/**
 * Scrabble-style letter point values
 */
const LETTER_POINTS: Record<string, number> = {
  A: 1, B: 3, C: 3, D: 2, E: 1,
  F: 4, G: 2, H: 4, I: 1, J: 8,
  K: 5, L: 1, M: 3, N: 1, O: 1,
  P: 3, Q: 10, R: 1, S: 1, T: 1,
  U: 1, V: 4, W: 4, X: 8, Y: 4,
  Z: 10,
};

/**
 * Get the point value for a single letter
 */
export function getLetterPoints(letter: string): number {
  return LETTER_POINTS[letter.toUpperCase()] || 0;
}

/**
 * Calculate the word pot (sum of all letter points)
 */
export function calculateWordPot(word: string): number {
  let total = 0;
  for (const letter of word.toUpperCase()) {
    total += getLetterPoints(letter);
  }
  return total;
}

export interface ScoringResult {
  winnerId: string;
  winnerName: string;
  wordPot: number;
  wordBonus: number | null;
  bluffBonus: number | null;
  totalAwarded: number;
  breakdown: string;
}

/**
 * Calculate scoring when defender successfully proves their word
 * Defender gets: Word Pot + Word Bonus
 */
export function calculateDefenderWinScore(
  wordFragment: string,
  claimedWord: string,
  defenderId: string,
  defenderName: string
): ScoringResult {
  const wordPot = calculateWordPot(wordFragment);
  const wordBonus = claimedWord.length - wordFragment.length;
  const totalAwarded = wordPot + wordBonus;

  return {
    winnerId: defenderId,
    winnerName: defenderName,
    wordPot,
    wordBonus,
    bluffBonus: null,
    totalAwarded,
    breakdown: `Word Pot (${wordPot}) + Word Bonus (${wordBonus}) = ${totalAwarded}`,
  };
}

/**
 * Calculate scoring when challenger catches a bluff
 * Challenger gets: Bluff Bonus = max(2, floor(wordPot * 0.3))
 */
export function calculateChallengerWinScore(
  wordFragment: string,
  challengerId: string,
  challengerName: string
): ScoringResult {
  const wordPot = calculateWordPot(wordFragment);
  const bluffBonus = Math.max(2, Math.floor(wordPot * 0.3));

  return {
    winnerId: challengerId,
    winnerName: challengerName,
    wordPot,
    wordBonus: null,
    bluffBonus,
    totalAwarded: bluffBonus,
    breakdown: `Bluff Bonus = max(2, floor(${wordPot} × 0.3)) = ${bluffBonus}`,
  };
}

/**
 * Check if any player has reached the target score
 */
export function checkForWinner(
  players: Record<string, { score: number; displayName: string }>,
  targetScore: number
): { hasWinner: boolean; winnerId: string | null; winnerName: string | null } {
  for (const [playerId, player] of Object.entries(players)) {
    if (player.score >= targetScore) {
      return {
        hasWinner: true,
        winnerId: playerId,
        winnerName: player.displayName,
      };
    }
  }

  return { hasWinner: false, winnerId: null, winnerName: null };
}
