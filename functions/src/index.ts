/**
 * Call My Word - Firebase Cloud Functions
 *
 * This file exports all Cloud Functions for the game:
 * - Matchmaking: joinOrCreateLobby, leaveLobby, cleanupStaleLobbies
 * - Game Actions: submitMove, initiateChallenge, respondToChallenge, callWord, respondToWordCall, checkChallengeTimeouts
 * - Friends: generateInviteCode, addFriendByCode, acceptFriendRequest, declineFriendRequest, removeFriend, blockFriend
 * - Friend Challenges: challengeFriend, acceptFriendChallenge, declineFriendChallenge, cancelFriendChallenge, cleanupExpiredChallenges
 * - Presence: onUserPresenceChange, cleanupStalePresence
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
  callWord,
  respondToWordCall,
  checkChallengeTimeouts,
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
export {
  onUserPresenceChange,
  cleanupStalePresence,
} from "./presence";

// Export party (multiplayer) functions
export {
  createPartyLobby,
  joinPartyLobby,
  startPartyGame,
  leavePartyLobby,
} from "./party";
