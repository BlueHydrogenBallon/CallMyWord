import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  ChallengeFriendRequest,
  ChallengeFriendResponse,
  AcceptFriendChallengeRequest,
  AcceptFriendChallengeResponse,
  DeclineFriendChallengeRequest,
  CancelFriendChallengeRequest,
  FriendChallenge,
  Friend,
  Lobby,
} from "./types";
import { createGameFromLobby, getDefaultGameSettings } from "./utils";

const db = getFirestore();

// Challenge expires after 60 seconds
const CHALLENGE_EXPIRY_SECONDS = 60;

// ═══════════════════════════════════════════════════════════════
// CHALLENGE FRIEND
// ═══════════════════════════════════════════════════════════════

export const challengeFriend = onCall<ChallengeFriendRequest>(
  async (request): Promise<ChallengeFriendResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const challengerId = request.auth.uid;
    const challengedId = request.data.friendUserId;

    if (!challengedId) {
      throw new HttpsError("invalid-argument", "Missing friendUserId");
    }

    // Get challenger's profile
    const challengerDoc = await db.collection("users").doc(challengerId).get();
    if (!challengerDoc.exists) {
      throw new HttpsError("not-found", "Your profile not found");
    }
    const challengerData = challengerDoc.data()!;

    // Verify they are friends
    const friendDoc = await db
      .collection("users")
      .doc(challengerId)
      .collection("friends")
      .doc(challengedId)
      .get();

    if (!friendDoc.exists || (friendDoc.data() as Friend).status !== "accepted") {
      throw new HttpsError("failed-precondition", "You are not friends with this user");
    }

    // Get challenged user's profile
    const challengedDoc = await db.collection("users").doc(challengedId).get();
    if (!challengedDoc.exists) {
      throw new HttpsError("not-found", "Friend's profile not found");
    }
    const challengedData = challengedDoc.data()!;

    // Verify challenged user is online
    if (!challengedData.isOnline) {
      throw new HttpsError("failed-precondition", "Friend is not online");
    }

    // Check for existing pending challenge between these users
    const existingChallenge = await db
      .collection("friendChallenges")
      .where("challengerId", "==", challengerId)
      .where("challengedId", "==", challengedId)
      .where("status", "==", "pending")
      .limit(1)
      .get();

    if (!existingChallenge.empty) {
      throw new HttpsError("already-exists", "You already have a pending challenge to this friend");
    }

    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + CHALLENGE_EXPIRY_SECONDS * 1000
    );

    // Create a private lobby for this challenge
    const lobbyRef = db.collection("lobbies").doc();
    const lobbyData: Omit<Lobby, "createdAt" | "updatedAt"> = {
      hostId: challengerId,
      hostDisplayName: challengerData.displayName || "Player",
      playerIds: [challengerId],
      playerNames: { [challengerId]: challengerData.displayName || "Player" },
      playerCount: 1,
      minPlayers: 2,
      maxPlayers: 2,
      status: "waiting",
      gameId: null,
    };

    // Create the challenge
    const challengeRef = db.collection("friendChallenges").doc();
    const challengeData: FriendChallenge = {
      challengerId,
      challengerName: challengerData.displayName || "Player",
      challengedId,
      challengedName: challengedData.displayName || "Player",
      status: "pending",
      gameId: null,
      lobbyId: lobbyRef.id,
      createdAt: now,
      expiresAt,
    };

    // Write both documents
    const batch = db.batch();
    batch.set(lobbyRef, {
      ...lobbyData,
      isPrivate: true, // Mark as private so it doesn't appear in matchmaking
      friendChallengeId: challengeRef.id,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    batch.set(challengeRef, challengeData);
    await batch.commit();

    return {
      challengeId: challengeRef.id,
      lobbyId: lobbyRef.id,
    };
  }
);

// ═══════════════════════════════════════════════════════════════
// ACCEPT FRIEND CHALLENGE
// ═══════════════════════════════════════════════════════════════

