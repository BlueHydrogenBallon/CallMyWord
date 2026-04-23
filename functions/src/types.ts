import { Timestamp } from "firebase-admin/firestore";

// ═══════════════════════════════════════════════════════════════
// USER TYPES
// ═══════════════════════════════════════════════════════════════

export interface UserProfile {
  displayName: string;
  username: string | null;
  avatarUrl: string | null;
  gamesPlayed: number;
  gamesWon: number;
  totalPointsScored: number;
  isAnonymous: boolean;
  createdAt: Timestamp;
  lastActiveAt: Timestamp;
}

// ═══════════════════════════════════════════════════════════════
// PROFILE FUNCTION REQUEST/RESPONSE TYPES
// ═══════════════════════════════════════════════════════════════

export interface SetUsernameRequest {
  username: string;
}

export interface SetUsernameResponse {
  success: boolean;
  username: string;
}

export interface GetGameHistoryRequest {
  limit?: number;
}

export interface GameHistorySummary {
  gameId: string;
  opponentNames: string[];
  playerScore: number;
  opponentScores: Record<string, number>;
  won: boolean;
  endReason: string | null;
  completedAt: Timestamp;
}

export interface GetGameHistoryResponse {
  games: GameHistorySummary[];
}

// ═══════════════════════════════════════════════════════════════
// LOBBY TYPES
// ═══════════════════════════════════════════════════════════════

export type LobbyStatus = "waiting" | "starting" | "started" | "cancelled";

