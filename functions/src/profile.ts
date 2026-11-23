import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import {
  SetUsernameRequest,
  SetUsernameResponse,
  GetGameHistoryRequest,
  GetGameHistoryResponse,
  GameHistorySummary,
  Game,
} from "./types";

const db = getFirestore();

// ═══════════════════════════════════════════════════════════════
// SET USERNAME (with uniqueness enforcement)
// ═══════════════════════════════════════════════════════════════

export const setUsername = onCall<SetUsernameRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const { username } = request.data;

  if (!username || typeof username !== "string") {
    throw new HttpsError("invalid-argument", "Username is required");
  }

  // Normalize to lowercase
  const normalizedUsername = username.toLowerCase().trim();

  // Validate format: 3-20 chars, alphanumeric + underscores
  const usernameRegex = /^[a-z0-9_]{3,20}$/;
  if (!usernameRegex.test(normalizedUsername)) {
    throw new HttpsError(
      "invalid-argument",
      "Username must be 3-20 characters, using only letters, numbers, and underscores"
    );
  }

  const usernameRef = db.collection("usernames").doc(normalizedUsername);
  const userRef = db.collection("users").doc(userId);

  const result = await db.runTransaction(async (transaction) => {
    // Check if username is already taken
    const usernameDoc = await transaction.get(usernameRef);
    if (usernameDoc.exists) {
      const existingUserId = usernameDoc.data()?.userId;
      if (existingUserId !== userId) {
        throw new HttpsError("already-exists", "Username is already taken");
      }
      // User already owns this username — no-op
      return { success: true, username: normalizedUsername };
    }

    // Get current user profile to check for existing username
    const userDoc = await transaction.get(userRef);
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User profile not found");
    }

    const oldUsername = userDoc.data()?.username as string | null;

    // Delete old username reservation if exists
    if (oldUsername && oldUsername !== normalizedUsername) {
      const oldUsernameRef = db.collection("usernames").doc(oldUsername);
      transaction.delete(oldUsernameRef);
    }

    // Reserve new username
    transaction.set(usernameRef, {
      userId,
      createdAt: FieldValue.serverTimestamp(),
    });

    // Update user profile
    transaction.update(userRef, {
      username: normalizedUsername,
      lastActiveAt: FieldValue.serverTimestamp(),
    });

    return { success: true, username: normalizedUsername } as SetUsernameResponse;
  });

  return result;
});

// ═══════════════════════════════════════════════════════════════
// GET GAME HISTORY
// ═══════════════════════════════════════════════════════════════

export const getGameHistory = onCall<GetGameHistoryRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const userId = request.auth.uid;
  const limit = Math.min(request.data?.limit ?? 20, 50);

  const gamesSnapshot = await db
    .collection("games")
    .where("playerIds", "array-contains", userId)
    .where("status", "==", "completed")
    .orderBy("updatedAt", "desc")
    .limit(limit)
    .get();

  const games: GameHistorySummary[] = gamesSnapshot.docs.map((doc) => {
    const game = doc.data() as Game;
    const playerScore = game.players[userId]?.score ?? 0;

    const opponentNames: string[] = [];
    const opponentScores: Record<string, number> = {};

    for (const [pid, player] of Object.entries(game.players)) {
      if (pid !== userId) {
        opponentNames.push(player.displayName);
        opponentScores[player.displayName] = player.score;
      }
    }

    return {
      gameId: doc.id,
      opponentNames,
      playerScore,
      opponentScores,
      won: game.winnerId === userId,
      endReason: game.endReason,
      completedAt: game.updatedAt,
    };
  });

  return { games } as GetGameHistoryResponse;
});

// ═══════════════════════════════════════════════════════════════
// ON GAME COMPLETED — Update player stats automatically
// ═══════════════════════════════════════════════════════════════

export const onGameCompleted = onDocumentUpdated("games/{gameId}", async (event) => {
  const before = event.data?.before.data() as Game | undefined;
  const after = event.data?.after.data() as Game | undefined;

  if (!before || !after) return;

  // Only trigger when status changes to "completed"
  if (before.status === "completed" || after.status !== "completed") return;

  const winnerId = after.winnerId;
  const batch = db.batch();

  for (const playerId of after.playerIds) {
    const userRef = db.collection("users").doc(playerId);
    const playerScore = after.players[playerId]?.score ?? 0;

    const updates: Record<string, unknown> = {
      gamesPlayed: FieldValue.increment(1),
      totalPointsScored: FieldValue.increment(playerScore),
    };

    if (playerId === winnerId) {
      updates.gamesWon = FieldValue.increment(1);
    }

    batch.update(userRef, updates);
  }

  await batch.commit();
});