export const acceptFriendChallenge = onCall<AcceptFriendChallengeRequest>(
  async (request): Promise<AcceptFriendChallengeResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const challengeId = request.data.challengeId;

    if (!challengeId) {
      throw new HttpsError("invalid-argument", "Missing challengeId");
    }

    // Get the challenge
    const challengeRef = db.collection("friendChallenges").doc(challengeId);
    const challengeDoc = await challengeRef.get();

    if (!challengeDoc.exists) {
      throw new HttpsError("not-found", "Challenge not found");
    }

    const challenge = challengeDoc.data() as FriendChallenge;

    // Verify user is the challenged player
    if (challenge.challengedId !== userId) {
      throw new HttpsError("permission-denied", "You are not the challenged player");
    }

    // Verify challenge is still pending
    if (challenge.status !== "pending") {
      throw new HttpsError("failed-precondition", `Challenge is ${challenge.status}`);
    }

    // Verify challenge hasn't expired
    if (challenge.expiresAt.toMillis() < Date.now()) {
      await challengeRef.update({ status: "expired" });
      throw new HttpsError("failed-precondition", "Challenge has expired");
    }

    // Get user's profile for name
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data() || {};

    // Get the lobby
    const lobbyId = challenge.lobbyId;
    if (!lobbyId) {
      throw new HttpsError("internal", "Challenge has no associated lobby");
    }

    const lobbyRef = db.collection("lobbies").doc(lobbyId);

    // Create game from lobby using transaction
    const result = await db.runTransaction(async (transaction) => {
      const lobbyDoc = await transaction.get(lobbyRef);

      if (!lobbyDoc.exists) {
        throw new HttpsError("not-found", "Lobby not found");
      }

      const lobby = lobbyDoc.data() as Lobby;

      if (lobby.status !== "waiting") {
        throw new HttpsError("failed-precondition", "Lobby is no longer available");
      }

      // Add challenged player to lobby
      const updatedPlayerIds = [...lobby.playerIds, userId];
      const updatedPlayerNames = {
        ...lobby.playerNames,
        [userId]: userData.displayName || "Player",
      };

      // Create the game
      const gameRef = db.collection("games").doc();
      const gameData = createGameFromLobby(
        lobbyId,
        updatedPlayerIds,
        updatedPlayerNames,
        getDefaultGameSettings()
      );

      transaction.set(gameRef, {
        ...gameData,
        isFriendGame: true,
        friendChallengeId: challengeId,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Update lobby
      transaction.update(lobbyRef, {
        playerIds: updatedPlayerIds,
        playerNames: updatedPlayerNames,
        playerCount: 2,
        status: "started",
        gameId: gameRef.id,
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Update challenge
      transaction.update(challengeRef, {
        status: "accepted",
        gameId: gameRef.id,
      });

      return {
        gameId: gameRef.id,
        lobbyId: lobbyId,
      };
    });

    return result;
  }
);

// ═══════════════════════════════════════════════════════════════
// DECLINE FRIEND CHALLENGE
// ═══════════════════════════════════════════════════════════════

export const declineFriendChallenge = onCall<DeclineFriendChallengeRequest>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const challengeId = request.data.challengeId;

    if (!challengeId) {
      throw new HttpsError("invalid-argument", "Missing challengeId");
    }

    const challengeRef = db.collection("friendChallenges").doc(challengeId);
    const challengeDoc = await challengeRef.get();

    if (!challengeDoc.exists) {
      throw new HttpsError("not-found", "Challenge not found");
    }

    const challenge = challengeDoc.data() as FriendChallenge;

    // Verify user is the challenged player
    if (challenge.challengedId !== userId) {
      throw new HttpsError("permission-denied", "You are not the challenged player");
    }

    // Verify challenge is still pending
    if (challenge.status !== "pending") {
      throw new HttpsError("failed-precondition", `Challenge is already ${challenge.status}`);
    }

    const batch = db.batch();

    // Update challenge status
    batch.update(challengeRef, { status: "declined" });

    // Cancel the associated lobby
    if (challenge.lobbyId) {
      const lobbyRef = db.collection("lobbies").doc(challenge.lobbyId);
      batch.update(lobbyRef, {
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    return { success: true };
  }
);

// ═══════════════════════════════════════════════════════════════
// CANCEL FRIEND CHALLENGE
// ═══════════════════════════════════════════════════════════════

export const cancelFriendChallenge = onCall<CancelFriendChallengeRequest>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const challengeId = request.data.challengeId;

    if (!challengeId) {
      throw new HttpsError("invalid-argument", "Missing challengeId");
    }

    const challengeRef = db.collection("friendChallenges").doc(challengeId);
    const challengeDoc = await challengeRef.get();

    if (!challengeDoc.exists) {
      throw new HttpsError("not-found", "Challenge not found");
    }

    const challenge = challengeDoc.data() as FriendChallenge;

    // Verify user is the challenger
    if (challenge.challengerId !== userId) {
      throw new HttpsError("permission-denied", "You are not the challenger");
    }

    // Verify challenge is still pending
    if (challenge.status !== "pending") {
      throw new HttpsError("failed-precondition", `Challenge is already ${challenge.status}`);
    }

    const batch = db.batch();

    // Update challenge status
    batch.update(challengeRef, { status: "cancelled" });

    // Cancel the associated lobby
    if (challenge.lobbyId) {
      const lobbyRef = db.collection("lobbies").doc(challenge.lobbyId);
      batch.update(lobbyRef, {
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    return { success: true };
  }
);

// ═══════════════════════════════════════════════════════════════
// CLEANUP EXPIRED CHALLENGES (Scheduled)
// ═══════════════════════════════════════════════════════════════

export const cleanupExpiredChallenges = onSchedule("every 1 minutes", async () => {
  const now = Timestamp.now();

  // Find pending challenges that have expired
  const expiredChallenges = await db
    .collection("friendChallenges")
    .where("status", "==", "pending")
    .where("expiresAt", "<", now)
    .limit(50)
    .get();

  if (expiredChallenges.empty) {
    console.log("No expired challenges found");
    return;
  }

  const batch = db.batch();

  for (const doc of expiredChallenges.docs) {
    const challenge = doc.data() as FriendChallenge;

    // Update challenge to expired
    batch.update(doc.ref, { status: "expired" });

    // Cancel the associated lobby
    if (challenge.lobbyId) {
      const lobbyRef = db.collection("lobbies").doc(challenge.lobbyId);
      batch.update(lobbyRef, {
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  }

  await batch.commit();
  console.log(`Expired ${expiredChallenges.size} challenges`);
});
