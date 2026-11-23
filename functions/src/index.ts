/**
 * Call My Word - Firebase Cloud Functions
 *
 * This file exports all Cloud Functions for the game:
 * - Matchmaking: joinOrCreateLobby, leaveLobby, cleanupStaleLobbies
 * - Game Actions: submitMove, initiateChallenge, respondToChallenge, callWord, respondToWordCall, checkChallengeTimeouts
 * - Friends: generateInviteCode, addFriendByCode, acceptFriendRequest, declineFriendRequest, removeFriend, blockFriend
 * - Friend Challenges: challengeFriend, acceptFriendChallenge, declineFriendChallenge, cancelFriendChallenge, cleanupExpiredChallenges
 * - Presence: onUserPresenceChange (RTDB trigger)
 */

import { initializeApp } from "firebase-admin/app";

// Initialize Firebase Admin SDK
initializeApp();

// Export matchmaking functions
export {
  joinOrCreateLobby,
  leaveLobby,
  cleanupStaleLobbies,
} from "./matchmaking";

// Export game action functions
export {
  submitMove,
  initiateChallenge,
  respondToChallenge,
  voteOnChallenge,
  callWord,
  respondToWordCall,
  checkChallengeTimeouts,
  abandonGame,
  rejoinGame,
  claimAbandonWin,
  cleanupStaleGames,
} from "./game-actions";

// Export friend functions
export {
  generateInviteCode,
  addFriendByCode,
  acceptFriendRequest,
  declineFriendRequest,
  removeFriend,
  blockFriend,
} from "./friends";

// Export friend challenge functions
export {
  challengeFriend,
  acceptFriendChallenge,
  declineFriendChallenge,
  cancelFriendChallenge,
  cleanupExpiredChallenges,
} from "./friend-challenges";

// Export presence functions
// onUserPresenceChange listens to RTDB /status/{userId} and mirrors to Firestore.
// Uses the friendOf reverse index — O(1) reads + O(friends) writes.
// No scheduled cleanup needed — RTDB onDisconnect() handles offline detection.
export {
  onUserPresenceChange,
} from "./presence";

// Export party (multiplayer) functions
export {
  createPartyLobby,
  joinPartyLobby,
  startPartyGame,
  leavePartyLobby,
} from "./party";

// Export profile functions
export {
  setUsername,
  getGameHistory,
  onGameCompleted,
} from "./profile";
