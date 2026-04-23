import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  Lobby,
  JoinOrCreateLobbyRequest,
  JoinOrCreateLobbyResponse,
  LeaveLobbyRequest,
} from "./types";
import { createGameFromLobby, getDefaultGameSettings } from "./utils";

const db = getFirestore();

// ═══════════════════════════════════════════════════════════════
// JOIN OR CREATE LOBBY
// ═══════════════════════════════════════════════════════════════

export const joinOrCreateLobby = onCall<JoinOrCreateLobbyRequest>(
  async (request) => {
    console.log("=== JOIN OR CREATE LOBBY ===");

    // Validate auth
    if (!request.auth) {
      console.log("ERROR: Not authenticated");
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const playerId = request.auth.uid;
    const playerName = request.data.playerName || "Player";
    const dictionary = request.data.dictionary || "english";
    console.log("Player:", playerId, playerName, "dictionary:", dictionary);

    // Step 1: Check if player is already in an active lobby
    console.log("Step 1: Checking for existing lobby...");
    const existingLobby = await findExistingLobby(playerId);
    if (existingLobby) {
      console.log("Found existing lobby:", existingLobby.id, existingLobby.status);
      return {
        success: true,
        lobbyId: existingLobby.id,
        gameId: existingLobby.gameId,
        status: existingLobby.status,
        alreadyJoined: true,
      } as JoinOrCreateLobbyResponse;
    }
    console.log("No existing lobby found");

    // Step 2: Try to join an available lobby with the same dictionary
    console.log("Step 2: Trying to join available lobby...");
    const joinResult = await tryJoinAvailableLobby(playerId, playerName, dictionary);
    if (joinResult) {
      console.log("Joined lobby:", joinResult.lobbyId, "gameId:", joinResult.gameId);
      return joinResult;
    }
    console.log("No available lobby to join");

    // Step 3: No available lobbies - create new one
    console.log("Step 3: Creating new lobby...");
    const newLobby = await createNewLobby(playerId, playerName, dictionary);
    console.log("Created new lobby:", newLobby.lobbyId);
    return newLobby;
  }
);

/**
 * Find an existing *waiting* lobby the player is already in.
 * Only returns lobbies still in matchmaking ("waiting" status).
 * Active / finished games are NOT returned here — rejoining an
 * in-progress game is handled separately by the client-side
 * rejoin popup on the home screen.
 */
async function findExistingLobby(
  playerId: string
): Promise<(Lobby & { id: string }) | null> {
  const waitingSnapshot = await db
    .collection("lobbies")
    .where("playerIds", "array-contains", playerId)
    .where("status", "==", "waiting")
    .limit(1)
    .get();

  if (!waitingSnapshot.empty) {
    const doc = waitingSnapshot.docs[0];
    return { id: doc.id, ...doc.data() } as Lobby & { id: string };
  }

  return null;
}

/**
 * Try to join an available lobby with the same dictionary
 */
async function tryJoinAvailableLobby(
  playerId: string,
  playerName: string,
  dictionary: string
): Promise<JoinOrCreateLobbyResponse | null> {
  // Query for available lobbies matching the same dictionary
  const snapshot = await db
    .collection("lobbies")
    .where("status", "==", "waiting")
    .where("dictionary", "==", dictionary)
    .where("playerCount", "<", 2)
    .orderBy("playerCount") // Required for inequality
    .orderBy("createdAt", "asc") // Oldest first for fairness
    .limit(5) // Get a few in case of race conditions
    .get();

  // Try each lobby until one succeeds
  for (const lobbyDoc of snapshot.docs) {
    const result = await tryJoinLobbyTransaction(
      lobbyDoc.id,
      playerId,
      playerName,
      dictionary
    );
    if (result) {
      return result;
    }
  }

  return null;
}

/**
 * Attempt to join a specific lobby using a transaction
 */
async function tryJoinLobbyTransaction(
  lobbyId: string,
  playerId: string,
  playerName: string,
  dictionary: string
): Promise<JoinOrCreateLobbyResponse | null> {
  try {
    const result = await db.runTransaction(async (transaction) => {
      const lobbyRef = db.collection("lobbies").doc(lobbyId);
      const lobbyDoc = await transaction.get(lobbyRef);

      if (!lobbyDoc.exists) {
        throw new Error("LOBBY_NOT_FOUND");
      }

      const lobby = lobbyDoc.data() as Lobby;

      // Validate lobby is still joinable
      if (lobby.status !== "waiting") {
        throw new Error("LOBBY_NOT_WAITING");
      }
      if (lobby.playerCount >= lobby.maxPlayers) {
        throw new Error("LOBBY_FULL");
      }
      if (lobby.playerIds.includes(playerId)) {
        throw new Error("ALREADY_IN_LOBBY");
      }

      // Add player to lobby
      const updatedPlayerIds = [...lobby.playerIds, playerId];
      const updatedPlayerNames = { ...lobby.playerNames, [playerId]: playerName };
      const updatedPlayerCount = lobby.playerCount + 1;

      // Check if we should start the game
      let gameId: string | null = null;
      let newStatus: Lobby["status"] = "waiting";

      if (updatedPlayerCount >= lobby.minPlayers) {
        // CREATE GAME
        const gameRef = db.collection("games").doc();
        gameId = gameRef.id;
        newStatus = "started";

        const gameData = createGameFromLobby(
          lobbyId,
          updatedPlayerIds,
          updatedPlayerNames,
          getDefaultGameSettings(lobby.dictionary || dictionary)
        );

        transaction.set(gameRef, {
          ...gameData,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      // Update lobby
      transaction.update(lobbyRef, {
        playerIds: updatedPlayerIds,
        playerNames: updatedPlayerNames,
        playerCount: updatedPlayerCount,
        status: newStatus,
        gameId: gameId,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        lobbyId: lobbyId,
        gameId: gameId,
        status: newStatus,
      } as JoinOrCreateLobbyResponse;
    });

    return result;
  } catch (error) {
    // Expected errors from race conditions - try next lobby
    const errorMessage = error instanceof Error ? error.message : "";
    if (
      ["LOBBY_NOT_FOUND", "LOBBY_NOT_WAITING", "LOBBY_FULL"].includes(
        errorMessage
      )
    ) {
      return null;
    }
    throw error;
  }
}

/**
 * Create a new lobby, then immediately try to match with another waiting lobby
 * This helps prevent race conditions where two players both create lobbies
 */
async function createNewLobby(
  playerId: string,
  playerName: string,
  dictionary: string
): Promise<JoinOrCreateLobbyResponse> {
  const lobbyRef = db.collection("lobbies").doc();

  const lobbyData: Omit<Lobby, "createdAt" | "updatedAt"> = {
    hostId: playerId,
    hostDisplayName: playerName,
    playerIds: [playerId],
    playerNames: { [playerId]: playerName },
    playerCount: 1,
    minPlayers: 2,
    maxPlayers: 2,
    status: "waiting",
    gameId: null,
    dictionary,
  };

  await lobbyRef.set({
    ...lobbyData,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  console.log("Created lobby:", lobbyRef.id, "- now checking for other waiting lobbies...");

  // Immediately try to match with another waiting lobby to prevent race conditions
  const matchResult = await tryMatchWithWaitingLobby(lobbyRef.id, playerId, playerName, dictionary);
  if (matchResult) {
    console.log("Matched with another lobby! gameId:", matchResult.gameId);
    return matchResult;
  }

  return {
    success: true,
    lobbyId: lobbyRef.id,
    gameId: null,
    status: "waiting",
    created: true,
  };
}

/**
 * Try to match our newly created lobby with another waiting lobby
 * This handles the race condition where two players create lobbies simultaneously
 */
async function tryMatchWithWaitingLobby(
  ourLobbyId: string,
  playerId: string,
  playerName: string,
  dictionary: string
): Promise<JoinOrCreateLobbyResponse | null> {
  // Find other waiting lobbies (not ours) with the same dictionary
  const snapshot = await db
    .collection("lobbies")
    .where("status", "==", "waiting")
    .where("dictionary", "==", dictionary)
    .where("playerCount", "==", 1)
    .orderBy("createdAt", "asc")
    .limit(5)
    .get();

  // Try to match with each lobby (excluding ours)
  for (const lobbyDoc of snapshot.docs) {
    if (lobbyDoc.id === ourLobbyId) continue; // Skip our own lobby

    const result = await tryMergeLobbies(ourLobbyId, lobbyDoc.id, playerId, playerName, dictionary);
    if (result) {
      return result;
    }
  }

  return null;
}

/**
 * Merge two lobbies: cancel our lobby and join the other one
 */
async function tryMergeLobbies(
  ourLobbyId: string,
  otherLobbyId: string,
  playerId: string,
  playerName: string,
  dictionary: string
): Promise<JoinOrCreateLobbyResponse | null> {
  try {
    const result = await db.runTransaction(async (transaction) => {
      const ourLobbyRef = db.collection("lobbies").doc(ourLobbyId);
      const otherLobbyRef = db.collection("lobbies").doc(otherLobbyId);

      const [ourLobbyDoc, otherLobbyDoc] = await Promise.all([
        transaction.get(ourLobbyRef),
        transaction.get(otherLobbyRef),
      ]);

      if (!ourLobbyDoc.exists || !otherLobbyDoc.exists) {
        throw new Error("LOBBY_NOT_FOUND");
      }

      const ourLobby = ourLobbyDoc.data() as Lobby;
      const otherLobby = otherLobbyDoc.data() as Lobby;

      // Both lobbies must still be waiting with 1 player
      if (ourLobby.status !== "waiting" || otherLobby.status !== "waiting") {
        throw new Error("LOBBY_NOT_WAITING");
      }
      if (ourLobby.playerCount !== 1 || otherLobby.playerCount !== 1) {
        throw new Error("LOBBY_NOT_SINGLE");
      }

      // Cancel our lobby
      transaction.update(ourLobbyRef, {
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Join the other lobby and create game
      const updatedPlayerIds = [...otherLobby.playerIds, playerId];
      const updatedPlayerNames = { ...otherLobby.playerNames, [playerId]: playerName };

      const gameRef = db.collection("games").doc();
      const gameData = createGameFromLobby(
        otherLobbyId,
        updatedPlayerIds,
        updatedPlayerNames,
        getDefaultGameSettings(otherLobby.dictionary || dictionary)
      );

      transaction.set(gameRef, {
        ...gameData,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      transaction.update(otherLobbyRef, {
        playerIds: updatedPlayerIds,
        playerNames: updatedPlayerNames,
        playerCount: 2,
        status: "started",
        gameId: gameRef.id,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        lobbyId: otherLobbyId,
        gameId: gameRef.id,
        status: "started" as const,
      };
    });

    return result;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : "";
    if (["LOBBY_NOT_FOUND", "LOBBY_NOT_WAITING", "LOBBY_NOT_SINGLE"].includes(errorMessage)) {
      return null;
    }
    // For other errors (like transaction conflicts), just return null and let the lobby wait
    console.log("Merge failed:", errorMessage);
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════
// LEAVE LOBBY
// ═══════════════════════════════════════════════════════════════

export const leaveLobby = onCall<LeaveLobbyRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const playerId = request.auth.uid;
  const { lobbyId } = request.data;

  if (!lobbyId) {
    throw new HttpsError("invalid-argument", "Missing lobbyId");
  }

  await db.runTransaction(async (transaction) => {
    const lobbyRef = db.collection("lobbies").doc(lobbyId);
    const lobbyDoc = await transaction.get(lobbyRef);

    if (!lobbyDoc.exists) {
      throw new HttpsError("not-found", "Lobby not found");
    }

    const lobby = lobbyDoc.data() as Lobby;

    if (lobby.status !== "waiting") {
      throw new HttpsError(
        "failed-precondition",
        "Cannot leave - game already started"
      );
    }

    if (!lobby.playerIds.includes(playerId)) {
      throw new HttpsError("failed-precondition", "You are not in this lobby");
    }

    const updatedPlayerIds = lobby.playerIds.filter((id) => id !== playerId);
    const updatedPlayerNames = { ...lobby.playerNames };
    delete updatedPlayerNames[playerId];

    if (updatedPlayerIds.length === 0) {
      // Last player left - cancel lobby
      transaction.update(lobbyRef, {
        status: "cancelled",
        playerIds: [],
        playerNames: {},
        playerCount: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else {
      // Other players remain
      transaction.update(lobbyRef, {
        playerIds: updatedPlayerIds,
        playerNames: updatedPlayerNames,
        playerCount: updatedPlayerIds.length,
        hostId: updatedPlayerIds[0], // Reassign host
        hostDisplayName: updatedPlayerNames[updatedPlayerIds[0]],
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════
// CLEANUP STALE LOBBIES (Scheduled)
// ═══════════════════════════════════════════════════════════════

export const cleanupStaleLobbies = onSchedule("every 5 minutes", async () => {
  const staleThreshold = Timestamp.fromMillis(
    Date.now() - 10 * 60 * 1000 // 10 minutes ago
  );

  const staleLobbies = await db
    .collection("lobbies")
    .where("status", "==", "waiting")
    .where("updatedAt", "<", staleThreshold)
    .limit(50)
    .get();

  if (staleLobbies.empty) {
    console.log("No stale lobbies found");
    return;
  }

  const batch = db.batch();
  staleLobbies.docs.forEach((doc) => {
    batch.update(doc.ref, { status: "cancelled" });
  });
  await batch.commit();

  console.log(`Cancelled ${staleLobbies.size} stale lobbies`);
});