export interface Lobby {
  hostId: string;
  hostDisplayName: string;
  playerIds: string[];
  playerNames: Record<string, string>;
  playerCount: number;
  minPlayers: number;
  maxPlayers: number;
  status: LobbyStatus;
  gameId: string | null;
  isParty?: boolean;
  dictionary?: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

// ═══════════════════════════════════════════════════════════════
// GAME TYPES
// ═══════════════════════════════════════════════════════════════

export type GameStatus = "in_progress" | "challenge_pending" | "word_call_pending" | "completed" | "abandoned" | "waiting_for_rejoin";

export interface Player {
  displayName: string;
  score: number;
  lives: number;
  isEliminated: boolean;
  joinOrder: number;
}

export interface PendingChallenge {
  challengerId: string;
  challengerName: string;
  challengedPlayerId: string;
  challengedPlayerName: string;
  wordFragment: string;
  responseDeadline: Timestamp;
  createdAt: Timestamp;
  // Multi-player: other players can join the challenge or pass
  // Key = playerId, value = their vote
  otherPlayerVotes?: Record<string, ChallengeVote>;
  // IDs of other players (not challenger, not challenged) who can vote
  otherPlayerIds?: string[];
}

export interface ChallengeVote {
  type: "join" | "pass";
  playerName: string;
  votedAt: Timestamp;
}

export interface PendingWordCall {
  callerId: string;
  callerName: string;
  // Legacy single-responder fields (kept for 2-player backward compat)
  responderId: string;
  responderName: string;
  wordFragment: string;
  calledWord: string;
  responseDeadline: Timestamp;
  createdAt: Timestamp;
  // Multi-player: all non-caller players vote independently
  // Key = playerId, value = their response
  responderVotes?: Record<string, WordCallVote>;
  // IDs of all players who can vote (everyone except caller)
  allResponderIds?: string[];
}

export interface WordCallVote {
  type: "continue" | "challenge" | "accept";
  continuationWord?: string | null;
  playerName: string;
  votedAt: Timestamp;
}

export interface ScoringDetails {
  wordPot: number;
  wordBonus: number | null;
  bluffBonus: number | null;
  totalAwarded: number;
  awardedTo: string;
  awardedToName: string;
  breakdown: string;
}

export interface LastAction {
  playerId: string;
  playerName: string;
  type: string;
  letter: string | null;
  letterPoints?: number;
  previousWord: string;
  resultingWord: string;
  wordPotBefore?: number;
  wordPotAfter?: number;
  challengeResult?: ChallengeResult;
  scoringDetails: ScoringDetails | null;
  timestamp: Timestamp;
}

export interface ChallengeResult {
  challengerId: string;
  challengerName: string;
  challengedPlayerId: string;
  challengedPlayerName: string;
  wordFragment: string;
  claimedWord: string | null;
  wasWordValid: boolean;
  failureReason: string | null;
  loserId: string;
  loserName: string;
  livesLost: number;
  wasEliminated: boolean;
}

export interface ChallengeHistoryEntry {
  wordFragment: string;
  claimedWord: string | null;
  wasWordValid: boolean;
  winnerId: string;
  winnerName: string;
  pointsAwarded: number;
  timestamp: Timestamp;
  // Player attribution
  challengerName?: string;
  challengedPlayerName?: string;
  // Multi-player: per-player scoring breakdown
  playerResults?: Record<string, ChallengePlayerResult>;
}

export interface ChallengePlayerResult {
  joined: boolean;
  pointsAwarded: number;
}

export interface WordCallHistoryEntry {
  wordFragment: string;
  calledWord: string;
  responseType: "continue" | "challenge" | "accept" | "timeout";
  continuationWord: string | null;
  wasCalledWordValid: boolean;
  wasContinuationValid: boolean | null;
  winnerId: string | null;
  winnerName: string | null;
  pointsAwarded: number;
  timestamp: Timestamp;
  // Player attribution
  callerName?: string;
  responderName?: string;
  // Multi-player: per-player scoring breakdown
  playerResults?: Record<string, WordCallPlayerResult>;
}

export interface WordCallPlayerResult {
  responseType: "continue" | "challenge" | "accept" | "timeout";
  continuationWord?: string;
  wasContinuationValid?: boolean;
  pointsAwarded: number;
  won: boolean;
}

export interface GameSettings {
  dictionary: string;
  startingLives: number;
  turnTimeoutSeconds: number | null;
  challengeResponseSeconds: number;
  minWordLength: number;
  minFragmentToChallenge: number;
  targetScore: number;
}

export interface Game {
  lobbyId: string;
  playerIds: string[];
  players: Record<string, Player>;
  currentWord: string;
  wordPot: number;
  currentPlayerIndex: number;
  turnNumber: number;
  wordTurnNumber: number;
  turnDeadline: Timestamp | null;
  status: GameStatus;
  pendingChallenge: PendingChallenge | null;
  pendingWordCall: PendingWordCall | null;
  lastAction: LastAction | null;
  challengeHistory: ChallengeHistoryEntry[];
  wordCallHistory: WordCallHistoryEntry[];
  winnerId: string | null;
  winnerName: string | null;
  endReason: string | null;
  abandonedBy?: string;
  rejoinDeadline?: Timestamp;
  settings: GameSettings;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

// ═══════════════════════════════════════════════════════════════
// FUNCTION REQUEST/RESPONSE TYPES
// ═══════════════════════════════════════════════════════════════

export interface JoinOrCreateLobbyRequest {
  playerName: string;
  dictionary?: string;
}

export interface JoinOrCreateLobbyResponse {
  success: boolean;
  lobbyId: string;
  gameId: string | null;
  status: LobbyStatus;
  alreadyJoined?: boolean;
  created?: boolean;
}

export interface LeaveLobbyRequest {
  lobbyId: string;
}

export interface SubmitMoveRequest {
  gameId: string;
  letter: string;
}

export interface InitiateChallengeRequest {
  gameId: string;
}

export interface RespondToChallengeRequest {
  gameId: string;
  claimedWord: string;
}

export interface CallWordRequest {
  gameId: string;
  calledWord: string;
}

export type WordCallResponseType = "continue" | "challenge" | "accept";

export interface RespondToWordCallRequest {
  gameId: string;
  responseType: WordCallResponseType;
  continuationWord?: string;
}

// Multi-player: other players vote on an active challenge
export interface VoteOnChallengeRequest {
  gameId: string;
  vote: "join" | "pass";
}

// ═══════════════════════════════════════════════════════════════
// FRIEND TYPES
// ═══════════════════════════════════════════════════════════════

export type FriendStatus = "pending" | "accepted" | "blocked";

export interface Friend {
  displayName: string;
  avatarUrl: string | null;
  status: FriendStatus;
  isOnline: boolean;
  lastActiveAt: Timestamp | null;
  createdAt: Timestamp;
  addedBy: string;
}

export type FriendChallengeStatus = "pending" | "accepted" | "declined" | "expired" | "cancelled";

export interface FriendChallenge {
  challengerId: string;
  challengerName: string;
  challengedId: string;
  challengedName: string;
  status: FriendChallengeStatus;
  gameId: string | null;
  lobbyId: string | null;
  isParty?: boolean;
  createdAt: Timestamp;
  expiresAt: Timestamp;
}

// ═══════════════════════════════════════════════════════════════
// FRIEND FUNCTION REQUEST/RESPONSE TYPES
// ═══════════════════════════════════════════════════════════════

export interface AddFriendByCodeRequest {
  inviteCode: string;
}

export interface AcceptFriendRequestRequest {
  friendUserId: string;
}

export interface DeclineFriendRequestRequest {
  friendUserId: string;
}

export interface RemoveFriendRequest {
  friendUserId: string;
}

export interface BlockFriendRequest {
  friendUserId: string;
}

export interface GenerateInviteCodeResponse {
  inviteCode: string;
}

export interface ChallengeFriendRequest {
  friendUserId: string;
}

export interface ChallengeFriendResponse {
  challengeId: string;
  lobbyId: string | null;
}

export interface AcceptFriendChallengeRequest {
  challengeId: string;
}

export interface AcceptFriendChallengeResponse {
  gameId: string;
  lobbyId: string;
}

export interface DeclineFriendChallengeRequest {
  challengeId: string;
}

export interface CancelFriendChallengeRequest {
  challengeId: string;
}

// ═══════════════════════════════════════════════════════════════
// PARTY (MULTIPLAYER) FUNCTION REQUEST/RESPONSE TYPES
// ═══════════════════════════════════════════════════════════════

export interface CreatePartyLobbyRequest {
  invitedFriendIds: string[];
  dictionary?: string;
}

export interface CreatePartyLobbyResponse {
  lobbyId: string;
  challengeIds: string[];
}

export interface JoinPartyLobbyRequest {
  lobbyId: string;
  challengeId: string;
}

export interface JoinPartyLobbyResponse {
  lobbyId: string;
  playerCount: number;
}

export interface StartPartyGameRequest {
  lobbyId: string;
}

export interface StartPartyGameResponse {
  gameId: string;
}

export interface LeavePartyLobbyRequest {
  lobbyId: string;
}
