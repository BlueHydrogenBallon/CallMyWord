import { Timestamp } from "firebase-admin/firestore";
import { Game, GameSettings, Player } from "../types";

/**
 * Get the next player index, skipping eliminated players
 */
export function getNextPlayerIndex(
  playerIds: string[],
  players: Record<string, Player>,
  currentIndex: number
): number {
  const playerCount = playerIds.length;
  let nextIndex = (currentIndex + 1) % playerCount;

  // Skip eliminated players
  let attempts = 0;
  while (players[playerIds[nextIndex]].isEliminated && attempts < playerCount) {
    nextIndex = (nextIndex + 1) % playerCount;
    attempts++;
  }

  return nextIndex;
}

/**
 * Get the previous player index (who made the last move), skipping eliminated players
 */
export function getPreviousPlayerIndex(
  playerIds: string[],
  players: Record<string, Player>,
  currentIndex: number
): number {
  const playerCount = playerIds.length;
  let prevIndex = (currentIndex - 1 + playerCount) % playerCount;

  // Skip eliminated players going backwards
  let attempts = 0;
  while (players[playerIds[prevIndex]].isEliminated && attempts < playerCount) {
    prevIndex = (prevIndex - 1 + playerCount) % playerCount;
    attempts++;
  }

  return prevIndex;
}

/**
 * Calculate the turn deadline based on settings
 */
export function calculateTurnDeadline(settings: GameSettings): Timestamp | null {
  if (!settings.turnTimeoutSeconds) {
    return null;
  }

  const deadline = new Date();
  deadline.setSeconds(deadline.getSeconds() + settings.turnTimeoutSeconds);
  return Timestamp.fromDate(deadline);
}

/**
 * Calculate the challenge response deadline
 */
export function calculateChallengeDeadline(settings: GameSettings): Timestamp {
  const deadline = new Date();
  deadline.setSeconds(deadline.getSeconds() + settings.challengeResponseSeconds);
  return Timestamp.fromDate(deadline);
}

/**
 * Count remaining (non-eliminated) players
 */
export function countRemainingPlayers(
  playerIds: string[],
  players: Record<string, Player>
): number {
  return playerIds.filter((id) => !players[id].isEliminated).length;
}

/**
 * Get the ID of the remaining player (for game over scenarios)
 */
export function getRemainingPlayerId(
  playerIds: string[],
  players: Record<string, Player>
): string | null {
  const remaining = playerIds.filter((id) => !players[id].isEliminated);
  return remaining.length === 1 ? remaining[0] : null;
}

/**
 * Default game settings
 */
export function getDefaultGameSettings(): GameSettings {
  return {
    dictionary: "english",
    startingLives: 3,
    turnTimeoutSeconds: 60,
    challengeResponseSeconds: 30,
    minWordLength: 4,
    minFragmentToChallenge: 2,
    targetScore: 50,
  };
}

/**
 * Create initial player state
 */
export function createPlayerState(
  displayName: string,
  joinOrder: number,
  startingLives: number
): Player {
  return {
    displayName,
    score: 0,
    lives: startingLives,
    isEliminated: false,
    joinOrder,
  };
}

/**
 * Create a new game from lobby data
 */
export function createGameFromLobby(
  lobbyId: string,
  playerIds: string[],
  playerNames: Record<string, string>,
  settings: GameSettings = getDefaultGameSettings()
): Omit<Game, "createdAt" | "updatedAt"> {
  // Build players map
  const players: Record<string, Player> = {};
  playerIds.forEach((playerId, index) => {
    players[playerId] = createPlayerState(
      playerNames[playerId],
      index,
      settings.startingLives
    );
  });

  // Randomly select who goes first
  const firstPlayerIndex = Math.floor(Math.random() * playerIds.length);

  return {
    lobbyId,
    playerIds,
    players,
    currentWord: "",
    wordPot: 0,
    currentPlayerIndex: firstPlayerIndex,
    turnNumber: 0,
    turnDeadline: calculateTurnDeadline(settings),
    status: "in_progress",
    pendingChallenge: null,
    lastAction: null,
    challengeHistory: [],
    pendingWordCall: null,
    wordCallHistory: [],
    winnerId: null,
    winnerName: null,
    endReason: null,
    settings,
  };
}
