import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  CreatePartyLobbyRequest,
  CreatePartyLobbyResponse,
  JoinPartyLobbyRequest,
  JoinPartyLobbyResponse,
  StartPartyGameRequest,
  StartPartyGameResponse,
  LeavePartyLobbyRequest,
  FriendChallenge,
  Friend,
  Lobby,
} from "./types";
import { createGameFromLobby, getDefaultGameSettings } from "./utils";

const db = getFirestore();

// Party invites expire after 5 minutes (longer than 1v1 challenges)
const PARTY_INVITE_EXPIRY_SECONDS = 300;

// ═══════════════════════════════════════════════════════════════
// CREATE PARTY LOBBY
// ═══════════════════════════════════════════════════════════════

export const createPartyLobby = onCall<CreatePartyLobbyRequest>(
  async (request): Promise<CreatePartyLobbyResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const hostId = request.auth.uid;
    const invitedFriendIds = request.data.invitedFriendIds;

    if (!invitedFriendIds || invitedFriendIds.length === 0) {
      throw new HttpsError("invalid-argument", "Must invite at least one friend");
    }

    if (invitedFriendIds.length > 3) {
      throw new HttpsError("invalid-argument", "Cannot invite more than 3 friends");
    }

    // Get host's profile
    const hostDoc = await db.collection("users").doc(hostId).get();
    if (!hostDoc.exists) {
      throw new HttpsError("not-found", "Your profile not found");
    }
    const hostData = hostDoc.data()!;
    const hostName = hostData.displayName || "Player";

    // Verify all invited users are accepted friends and online
    const invitedNames: Record<string, string> = {};
    for (const friendId of invitedFriendIds) {
      // Check friendship
      const friendDoc = await db
        .collection("users")
        .doc(hostId)
        .collection("friends")
        .doc(friendId)
        .get();

      if (!friendDoc.exists || (friendDoc.data() as Friend).status !== "accepted") {
        throw new HttpsError("failed-precondition", `User ${friendId} is not your friend`);
      }

      // Get friend's profile
      const userDoc = await db.collection("users").doc(friendId).get();
      if (!userDoc.exists) {
        throw new HttpsError("not-found", "Friend profile not found");
      }
      const userData = userDoc.data()!;

      if (!userData.isOnline) {
        throw new HttpsError(
          "failed-precondition",
          `${userData.displayName || "Friend"} is not online`
        );
      }

      invitedNames[friendId] = userData.displayName || "Player";
    }

    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(
      now.toMillis() + PARTY_INVITE_EXPIRY_SECONDS * 1000
    );

    // Create the party lobby
    const lobbyRef = db.collection("lobbies").doc();
    const lobbyData: Omit<Lobby, "createdAt" | "updatedAt"> = {
      hostId,
      hostDisplayName: hostName,
      playerIds: [hostId],
      playerNames: { [hostId]: hostName },
      playerCount: 1,
      minPlayers: 2,
      maxPlayers: invitedFriendIds.length + 1, // host + invited friends
      status: "waiting",
      gameId: null,
      isParty: true,
    };

    const batch = db.batch();

    // Create lobby
    batch.set(lobbyRef, {
      ...lobbyData,
      isPrivate: true,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Create one FriendChallenge per invited friend
    const challengeIds: string[] = [];
    for (const friendId of invitedFriendIds) {
      const challengeRef = db.collection("friendChallenges").doc();
      challengeIds.push(challengeRef.id);

      const challengeData: FriendChallenge = {
        challengerId: hostId,
        challengerName: hostName,
        challengedId: friendId,
        challengedName: invitedNames[friendId],
        status: "pending",
        gameId: null,
        lobbyId: lobbyRef.id,
        isParty: true,
        createdAt: now,
        expiresAt,
      };

      batch.set(challengeRef, challengeData);
    }

    await batch.commit();

    console.log(
      `Party lobby ${lobbyRef.id} created by ${hostName}, invited ${invitedFriendIds.length} friends`
    );

    return {
      lobbyId: lobbyRef.id,
      challengeIds,
    };
  }
);

// ═══════════════════════════════════════════════════════════════
// JOIN PARTY LOBBY
// ═══════════════════════════════════════════════════════════════

export const joinPartyLobby = onCall<JoinPartyLobbyRequest>(
  async (request): Promise<JoinPartyLobbyResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const { lobbyId, challengeId } = request.data;

    if (!lobbyId || !challengeId) {
      throw new HttpsError("invalid-argument", "Missing lobbyId or challengeId");
    }

    // Verify the challenge
    const challengeRef = db.collection("friendChallenges").doc(challengeId);
    const challengeDoc = await challengeRef.get();

    if (!challengeDoc.exists) {
      throw new HttpsError("not-found", "Invitation not found");
    }

    const challenge = challengeDoc.data() as FriendChallenge;

    if (challenge.challengedId !== userId) {
      throw new HttpsError("permission-denied", "This invitation is not for you");
    }

    if (challenge.status !== "pending") {
      throw new HttpsError("failed-precondition", `Invitation is ${challenge.status}`);
    }

    if (challenge.expiresAt.toMillis() < Date.now()) {
      await challengeRef.update({ status: "expired" });
      throw new HttpsError("failed-precondition", "Invitation has expired");
    }

    // Get user's profile for display name
    const userDoc = await db.collection("users").doc(userId).get();
    const userData = userDoc.data() || {};
    const userName = userData.displayName || "Player";

    // Join the lobby using a transaction
    const result = await db.runTransaction(async (transaction) => {
      const lobbyRef = db.collection("lobbies").doc(lobbyId);
      const lobbyDoc = await transaction.get(lobbyRef);

      if (!lobbyDoc.exists) {
        throw new HttpsError("not-found", "Lobby not found");
      }

      const lobby = lobbyDoc.data() as Lobby;

      if (lobby.status !== "waiting") {
        throw new HttpsError("failed-precondition", "Lobby is no longer accepting players");
      }

      if (lobby.playerIds.includes(userId)) {
        // Already in lobby - return current state
        return { lobbyId, playerCount: lobby.playerCount };
      }

      if (lobby.playerCount >= lobby.maxPlayers) {
        throw new HttpsError("failed-precondition", "Lobby is full");
      }

      // Add player to lobby
      const updatedPlayerIds = [...lobby.playerIds, userId];
      const updatedPlayerNames = { ...lobby.playerNames, [userId]: userName };
      const updatedPlayerCount = lobby.playerCount + 1;

      transaction.update(lobbyRef, {
        playerIds: updatedPlayerIds,
        playerNames: updatedPlayerNames,
        playerCount: updatedPlayerCount,
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Update challenge status to accepted
      transaction.update(challengeRef, { status: "accepted" });

      return { lobbyId, playerCount: updatedPlayerCount };
    });

    console.log(`${userName} joined party lobby ${lobbyId} (${result.playerCount} players)`);

    return result;
  }
);

// ═══════════════════════════════════════════════════════════════
// START PARTY GAME
// ═══════════════════════════════════════════════════════════════

export const startPartyGame = onCall<StartPartyGameRequest>(
  async (request): Promise<StartPartyGameResponse> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const { lobbyId } = request.data;

    if (!lobbyId) {
      throw new HttpsError("invalid-argument", "Missing lobbyId");
    }

    const result = await db.runTransaction(async (transaction) => {
      const lobbyRef = db.collection("lobbies").doc(lobbyId);
      const lobbyDoc = await transaction.get(lobbyRef);

      if (!lobbyDoc.exists) {
        throw new HttpsError("not-found", "Lobby not found");
      }

      const lobby = lobbyDoc.data() as Lobby;

      // Only host can start
      if (lobby.hostId !== userId) {
        throw new HttpsError("permission-denied", "Only the host can start the game");
      }

      if (lobby.status !== "waiting") {
        throw new HttpsError("failed-precondition", "Lobby is no longer in waiting state");
      }

      if (lobby.playerCount < 2) {
        throw new HttpsError("failed-precondition", "Need at least 2 players to start");
      }

      // Create the game using existing helper
      const gameRef = db.collection("games").doc();
      const gameData = createGameFromLobby(
        lobbyId,
        lobby.playerIds,
        lobby.playerNames,
        getDefaultGameSettings()
      );

      transaction.set(gameRef, {
        ...gameData,
        isPartyGame: true,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Update lobby to started
      transaction.update(lobbyRef, {
        status: "started",
        gameId: gameRef.id,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return { gameId: gameRef.id };
    });

    // Cancel remaining pending challenges for this lobby (outside transaction)
    const pendingChallenges = await db
      .collection("friendChallenges")
      .where("lobbyId", "==", lobbyId)
      .where("status", "==", "pending")
      .get();

    if (!pendingChallenges.empty) {
      const batch = db.batch();
      for (const doc of pendingChallenges.docs) {
        batch.update(doc.ref, { status: "expired" });
      }
      await batch.commit();
      console.log(`Cancelled ${pendingChallenges.size} pending invites for lobby ${lobbyId}`);
    }

    console.log(`Party game started in lobby ${lobbyId}, gameId: ${result.gameId}`);

    return result;
  }
);

// ═══════════════════════════════════════════════════════════════
// LEAVE PARTY LOBBY
// ═══════════════════════════════════════════════════════════════

export const leavePartyLobby = onCall<LeavePartyLobbyRequest>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const userId = request.auth.uid;
    const { lobbyId } = request.data;

    if (!lobbyId) {
      throw new HttpsError("invalid-argument", "Missing lobbyId");
    }

    const lobbyRef = db.collection("lobbies").doc(lobbyId);
    const lobbyDoc = await lobbyRef.get();

    if (!lobbyDoc.exists) {
      throw new HttpsError("not-found", "Lobby not found");
    }

    const lobby = lobbyDoc.data() as Lobby;

    if (lobby.status !== "waiting") {
      throw new HttpsError("failed-precondition", "Cannot leave - game already started");
    }

    if (!lobby.playerIds.includes(userId)) {
      throw new HttpsError("failed-precondition", "You are not in this lobby");
    }

    const batch = db.batch();

    if (lobby.hostId === userId) {
      // Host is leaving - cancel the entire lobby
      batch.update(lobbyRef, {
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Cancel all pending challenges for this lobby
      const pendingChallenges = await db
        .collection("friendChallenges")
        .where("lobbyId", "==", lobbyId)
        .where("status", "==", "pending")
        .get();

      for (const doc of pendingChallenges.docs) {
        batch.update(doc.ref, { status: "cancelled" });
      }
    } else {
      // Non-host is leaving - remove from lobby
      const updatedPlayerIds = lobby.playerIds.filter((id) => id !== userId);
      const updatedPlayerNames = { ...lobby.playerNames };
      delete updatedPlayerNames[userId];

      batch.update(lobbyRef, {
        playerIds: updatedPlayerIds,
        playerNames: updatedPlayerNames,
        playerCount: updatedPlayerIds.length,
        updatedAt: FieldValue.serverTimestamp(),
      });

      // Update their challenge to declined
      const userChallenge = await db
        .collection("friendChallenges")
        .where("lobbyId", "==", lobbyId)
        .where("challengedId", "==", userId)
        .where("status", "==", "accepted")
        .limit(1)
        .get();

      if (!userChallenge.empty) {
        batch.update(userChallenge.docs[0].ref, { status: "declined" });
      }
    }

    await batch.commit();

    console.log(`User ${userId} left party lobby ${lobbyId} (host: ${lobby.hostId === userId})`);

    return { success: true };
  }
);
