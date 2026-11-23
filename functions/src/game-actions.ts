import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import {
  Game,
  SubmitMoveRequest,
  InitiateChallengeRequest,
  RespondToChallengeRequest,
  CallWordRequest,
  RespondToWordCallRequest,
  VoteOnChallengeRequest,
  LastAction,
  PendingChallenge,
  PendingWordCall,
  ScoringDetails,
  ChallengeHistoryEntry,
  WordCallHistoryEntry,
  WordCallPlayerResult,
  ChallengePlayerResult,
} from "./types";
import {
  getLetterPoints,
  calculateWordPot,
  calculateDefenderWinScore,
  calculateChallengerWinScore,
  checkForWinner,
  validateClaimedWord,
  getNextPlayerIndex,
  getPreviousPlayerIndex,
  calculateTurnDeadline,
  calculateChallengeDeadline,
} from "./utils";

const db = getFirestore();

// ═══════════════════════════════════════════════════════════════
// SUBMIT MOVE (Add Letter)
// ═══════════════════════════════════════════════════════════════

export const submitMove = onCall<SubmitMoveRequest>(async (request) => {
  // Validate auth
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const playerId = request.auth.uid;
  const { gameId, letter } = request.data;

  // Input validation
  if (!gameId || typeof gameId !== "string") {
    throw new HttpsError("invalid-argument", "Missing gameId");
  }
  if (!letter || typeof letter !== "string") {
    throw new HttpsError("invalid-argument", "Missing letter");
  }

  const upperLetter = letter.toUpperCase();

  // Transaction
  const result = await db.runTransaction(async (transaction) => {
    const gameRef = db.collection("games").doc(gameId);
    const gameDoc = await transaction.get(gameRef);

    if (!gameDoc.exists) {
      throw new HttpsError("not-found", "Game not found");
    }

    const game = gameDoc.data() as Game;

    // Validate letter is valid for the game's dictionary
    const dictionary = game.settings.dictionary || "english";
    const isValidLetter = dictionary === "greek"
      ? /^[ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ]$/.test(upperLetter)
      : /^[A-Z]$/.test(upperLetter);
    if (!isValidLetter) {
      throw new HttpsError(
        "invalid-argument",
        dictionary === "greek"
          ? "Letter must be a single Greek character"
          : "Letter must be a single A-Z character"
      );
    }

    // Validate game state
    if (game.status !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not active");
    }

    if (!game.playerIds.includes(playerId)) {
      throw new HttpsError("permission-denied", "You are not in this game");
    }

    // Validate turn
    const currentPlayerId = game.playerIds[game.currentPlayerIndex];
    if (currentPlayerId !== playerId) {
      throw new HttpsError("failed-precondition", "Not your turn");
    }

    if (game.players[playerId].isEliminated) {
      throw new HttpsError("failed-precondition", "You are eliminated");
    }

    // Calculate new word and pot
    const previousWord = game.currentWord;
    const newWord = previousWord + upperLetter;
    const letterPoints = getLetterPoints(upperLetter, dictionary);
    const newWordPot = game.wordPot + letterPoints;

    // Get next player
    const nextPlayerIndex = getNextPlayerIndex(
      game.playerIds,
      game.players,
      game.currentPlayerIndex
    );

    // Build last action
    const lastAction: LastAction = {
      playerId,
      playerName: game.players[playerId].displayName,
      type: "add_letter",
      letter: upperLetter,
      letterPoints,
      previousWord,
      resultingWord: newWord,
      wordPotBefore: game.wordPot,
      wordPotAfter: newWordPot,
      scoringDetails: null,
      timestamp: Timestamp.now(),
    };

    // Write turn history
    const turnRef = gameRef
      .collection("turns")
      .doc(String(game.turnNumber + 1));
    transaction.set(turnRef, {
      turnNumber: game.turnNumber + 1,
      playerId,
      playerDisplayName: game.players[playerId].displayName,
      actionType: "add_letter",
      letter: upperLetter,
      letterPoints,
      wordBefore: previousWord,
      wordAfter: newWord,
      wordPotAfter: newWordPot,
      timestamp: FieldValue.serverTimestamp(),
    });

    // Update game
    transaction.update(gameRef, {
      currentWord: newWord,
      wordPot: newWordPot,
      currentPlayerIndex: nextPlayerIndex,
      turnNumber: game.turnNumber + 1,
      wordTurnNumber: game.wordTurnNumber + 1,
      turnDeadline: calculateTurnDeadline(game.settings),
      lastAction,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      newWord,
      letterPoints,
      wordPot: newWordPot,
      nextPlayerId: game.playerIds[nextPlayerIndex],
    };
  });

  return result;
});

// ═══════════════════════════════════════════════════════════════
// INITIATE CHALLENGE
// ═══════════════════════════════════════════════════════════════

export const initiateChallenge = onCall<InitiateChallengeRequest>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const challengerId = request.auth.uid;
    const { gameId } = request.data;

    if (!gameId) {
      throw new HttpsError("invalid-argument", "Missing gameId");
    }

    const result = await db.runTransaction(async (transaction) => {
      const gameRef = db.collection("games").doc(gameId);
      const gameDoc = await transaction.get(gameRef);

      if (!gameDoc.exists) {
        throw new HttpsError("not-found", "Game not found");
      }

      const game = gameDoc.data() as Game;

      // Validate game state
      if (game.status !== "in_progress") {
        throw new HttpsError("failed-precondition", "Game is not active");
      }

      // Validate turn
      const currentPlayerId = game.playerIds[game.currentPlayerIndex];
      if (currentPlayerId !== challengerId) {
        throw new HttpsError("failed-precondition", "Not your turn");
      }

      // Validate minimum letters for challenge
      if (game.currentWord.length < game.settings.minFragmentToChallenge) {
        throw new HttpsError(
          "failed-precondition",
          `Cannot challenge until at least ${game.settings.minFragmentToChallenge} letters`
        );
      }

      // Cannot challenge on first turn
      if (game.turnNumber < 1) {
        throw new HttpsError(
          "failed-precondition",
          "Cannot challenge on first turn"
        );
      }

      // Get challenged player (previous player who added last letter)
      const previousPlayerIndex = getPreviousPlayerIndex(
        game.playerIds,
        game.players,
        game.currentPlayerIndex
      );
      const challengedPlayerId = game.playerIds[previousPlayerIndex];

      // Can't challenge yourself
      if (challengedPlayerId === challengerId) {
        throw new HttpsError("failed-precondition", "Cannot challenge yourself");
      }

      // Identify other players (not challenger, not challenged) for voting
      const otherPlayerIds = game.playerIds.filter(
        (id) => id !== challengerId && id !== challengedPlayerId && !game.players[id].isEliminated
      );

      // Create pending challenge
      const pendingChallenge: PendingChallenge = {
        challengerId,
        challengerName: game.players[challengerId].displayName,
        challengedPlayerId,
        challengedPlayerName: game.players[challengedPlayerId].displayName,
        wordFragment: game.currentWord,
        responseDeadline: calculateChallengeDeadline(game.settings),
        createdAt: Timestamp.now(),
        otherPlayerIds,
        otherPlayerVotes: {},
      };

      // Write turn history
      const turnRef = gameRef
        .collection("turns")
        .doc(String(game.turnNumber + 1));
      transaction.set(turnRef, {
        turnNumber: game.turnNumber + 1,
        playerId: challengerId,
        playerDisplayName: game.players[challengerId].displayName,
        actionType: "challenge_initiated",
        wordFragment: game.currentWord,
        challengedPlayerId,
        timestamp: FieldValue.serverTimestamp(),
      });

      // Update game to challenge_pending
      transaction.update(gameRef, {
        status: "challenge_pending",
        pendingChallenge,
        turnNumber: game.turnNumber + 1,
        wordTurnNumber: game.wordTurnNumber + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        pendingChallenge: {
          ...pendingChallenge,
          responseDeadline: pendingChallenge.responseDeadline
            .toDate()
            .toISOString(),
        },
      };
    });

    return result;
  }
);

// ═══════════════════════════════════════════════════════════════
// RESPOND TO CHALLENGE
// ═══════════════════════════════════════════════════════════════

export const respondToChallenge = onCall<RespondToChallengeRequest>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const responderId = request.auth.uid;
    const { gameId, claimedWord } = request.data;

    if (!gameId) {
      throw new HttpsError("invalid-argument", "Missing gameId");
    }
    if (!claimedWord || typeof claimedWord !== "string") {
      throw new HttpsError("invalid-argument", "Must provide a word");
    }

    const normalizedWord = claimedWord.trim().toUpperCase();

    if (!/^[A-Za-zΑ-Ωα-ω]+$/.test(normalizedWord)) {
      throw new HttpsError(
        "invalid-argument",
        "Word must contain only letters"
      );
    }

    const result = await db.runTransaction(async (transaction) => {
      const gameRef = db.collection("games").doc(gameId);
      const gameDoc = await transaction.get(gameRef);

      if (!gameDoc.exists) {
        throw new HttpsError("not-found", "Game not found");
      }

      const game = gameDoc.data() as Game;

      // Validate state
      if (game.status !== "challenge_pending") {
        throw new HttpsError("failed-precondition", "No pending challenge");
      }

      const challenge = game.pendingChallenge!;

      if (challenge.challengedPlayerId !== responderId) {
        throw new HttpsError(
          "permission-denied",
          "You are not the challenged player"
        );
      }

      // Check deadline
      if (challenge.responseDeadline.toDate() < new Date()) {
        throw new HttpsError("deadline-exceeded", "Response time has expired");
      }

      // Validate the claimed word
      const validationResult = validateClaimedWord(
        normalizedWord,
        challenge.wordFragment,
        game.settings.minWordLength,
        game.settings.dictionary
      );

      // Debug logging
      console.log("=== CHALLENGE RESPONSE DEBUG ===");
      console.log("Claimed word:", normalizedWord);
      console.log("Word fragment:", challenge.wordFragment);
      console.log("Min word length:", game.settings.minWordLength);
      console.log("Validation result:", JSON.stringify(validationResult));
      console.log("Challenger:", challenge.challengerId, challenge.challengerName);
      console.log("Defender:", challenge.challengedPlayerId, challenge.challengedPlayerName);

      // Calculate scoring
      let scoringResult;
      if (validationResult.isValid) {
        // Defender wins
        console.log("DEFENDER WINS - awarding points to:", challenge.challengedPlayerName);
        scoringResult = calculateDefenderWinScore(
          challenge.wordFragment,
          normalizedWord,
          challenge.challengedPlayerId,
          challenge.challengedPlayerName,
          game.settings.dictionary
        );
      } else {
        // Challenger wins
        console.log("CHALLENGER WINS - awarding points to:", challenge.challengerName);
        scoringResult = calculateChallengerWinScore(
          challenge.wordFragment,
          challenge.challengerId,
          challenge.challengerName,
          game.settings.dictionary
        );
      }
      console.log("Scoring result:", JSON.stringify(scoringResult));
      console.log("=== END DEBUG ===");

      // Update winner's score
      const updatedPlayers = { ...game.players };
      const previousScore = updatedPlayers[scoringResult.winnerId].score;
      const newScore = previousScore + scoringResult.totalAwarded;
      updatedPlayers[scoringResult.winnerId] = {
        ...updatedPlayers[scoringResult.winnerId],
        score: newScore,
      };

      // Multi-player: distribute points to other players who joined the challenge
      const playerResults: Record<string, ChallengePlayerResult> = {};
      const otherVotes = challenge.otherPlayerVotes || {};

      // The original challenger always counts as "joined"
      playerResults[challenge.challengerId] = {
        joined: true,
        pointsAwarded: validationResult.isValid ? 0 : scoringResult.totalAwarded,
      };

      // Defender result
      playerResults[challenge.challengedPlayerId] = {
        joined: false, // defender doesn't "join" — they respond
        pointsAwarded: validationResult.isValid ? scoringResult.totalAwarded : 0,
      };

      for (const [voterId, voteData] of Object.entries(otherVotes)) {
        const joined = voteData.type === "join";
        let voterPoints = 0;

        if (joined && !validationResult.isValid) {
          // Word was invalid — joiners also get bluff bonus
          const joinerScore = calculateChallengerWinScore(
            challenge.wordFragment,
            voterId,
            game.players[voterId].displayName,
            game.settings.dictionary
          );
          voterPoints = joinerScore.totalAwarded;
          updatedPlayers[voterId] = {
            ...updatedPlayers[voterId],
            score: updatedPlayers[voterId].score + voterPoints,
          };
        }

        playerResults[voterId] = {
          joined,
          pointsAwarded: voterPoints,
        };
      }

      // Check for game winner
      const winCheck = checkForWinner(
        updatedPlayers,
        game.settings.targetScore
      );

      // Loser starts next round
      const loserId = validationResult.isValid
        ? challenge.challengerId
        : challenge.challengedPlayerId;
      const nextPlayerIndex = game.playerIds.indexOf(loserId);

      // Build scoring details
      const scoringDetails: ScoringDetails = {
        wordPot: scoringResult.wordPot,
        wordBonus: scoringResult.wordBonus,
        bluffBonus: scoringResult.bluffBonus,
        totalAwarded: scoringResult.totalAwarded,
        awardedTo: scoringResult.winnerId,
        awardedToName: scoringResult.winnerName,
        breakdown: scoringResult.breakdown,
      };

      // Build last action
      const lastAction: LastAction = {
        playerId: challenge.challengedPlayerId,
        playerName: challenge.challengedPlayerName,
        type: "challenge_resolved",
        letter: null,
        previousWord: challenge.wordFragment,
        resultingWord: "",
        challengeResult: {
          challengerId: challenge.challengerId,
          challengerName: challenge.challengerName,
          challengedPlayerId: challenge.challengedPlayerId,
          challengedPlayerName: challenge.challengedPlayerName,
          wordFragment: challenge.wordFragment,
          claimedWord: normalizedWord,
          wasWordValid: validationResult.isValid,
          failureReason: validationResult.failureReason,
          loserId,
          loserName: game.players[loserId].displayName,
          livesLost: 0,
          wasEliminated: false,
        },
        scoringDetails,
        timestamp: Timestamp.now(),
      };

      // Write turn history
      const turnRef = gameRef
        .collection("turns")
        .doc(String(game.turnNumber + 1));
      transaction.set(turnRef, {
        turnNumber: game.turnNumber + 1,
        playerId: challenge.challengedPlayerId,
        playerDisplayName: challenge.challengedPlayerName,
        actionType: "challenge_response",
        claimedWord: normalizedWord,
        validationResult,
        scoringResult,
        playerResults,
        timestamp: FieldValue.serverTimestamp(),
      });

      // Build challenge history entry
      const historyEntry: ChallengeHistoryEntry = {
        wordFragment: challenge.wordFragment,
        claimedWord: normalizedWord,
        wasWordValid: validationResult.isValid,
        winnerId: scoringResult.winnerId,
        winnerName: scoringResult.winnerName,
        pointsAwarded: scoringResult.totalAwarded,
        timestamp: Timestamp.now(),
        challengerName: challenge.challengerName,
        challengedPlayerName: challenge.challengedPlayerName,
        playerResults,
      };

      // Build game update
      const gameUpdate: Record<string, unknown> = {
        currentWord: "", // Reset word
        wordPot: 0, // Reset pot
        pendingChallenge: null,
        currentPlayerIndex: nextPlayerIndex,
        turnNumber: game.turnNumber + 1,
        wordTurnNumber: 1,
        players: updatedPlayers,
        lastAction,
        challengeHistory: FieldValue.arrayUnion(historyEntry),
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (winCheck.hasWinner) {
        gameUpdate.status = "completed";
        gameUpdate.winnerId = winCheck.winnerId;
        gameUpdate.winnerName = winCheck.winnerName;
        gameUpdate.endReason = "target_score_reached";
        gameUpdate.turnDeadline = null;
      } else {
        gameUpdate.status = "in_progress";
        gameUpdate.turnDeadline = calculateTurnDeadline(game.settings);
      }

      transaction.update(gameRef, gameUpdate);

      return {
        success: true,
        validationResult,
        scoringResult,
        isGameOver: winCheck.hasWinner,
        winnerId: winCheck.winnerId,
      };
    });

    return result;
  }
);

// ═══════════════════════════════════════════════════════════════
// VOTE ON CHALLENGE (Multi-player: other players join or pass)
// ═══════════════════════════════════════════════════════════════

export const voteOnChallenge = onCall<VoteOnChallengeRequest>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const voterId = request.auth.uid;
    const { gameId, vote } = request.data;

    if (!gameId) {
      throw new HttpsError("invalid-argument", "Missing gameId");
    }
    if (!["join", "pass"].includes(vote)) {
      throw new HttpsError("invalid-argument", "Vote must be 'join' or 'pass'");
    }

    const result = await db.runTransaction(async (transaction) => {
      const gameRef = db.collection("games").doc(gameId);
      const gameDoc = await transaction.get(gameRef);

      if (!gameDoc.exists) {
        throw new HttpsError("not-found", "Game not found");
      }

      const game = gameDoc.data() as Game;

      if (game.status !== "challenge_pending") {
        throw new HttpsError("failed-precondition", "No pending challenge");
      }

      const challenge = game.pendingChallenge!;

      // Verify this player is an eligible voter
      if (!challenge.otherPlayerIds?.includes(voterId)) {
        throw new HttpsError(
          "permission-denied",
          "You are not eligible to vote on this challenge"
        );
      }

      // Check if already voted
      if (challenge.otherPlayerVotes?.[voterId]) {
        throw new HttpsError("already-exists", "You already voted");
      }

      // Check deadline
      if (challenge.responseDeadline.toDate() < new Date()) {
        throw new HttpsError("deadline-exceeded", "Response time has expired");
      }

      // Record the vote
      const updatedVotes = { ...(challenge.otherPlayerVotes || {}) };
      updatedVotes[voterId] = {
        type: vote,
        playerName: game.players[voterId].displayName,
        votedAt: Timestamp.now(),
      };

      transaction.update(gameRef, {
        "pendingChallenge.otherPlayerVotes": updatedVotes,
        updatedAt: FieldValue.serverTimestamp(),
      });

      return { success: true, vote };
    });

    return result;
  }
);

// ═══════════════════════════════════════════════════════════════
// CHALLENGE TIMEOUT HANDLER (Scheduled)
// ═══════════════════════════════════════════════════════════════

export const checkChallengeTimeouts = onSchedule(
  "every 1 minutes",
  async () => {
    const now = Timestamp.now();

    // Find games with expired challenges
    const expiredChallenges = await db
      .collection("games")
      .where("status", "==", "challenge_pending")
      .get();

    let challengesProcessed = 0;
    for (const gameDoc of expiredChallenges.docs) {
      const game = gameDoc.data() as Game;
      const challenge = game.pendingChallenge;

      if (!challenge) continue;
      if (challenge.responseDeadline.toDate() > now.toDate()) continue;

      await handleChallengeTimeout(gameDoc.id);
      challengesProcessed++;
    }

    if (challengesProcessed > 0) {
      console.log(`Processed ${challengesProcessed} challenge timeouts`);
    }

    // Find games with expired word calls
    const expiredWordCalls = await db
      .collection("games")
      .where("status", "==", "word_call_pending")
      .get();

    let wordCallsProcessed = 0;
    for (const gameDoc of expiredWordCalls.docs) {
      const game = gameDoc.data() as Game;
      const wordCall = game.pendingWordCall;

      if (!wordCall) continue;
      if (wordCall.responseDeadline.toDate() > now.toDate()) continue;

      await handleWordCallTimeout(gameDoc.id);
      wordCallsProcessed++;
    }

    if (wordCallsProcessed > 0) {
      console.log(`Processed ${wordCallsProcessed} word call timeouts`);
    }
  }
);

/**
 * Handle a challenge timeout - challenger wins by default
 */
async function handleChallengeTimeout(gameId: string): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const gameRef = db.collection("games").doc(gameId);
    const freshDoc = await transaction.get(gameRef);

    if (!freshDoc.exists) return;

    const freshGame = freshDoc.data() as Game;

    // Verify still in challenge_pending
    if (freshGame.status !== "challenge_pending") return;
    if (!freshGame.pendingChallenge) return;

    const challenge = freshGame.pendingChallenge;

    // Verify deadline passed
    if (challenge.responseDeadline.toDate() > new Date()) return;

    // Challenger wins (defender couldn't respond)
    const scoringResult = calculateChallengerWinScore(
      challenge.wordFragment,
      challenge.challengerId,
      challenge.challengerName,
      freshGame.settings.dictionary
    );

    // Update scores
    const updatedPlayers = { ...freshGame.players };
    const previousScore = updatedPlayers[scoringResult.winnerId].score;
    const newScore = previousScore + scoringResult.totalAwarded;
    updatedPlayers[scoringResult.winnerId] = {
      ...updatedPlayers[scoringResult.winnerId],
      score: newScore,
    };

    // Multi-player: joiners also get bluff bonus on timeout (defender failed)
    const otherVotes = challenge.otherPlayerVotes || {};
    for (const [voterId, voteData] of Object.entries(otherVotes)) {
      if (voteData.type === "join") {
        const joinerScore = calculateChallengerWinScore(
          challenge.wordFragment,
          voterId,
          freshGame.players[voterId].displayName,
          freshGame.settings.dictionary
        );
        updatedPlayers[voterId] = {
          ...updatedPlayers[voterId],
          score: updatedPlayers[voterId].score + joinerScore.totalAwarded,
        };
      }
    }

    // Check for winner
    const winCheck = checkForWinner(
      updatedPlayers,
      freshGame.settings.targetScore
    );

    // Loser (defender) starts next round
    const nextPlayerIndex = freshGame.playerIds.indexOf(
      challenge.challengedPlayerId
    );

    // Build scoring details
    const scoringDetails: ScoringDetails = {
      wordPot: scoringResult.wordPot,
      wordBonus: null,
      bluffBonus: scoringResult.bluffBonus,
      totalAwarded: scoringResult.totalAwarded,
      awardedTo: scoringResult.winnerId,
      awardedToName: scoringResult.winnerName,
      breakdown: `Timeout: ${scoringResult.breakdown}`,
    };

    const lastAction: LastAction = {
      playerId: challenge.challengedPlayerId,
      playerName: challenge.challengedPlayerName,
      type: "challenge_timeout",
      letter: null,
      previousWord: challenge.wordFragment,
      resultingWord: "",
      challengeResult: {
        challengerId: challenge.challengerId,
        challengerName: challenge.challengerName,
        challengedPlayerId: challenge.challengedPlayerId,
        challengedPlayerName: challenge.challengedPlayerName,
        wordFragment: challenge.wordFragment,
        claimedWord: null,
        wasWordValid: false,
        failureReason: "Response timeout",
        loserId: challenge.challengedPlayerId,
        loserName: challenge.challengedPlayerName,
        livesLost: 0,
        wasEliminated: false,
      },
      scoringDetails,
      timestamp: Timestamp.now(),
    };

    // Write turn history
    const turnRef = gameRef
      .collection("turns")
      .doc(String(freshGame.turnNumber + 1));
    transaction.set(turnRef, {
      turnNumber: freshGame.turnNumber + 1,
      playerId: challenge.challengedPlayerId,
      playerDisplayName: challenge.challengedPlayerName,
      actionType: "challenge_timeout",
      timestamp: FieldValue.serverTimestamp(),
    });

    // Build challenge history entry for timeout
    const historyEntry: ChallengeHistoryEntry = {
      wordFragment: challenge.wordFragment,
      claimedWord: null,
      wasWordValid: false,
      winnerId: scoringResult.winnerId,
      winnerName: scoringResult.winnerName,
      pointsAwarded: scoringResult.totalAwarded,
      timestamp: Timestamp.now(),
      challengerName: challenge.challengerName,
      challengedPlayerName: challenge.challengedPlayerName,
    };

    const gameUpdate: Record<string, unknown> = {
      currentWord: "",
      wordPot: 0,
      pendingChallenge: null,
      currentPlayerIndex: nextPlayerIndex,
      turnNumber: freshGame.turnNumber + 1,
      wordTurnNumber: 1,
      players: updatedPlayers,
      lastAction,
      challengeHistory: FieldValue.arrayUnion(historyEntry),
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (winCheck.hasWinner) {
      gameUpdate.status = "completed";
      gameUpdate.winnerId = winCheck.winnerId;
      gameUpdate.winnerName = winCheck.winnerName;
      gameUpdate.endReason = "challenge_timeout";
      gameUpdate.turnDeadline = null;
    } else {
      gameUpdate.status = "in_progress";
      gameUpdate.turnDeadline = calculateTurnDeadline(freshGame.settings);
    }

    transaction.update(gameRef, gameUpdate);
  });
}

/**
 * Handle a word call timeout - caller wins if their word is valid
 */
async function handleWordCallTimeout(gameId: string): Promise<void> {
  await db.runTransaction(async (transaction) => {
    const gameRef = db.collection("games").doc(gameId);
    const freshDoc = await transaction.get(gameRef);

    if (!freshDoc.exists) return;

    const freshGame = freshDoc.data() as Game;

    // Verify still in word_call_pending
    if (freshGame.status !== "word_call_pending") return;
    if (!freshGame.pendingWordCall) return;

    const wordCall = freshGame.pendingWordCall;

    // Verify deadline passed
    if (wordCall.responseDeadline.toDate() > new Date()) return;

    // Multi-player: fill in missing votes as "accept" (timeout default)
    const isMultiPlayer = wordCall.allResponderIds && wordCall.allResponderIds.length > 1;
    if (isMultiPlayer) {
      const filledVotes = { ...(wordCall.responderVotes || {}) };
      for (const id of wordCall.allResponderIds!) {
        if (!(id in filledVotes)) {
          filledVotes[id] = {
            type: "accept" as const,
            playerName: freshGame.players[id].displayName,
            votedAt: Timestamp.now(),
          };
        }
      }
      // Resolve using multi-player logic
      resolveMultiPlayerWordCall(
        transaction,
        gameRef,
        freshGame,
        wordCall,
        filledVotes
      );
      return;
    }

    // Legacy 2-player timeout path
    // Validate the called word
    const calledWordValid = validateClaimedWord(
      wordCall.calledWord,
      wordCall.wordFragment,
      freshGame.settings.minWordLength,
      freshGame.settings.dictionary
    );

    let winnerId: string | null = null;
    let winnerName: string | null = null;
    let pointsAwarded = 0;
    let loserId: string;

    if (calledWordValid.isValid) {
      // Caller wins with their word (timeout = implicit accept)
      winnerId = wordCall.callerId;
      winnerName = wordCall.callerName;
      const wordPot = calculateWordPot(wordCall.wordFragment, freshGame.settings.dictionary);
      const wordBonus = calculateWordPot(wordCall.calledWord, freshGame.settings.dictionary) - wordPot;
      pointsAwarded = wordPot + wordBonus;
      loserId = wordCall.responderId;
    } else {
      // Caller's word was invalid - no points, caller starts next
      loserId = wordCall.callerId;
    }

    // Update winner's score if there is one
    const updatedPlayers = { ...freshGame.players };
    if (winnerId && pointsAwarded > 0) {
      const previousScore = updatedPlayers[winnerId].score;
      updatedPlayers[winnerId] = {
        ...updatedPlayers[winnerId],
        score: previousScore + pointsAwarded,
      };
    }

    // Check for winner
    const winCheck = checkForWinner(
      updatedPlayers,
      freshGame.settings.targetScore
    );

    // Loser starts next round
    const nextPlayerIndex = freshGame.playerIds.indexOf(loserId);

    // Build scoring details
    const scoringDetails: ScoringDetails | null =
      winnerId && pointsAwarded > 0
        ? {
            wordPot: calculateWordPot(wordCall.wordFragment, freshGame.settings.dictionary),
            wordBonus: calculateWordPot(wordCall.calledWord, freshGame.settings.dictionary) - calculateWordPot(wordCall.wordFragment, freshGame.settings.dictionary),
            bluffBonus: null,
            totalAwarded: pointsAwarded,
            awardedTo: winnerId,
            awardedToName: winnerName!,
            breakdown: `Word Call timeout: ${pointsAwarded} points`,
          }
        : null;

    const lastAction: LastAction = {
      playerId: wordCall.responderId,
      playerName: wordCall.responderName,
      type: "word_call_timeout",
      letter: null,
      previousWord: wordCall.wordFragment,
      resultingWord: "",
      scoringDetails,
      timestamp: Timestamp.now(),
    };

    // Write turn history
    const turnRef = gameRef
      .collection("turns")
      .doc(String(freshGame.turnNumber + 1));
    transaction.set(turnRef, {
      turnNumber: freshGame.turnNumber + 1,
      playerId: wordCall.responderId,
      playerDisplayName: wordCall.responderName,
      actionType: "word_call_timeout",
      calledWord: wordCall.calledWord,
      wasCalledWordValid: calledWordValid.isValid,
      winnerId,
      pointsAwarded,
      timestamp: FieldValue.serverTimestamp(),
    });

    // Build word call history entry
    const historyEntry: WordCallHistoryEntry = {
      wordFragment: wordCall.wordFragment,
      calledWord: wordCall.calledWord,
      responseType: "timeout",
      continuationWord: null,
      wasCalledWordValid: calledWordValid.isValid,
      wasContinuationValid: null,
      winnerId,
      winnerName,
      pointsAwarded,
      timestamp: Timestamp.now(),
      callerName: wordCall.callerName,
      responderName: wordCall.responderName,
    };

    const gameUpdate: Record<string, unknown> = {
      currentWord: "",
      wordPot: 0,
      pendingWordCall: null,
      currentPlayerIndex: nextPlayerIndex,
      turnNumber: freshGame.turnNumber + 1,
      wordTurnNumber: 1,
      players: updatedPlayers,
      lastAction,
      wordCallHistory: FieldValue.arrayUnion(historyEntry),
      updatedAt: FieldValue.serverTimestamp(),
    };

    if (winCheck.hasWinner) {
      gameUpdate.status = "completed";
      gameUpdate.winnerId = winCheck.winnerId;
      gameUpdate.winnerName = winCheck.winnerName;
      gameUpdate.endReason = "word_call_timeout";
      gameUpdate.turnDeadline = null;
    } else {
      gameUpdate.status = "in_progress";
      gameUpdate.turnDeadline = calculateTurnDeadline(freshGame.settings);
    }

    transaction.update(gameRef, gameUpdate);
  });
}

// ═══════════════════════════════════════════════════════════════
// CALL WORD (Declare complete word)
// ═══════════════════════════════════════════════════════════════

export const callWord = onCall<CallWordRequest>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const callerId = request.auth.uid;
  const { gameId, calledWord } = request.data;

  if (!gameId) {
    throw new HttpsError("invalid-argument", "Missing gameId");
  }
  if (!calledWord || typeof calledWord !== "string") {
    throw new HttpsError("invalid-argument", "Must provide a word");
  }

  const normalizedWord = calledWord.trim().toUpperCase();

  if (!/^[A-Za-zΑ-Ωα-ω]+$/.test(normalizedWord)) {
    throw new HttpsError("invalid-argument", "Word must contain only letters");
  }

  const result = await db.runTransaction(async (transaction) => {
    const gameRef = db.collection("games").doc(gameId);
    const gameDoc = await transaction.get(gameRef);

    if (!gameDoc.exists) {
      throw new HttpsError("not-found", "Game not found");
    }

    const game = gameDoc.data() as Game;

    // Validate game state
    if (game.status !== "in_progress") {
      throw new HttpsError("failed-precondition", "Game is not active");
    }

    // Validate it's caller's turn
    const currentPlayerId = game.playerIds[game.currentPlayerIndex];
    if (currentPlayerId !== callerId) {
      throw new HttpsError("failed-precondition", "Not your turn");
    }

    // Validate word starts with current fragment
    if (!normalizedWord.startsWith(game.currentWord.toUpperCase())) {
      throw new HttpsError(
        "invalid-argument",
        `Word must start with "${game.currentWord}"`
      );
    }

    // Validate minimum word length
    if (normalizedWord.length < game.settings.minWordLength) {
      throw new HttpsError(
        "invalid-argument",
        `Word must be at least ${game.settings.minWordLength} letters`
      );
    }

    // Get all non-caller players who can respond
    const allResponderIds = game.playerIds.filter(
      (id) => id !== callerId && !game.players[id].isEliminated
    );

    // Legacy: first responder for 2-player compat
    const responderIndex = getNextPlayerIndex(
      game.playerIds,
      game.players,
      game.currentPlayerIndex
    );
    const responderId = game.playerIds[responderIndex];

    // Create pending word call
    const pendingWordCall: PendingWordCall = {
      callerId,
      callerName: game.players[callerId].displayName,
      responderId,
      responderName: game.players[responderId].displayName,
      wordFragment: game.currentWord,
      calledWord: normalizedWord,
      responseDeadline: calculateChallengeDeadline(game.settings),
      createdAt: Timestamp.now(),
      allResponderIds,
      responderVotes: {},
    };

    // Write turn history
    const turnRef = gameRef
      .collection("turns")
      .doc(String(game.turnNumber + 1));
    transaction.set(turnRef, {
      turnNumber: game.turnNumber + 1,
      playerId: callerId,
      playerDisplayName: game.players[callerId].displayName,
      actionType: "word_call_initiated",
      calledWord: normalizedWord,
      wordFragment: game.currentWord,
      timestamp: FieldValue.serverTimestamp(),
    });

    // Update game to word_call_pending
    transaction.update(gameRef, {
      status: "word_call_pending",
      pendingWordCall,
      turnNumber: game.turnNumber + 1,
      wordTurnNumber: game.wordTurnNumber + 1,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return {
      success: true,
      pendingWordCall: {
        ...pendingWordCall,
        responseDeadline: pendingWordCall.responseDeadline.toDate().toISOString(),
      },
    };
  });

  return result;
});

// ═══════════════════════════════════════════════════════════════
// RESPOND TO WORD CALL
// ═══════════════════════════════════════════════════════════════

export const respondToWordCall = onCall<RespondToWordCallRequest>(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const responderId = request.auth.uid;
    const { gameId, responseType, continuationWord } = request.data;

    if (!gameId) {
      throw new HttpsError("invalid-argument", "Missing gameId");
    }
    if (!["continue", "challenge", "accept"].includes(responseType)) {
      throw new HttpsError("invalid-argument", "Invalid response type");
    }
    if (responseType === "continue" && !continuationWord) {
      throw new HttpsError(
        "invalid-argument",
        "Must provide continuation word"
      );
    }

    const result = await db.runTransaction(async (transaction) => {
      const gameRef = db.collection("games").doc(gameId);
      const gameDoc = await transaction.get(gameRef);

      if (!gameDoc.exists) {
        throw new HttpsError("not-found", "Game not found");
      }

      const game = gameDoc.data() as Game;

      // Validate state
      if (game.status !== "word_call_pending") {
        throw new HttpsError("failed-precondition", "No pending word call");
      }

      const wordCall = game.pendingWordCall!;

      // Check deadline (5s grace period for network latency)
      const deadlineMs = wordCall.responseDeadline.toDate().getTime() + 5000;
      if (deadlineMs < Date.now()) {
        throw new HttpsError("deadline-exceeded", "Response time has expired");
      }

      // Multi-player path: use allResponderIds if available
      const isMultiPlayer = wordCall.allResponderIds && wordCall.allResponderIds.length > 1;

      if (isMultiPlayer) {
        // Verify this player is an eligible responder
        if (!wordCall.allResponderIds!.includes(responderId)) {
          throw new HttpsError(
            "permission-denied",
            "You are not a responder for this word call"
          );
        }

        // Check if already voted
        if (wordCall.responderVotes?.[responderId]) {
          throw new HttpsError("already-exists", "You already responded");
        }

        // Record the vote (use null instead of undefined — Firestore rejects undefined)
        const updatedVotes = { ...(wordCall.responderVotes || {}) };
        updatedVotes[responderId] = {
          type: responseType as "continue" | "challenge" | "accept",
          continuationWord: continuationWord ? continuationWord.trim().toUpperCase() : null,
          playerName: game.players[responderId].displayName,
          votedAt: Timestamp.now(),
        };

        // Check if all responders have voted
        const allVoted = wordCall.allResponderIds!.every((id) => id in updatedVotes);

        if (allVoted) {
          // All votes are in — resolve the word call
          return resolveMultiPlayerWordCall(
            transaction,
            gameRef,
            game,
            wordCall,
            updatedVotes
          );
        } else {
          // Not all voted yet — just record the vote and wait
          transaction.update(gameRef, {
            "pendingWordCall.responderVotes": updatedVotes,
            updatedAt: FieldValue.serverTimestamp(),
          });

          return {
            success: true,
            voteRecorded: true,
            allVoted: false,
            responseType,
          };
        }
      }

      // Legacy 2-player path
      if (wordCall.responderId !== responderId) {
        throw new HttpsError(
          "permission-denied",
          "You are not the responder"
        );
      }

      // Handle response based on type
      switch (responseType) {
        case "continue":
          return handleContinueResponse(
            transaction,
            gameRef,
            game,
            wordCall,
            continuationWord!.trim().toUpperCase()
          );
        case "challenge":
          return handleWordCallChallengeResponse(
            transaction,
            gameRef,
            game,
            wordCall
          );
        case "accept":
          return handleAcceptResponse(transaction, gameRef, game, wordCall);
        default:
          throw new HttpsError("invalid-argument", "Invalid response type");
      }
    });

    return result;
  }
);

/**
 * Handle 'continue' response - responder tries to extend the word
 */
/**
 * Resolve a multi-player word call once all votes are in.
 * Each voter's bet is evaluated independently against the caller's word.
 */
function resolveMultiPlayerWordCall(
  transaction: FirebaseFirestore.Transaction,
  gameRef: FirebaseFirestore.DocumentReference,
  game: Game,
  wordCall: PendingWordCall,
  votes: Record<string, { type: "continue" | "challenge" | "accept"; continuationWord?: string | null; playerName: string; votedAt: Timestamp }>
): Record<string, unknown> {
  const fragmentUpper = wordCall.wordFragment.toUpperCase();

  // Validate the caller's word
  const calledWordValid = validateClaimedWord(
    wordCall.calledWord.toUpperCase(),
    fragmentUpper,
    game.settings.minWordLength,
    game.settings.dictionary
  );

  console.log("=== MULTI-PLAYER WORD CALL RESOLVE ===");
  console.log("Called word:", wordCall.calledWord, "valid:", calledWordValid.isValid);
  console.log("Votes:", JSON.stringify(votes));

  const updatedPlayers = { ...game.players };
  const playerResults: Record<string, WordCallPlayerResult> = {};
  const wordPot = calculateWordPot(wordCall.wordFragment, game.settings.dictionary);


  const calledWordFullPoints = calculateWordPot(wordCall.calledWord, game.settings.dictionary);

  // Track overall best continuation for display purposes
  let bestContinuationWord: string | null = null;
  let bestContinuationValid = false;

  // Overall winner tracking (for history display — the highest single earner)
  let overallWinnerId: string | null = null;
  let overallWinnerName: string | null = null;
  let overallPointsAwarded = 0;
  let callerTotalEarned = 0;

  // First pass: find the best continuation among all "continue" voters
  // Only the best continuation wins the pot — not all valid continuations
  let bestContinuationVoterId: string | null = null;
  let bestContinuationPoints = 0;

  for (const [voterId, vote] of Object.entries(votes)) {
    if (vote.type === "continue" && vote.continuationWord) {
      const contWord = vote.continuationWord.toUpperCase();
      const continuationValid = validateClaimedWord(
        contWord,
        fragmentUpper,
        game.settings.minWordLength,
        game.settings.dictionary
      );
      if (continuationValid.isValid) {
        const continuationPoints = calculateWordPot(contWord, game.settings.dictionary);
        if (continuationPoints > bestContinuationPoints) {
          bestContinuationVoterId = voterId;
          bestContinuationPoints = continuationPoints;
          bestContinuationWord = contWord;
          bestContinuationValid = true;
        }
      }
    }
  }

  // Second pass: evaluate each voter and award points
  for (const [voterId, vote] of Object.entries(votes)) {
    let voterPoints = 0;
    let voterWon = false;
    let voterContinuationValid: boolean | undefined;

    switch (vote.type) {
      case "challenge": {
        if (!calledWordValid.isValid) {
          // Successful challenge — voter wins bluff bonus
          const bluffBonus = Math.max(2, Math.floor(wordPot * 0.3));
          voterPoints = bluffBonus;
          voterWon = true;
        }
        // If word was valid, challenger gets nothing (bad bet)
        break;
      }
      case "continue": {
        if (vote.continuationWord) {
          const contWord = vote.continuationWord.toUpperCase();
          const continuationValid = validateClaimedWord(
            contWord,
            fragmentUpper,
            game.settings.minWordLength,
            game.settings.dictionary
          );
          voterContinuationValid = continuationValid.isValid;

          // Only the best continuation wins the pot
          if (voterId === bestContinuationVoterId) {
            voterPoints = wordPot + (bestContinuationPoints - wordPot);
            voterWon = true;
          }
          // All other continuations (even valid ones) get nothing
        }
        break;
      }
      case "accept": {
        // Acceptors earn nothing — passive choice
        // But caller earns their share of the pot (handled below)
        break;
      }
    }

    // Award voter points
    if (voterPoints > 0) {
      updatedPlayers[voterId] = {
        ...updatedPlayers[voterId],
        score: updatedPlayers[voterId].score + voterPoints,
      };
    }

    playerResults[voterId] = {
      responseType: vote.type,
      continuationWord: vote.continuationWord ?? undefined,
      wasContinuationValid: voterContinuationValid,
      pointsAwarded: voterPoints,
      won: voterWon,
    };

    if (voterPoints > overallPointsAwarded) {
      overallPointsAwarded = voterPoints;
      overallWinnerId = voterId;
      overallWinnerName = game.players[voterId].displayName;
    }
  }

  // Calculate caller's earnings: from each voter who accepted or failed their bet
  const numVoters = Object.keys(votes).length;
  const perVoterPotShare = numVoters > 0 ? Math.floor((wordPot + (calledWordFullPoints - wordPot)) / numVoters) : 0;

  for (const [voterId] of Object.entries(votes)) {
    const voterResult = playerResults[voterId];
    if (!voterResult.won && calledWordValid.isValid) {
      // This voter's bet failed AND caller's word is valid — caller earns their share
      callerTotalEarned += perVoterPotShare;
    }
  }

  // Award caller's earnings
  if (callerTotalEarned > 0) {
    updatedPlayers[wordCall.callerId] = {
      ...updatedPlayers[wordCall.callerId],
      score: updatedPlayers[wordCall.callerId].score + callerTotalEarned,
    };
  }

  // If caller earned the most, they are the overall winner
  if (callerTotalEarned > overallPointsAwarded) {
    overallPointsAwarded = callerTotalEarned;
    overallWinnerId = wordCall.callerId;
    overallWinnerName = wordCall.callerName;
  }

  // Check for game winner
  const winCheck = checkForWinner(updatedPlayers, game.settings.targetScore);

  // Determine who starts next round: if caller's word was valid and they earned points,
  // the lowest scorer among non-callers starts; otherwise caller starts
  let loserId: string;
  if (calledWordValid.isValid && callerTotalEarned > 0) {
    // Find the first voter who lost their bet
    const loser = Object.entries(playerResults).find(([, r]) => !r.won);
    loserId = loser ? loser[0] : wordCall.callerId;
  } else {
    loserId = wordCall.callerId;
  }
  const nextPlayerIndex = game.playerIds.indexOf(loserId);

  // Build scoring details (summary — caller perspective)
  const scoringDetails: ScoringDetails | null = overallPointsAwarded > 0
    ? {
        wordPot,
        wordBonus: calledWordFullPoints - wordPot,
        bluffBonus: null,
        totalAwarded: overallPointsAwarded,
        awardedTo: overallWinnerId!,
        awardedToName: overallWinnerName!,
        breakdown: `Multi-player word call: ${overallPointsAwarded} points`,
      }
    : null;

  // Determine dominant response type for history
  const responseTypes = Object.values(votes).map((v) => v.type);
  const dominantResponseType = responseTypes.includes("continue")
    ? "continue"
    : responseTypes.includes("challenge")
      ? "challenge"
      : "accept";

  // Build last action
  const lastAction: LastAction = {
    playerId: wordCall.callerId,
    playerName: wordCall.callerName,
    type: `word_call_${dominantResponseType}`,
    letter: null,
    previousWord: wordCall.wordFragment,
    resultingWord: "",
    scoringDetails,
    timestamp: Timestamp.now(),
  };

  // Write turn history
  const turnRef = gameRef.collection("turns").doc(String(game.turnNumber + 1));
  transaction.set(turnRef, {
    turnNumber: game.turnNumber + 1,
    playerId: wordCall.callerId,
    playerDisplayName: wordCall.callerName,
    actionType: "word_call_multi_resolved",
    calledWord: wordCall.calledWord,
    wasCalledWordValid: calledWordValid.isValid,
    playerResults,
    overallWinnerId,
    overallPointsAwarded,
    timestamp: FieldValue.serverTimestamp(),
  });

  // Build word call history entry
  const historyEntry: WordCallHistoryEntry = {
    wordFragment: wordCall.wordFragment,
    calledWord: wordCall.calledWord,
    responseType: dominantResponseType,
    continuationWord: bestContinuationWord,
    wasCalledWordValid: calledWordValid.isValid,
    wasContinuationValid: bestContinuationValid || null,
    winnerId: overallWinnerId,
    winnerName: overallWinnerName,
    pointsAwarded: overallPointsAwarded,
    timestamp: Timestamp.now(),
    callerName: wordCall.callerName,
    responderName: wordCall.responderName,
    playerResults,
  };

  // Build game update
  const gameUpdate: Record<string, unknown> = {
    currentWord: "",
    wordPot: 0,
    pendingWordCall: null,
    currentPlayerIndex: nextPlayerIndex,
    turnNumber: game.turnNumber + 1,
    wordTurnNumber: 1,
    players: updatedPlayers,
    lastAction,
    wordCallHistory: FieldValue.arrayUnion(historyEntry),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (winCheck.hasWinner) {
    gameUpdate.status = "completed";
    gameUpdate.winnerId = winCheck.winnerId;
    gameUpdate.winnerName = winCheck.winnerName;
    gameUpdate.endReason = "target_score_reached";
    gameUpdate.turnDeadline = null;
  } else {
    gameUpdate.status = "in_progress";
    gameUpdate.turnDeadline = calculateTurnDeadline(game.settings);
  }

  transaction.update(gameRef, gameUpdate);

  return {
    success: true,
    allVoted: true,
    wasCalledWordValid: calledWordValid.isValid,
    playerResults,
    overallWinnerId,
    overallWinnerName,
    overallPointsAwarded,
    isGameOver: winCheck.hasWinner,
  };
}

/**
 * Handle 'continue' response - responder tries to extend the word
 */
async function handleContinueResponse(
  transaction: FirebaseFirestore.Transaction,
  gameRef: FirebaseFirestore.DocumentReference,
  game: Game,
  wordCall: PendingWordCall,
  continuationWord: string
): Promise<Record<string, unknown>> {
  // Validate continuation word starts with the original fragment (case-insensitive)
  const fragmentUpper = wordCall.wordFragment.toUpperCase();
  if (!continuationWord.startsWith(fragmentUpper)) {
    throw new HttpsError(
      "invalid-argument",
      `Word must start with "${wordCall.wordFragment}"`
    );
  }

  // Validate both words (ensure uppercase for dictionary lookup)
  const calledWordValid = validateClaimedWord(
    wordCall.calledWord.toUpperCase(),
    fragmentUpper,
    game.settings.minWordLength,
    game.settings.dictionary
  );
  const continuationValid = validateClaimedWord(
    continuationWord,
    fragmentUpper,
    game.settings.minWordLength,
    game.settings.dictionary
  );

  console.log("=== WORD CALL CONTINUE DEBUG ===");
  console.log("Called word:", wordCall.calledWord, "valid:", calledWordValid.isValid);
  console.log("Continuation:", continuationWord, "valid:", continuationValid.isValid);

  let winnerId: string | null = null;
  let winnerName: string | null = null;
  let pointsAwarded = 0;
  let loserId: string;

  if (continuationValid.isValid) {
    // Responder wins with continuation
    winnerId = wordCall.responderId;
    winnerName = wordCall.responderName;
    const wordPot = calculateWordPot(wordCall.wordFragment, game.settings.dictionary);
    const wordBonus = calculateWordPot(continuationWord, game.settings.dictionary) - wordPot;
    pointsAwarded = wordPot + wordBonus;
    loserId = wordCall.callerId;
  } else if (calledWordValid.isValid) {
    // Caller wins - their word was valid and continuation failed
    winnerId = wordCall.callerId;
    winnerName = wordCall.callerName;
    const wordPot = calculateWordPot(wordCall.wordFragment, game.settings.dictionary);
    const wordBonus = calculateWordPot(wordCall.calledWord, game.settings.dictionary) - wordPot;
    pointsAwarded = wordPot + wordBonus;
    loserId = wordCall.responderId;
  } else {
    // Both invalid - no points, responder starts next
    loserId = wordCall.responderId;
  }

  return finalizeWordCallResponse(
    transaction,
    gameRef,
    game,
    wordCall,
    "continue",
    continuationWord,
    calledWordValid.isValid,
    continuationValid.isValid,
    winnerId,
    winnerName,
    pointsAwarded,
    loserId
  );
}

/**
 * Handle 'challenge' response - responder disputes the called word
 */
async function handleWordCallChallengeResponse(
  transaction: FirebaseFirestore.Transaction,
  gameRef: FirebaseFirestore.DocumentReference,
  game: Game,
  wordCall: PendingWordCall
): Promise<Record<string, unknown>> {
  const fragmentUpper = wordCall.wordFragment.toUpperCase();
  const calledWordValid = validateClaimedWord(
    wordCall.calledWord.toUpperCase(),
    fragmentUpper,
    game.settings.minWordLength,
    game.settings.dictionary
  );

  console.log("=== WORD CALL CHALLENGE DEBUG ===");
  console.log("Called word:", wordCall.calledWord, "valid:", calledWordValid.isValid);

  let winnerId: string;
  let winnerName: string;
  let pointsAwarded: number;
  let loserId: string;

  if (!calledWordValid.isValid) {
    // Challenge successful - responder wins bluff bonus
    winnerId = wordCall.responderId;
    winnerName = wordCall.responderName;
    const wordPot = calculateWordPot(wordCall.wordFragment, game.settings.dictionary);
    pointsAwarded = Math.max(2, Math.floor(wordPot * 0.3));
    loserId = wordCall.callerId;
  } else {
    // Challenge failed - caller wins with their valid word
    winnerId = wordCall.callerId;
    winnerName = wordCall.callerName;
    const wordPot = calculateWordPot(wordCall.wordFragment, game.settings.dictionary);
    const wordBonus = calculateWordPot(wordCall.calledWord, game.settings.dictionary) - wordPot;
    pointsAwarded = wordPot + wordBonus;
    loserId = wordCall.responderId;
  }

  return finalizeWordCallResponse(
    transaction,
    gameRef,
    game,
    wordCall,
    "challenge",
    null,
    calledWordValid.isValid,
    null,
    winnerId,
    winnerName,
    pointsAwarded,
    loserId
  );
}

/**
 * Handle 'accept' response - responder accepts the called word
 */
async function handleAcceptResponse(
  transaction: FirebaseFirestore.Transaction,
  gameRef: FirebaseFirestore.DocumentReference,
  game: Game,
  wordCall: PendingWordCall
): Promise<Record<string, unknown>> {
  const fragmentUpper = wordCall.wordFragment.toUpperCase();
  const calledWordValid = validateClaimedWord(
    wordCall.calledWord.toUpperCase(),
    fragmentUpper,
    game.settings.minWordLength,
    game.settings.dictionary
  );

  console.log("=== WORD CALL ACCEPT DEBUG ===");
  console.log("Called word:", wordCall.calledWord, "valid:", calledWordValid.isValid);

  let winnerId: string | null = null;
  let winnerName: string | null = null;
  let pointsAwarded = 0;
  let loserId: string;

  if (calledWordValid.isValid) {
    // Caller wins with their word
    winnerId = wordCall.callerId;
    winnerName = wordCall.callerName;
    const wordPot = calculateWordPot(wordCall.wordFragment, game.settings.dictionary);
    const wordBonus = calculateWordPot(wordCall.calledWord, game.settings.dictionary) - wordPot;
    pointsAwarded = wordPot + wordBonus;
    loserId = wordCall.responderId;
  } else {
    // Caller's word was invalid but not challenged - no points
    loserId = wordCall.callerId;
  }

  return finalizeWordCallResponse(
    transaction,
    gameRef,
    game,
    wordCall,
    "accept",
    null,
    calledWordValid.isValid,
    null,
    winnerId,
    winnerName,
    pointsAwarded,
    loserId
  );
}

/**
 * Finalize word call response - update scores, reset word, determine next player
 */
function finalizeWordCallResponse(
  transaction: FirebaseFirestore.Transaction,
  gameRef: FirebaseFirestore.DocumentReference,
  game: Game,
  wordCall: PendingWordCall,
  responseType: "continue" | "challenge" | "accept" | "timeout",
  continuationWord: string | null,
  wasCalledWordValid: boolean,
  wasContinuationValid: boolean | null,
  winnerId: string | null,
  winnerName: string | null,
  pointsAwarded: number,
  loserId: string
): Record<string, unknown> {
  // Update winner's score if there is one
  const updatedPlayers = { ...game.players };
  if (winnerId && pointsAwarded > 0) {
    const previousScore = updatedPlayers[winnerId].score;
    updatedPlayers[winnerId] = {
      ...updatedPlayers[winnerId],
      score: previousScore + pointsAwarded,
    };
  }

  // Check for game winner
  const winCheck = checkForWinner(updatedPlayers, game.settings.targetScore);

  // Loser starts next round
  const nextPlayerIndex = game.playerIds.indexOf(loserId);

  // Build scoring details
  const scoringDetails: ScoringDetails | null =
    winnerId && pointsAwarded > 0
      ? {
          wordPot: calculateWordPot(wordCall.wordFragment, game.settings.dictionary),
          wordBonus:
            responseType === "challenge" && !wasCalledWordValid
              ? null
              : calculateWordPot(wasContinuationValid === true ? (continuationWord ?? wordCall.calledWord) : wordCall.calledWord, game.settings.dictionary) -
                calculateWordPot(wordCall.wordFragment, game.settings.dictionary),
          bluffBonus:
            responseType === "challenge" && !wasCalledWordValid
              ? pointsAwarded
              : null,
          totalAwarded: pointsAwarded,
          awardedTo: winnerId,
          awardedToName: winnerName!,
          breakdown: `Word Call ${responseType}: ${pointsAwarded} points`,
        }
      : null;

  // Build last action
  const lastAction: LastAction = {
    playerId: wordCall.responderId,
    playerName: wordCall.responderName,
    type: `word_call_${responseType}`,
    letter: null,
    previousWord: wordCall.wordFragment,
    resultingWord: "",
    scoringDetails,
    timestamp: Timestamp.now(),
  };

  // Write turn history
  const turnRef = gameRef.collection("turns").doc(String(game.turnNumber + 1));
  transaction.set(turnRef, {
    turnNumber: game.turnNumber + 1,
    playerId: wordCall.responderId,
    playerDisplayName: wordCall.responderName,
    actionType: `word_call_${responseType}`,
    calledWord: wordCall.calledWord,
    continuationWord,
    wasCalledWordValid,
    wasContinuationValid,
    winnerId,
    pointsAwarded,
    timestamp: FieldValue.serverTimestamp(),
  });

  // Build word call history entry
  const historyEntry: WordCallHistoryEntry = {
    wordFragment: wordCall.wordFragment,
    calledWord: wordCall.calledWord,
    responseType,
    continuationWord,
    wasCalledWordValid,
    wasContinuationValid,
    winnerId,
    winnerName,
    pointsAwarded,
    timestamp: Timestamp.now(),
    callerName: wordCall.callerName,
    responderName: wordCall.responderName,
  };

  // Build game update
  const gameUpdate: Record<string, unknown> = {
    currentWord: "",
    wordPot: 0,
    pendingWordCall: null,
    currentPlayerIndex: nextPlayerIndex,
    turnNumber: game.turnNumber + 1,
    wordTurnNumber: 1,
    players: updatedPlayers,
    lastAction,
    wordCallHistory: FieldValue.arrayUnion(historyEntry),
    updatedAt: FieldValue.serverTimestamp(),
  };

  if (winCheck.hasWinner) {
    gameUpdate.status = "completed";
    gameUpdate.winnerId = winCheck.winnerId;
    gameUpdate.winnerName = winCheck.winnerName;
    gameUpdate.endReason = "target_score_reached";
    gameUpdate.turnDeadline = null;
  } else {
    gameUpdate.status = "in_progress";
    gameUpdate.turnDeadline = calculateTurnDeadline(game.settings);
  }

  transaction.update(gameRef, gameUpdate);

  return {
    success: true,
    responseType,
    wasCalledWordValid,
    wasContinuationValid,
    winnerId,
    winnerName,
    pointsAwarded,
    isGameOver: winCheck.hasWinner,
  };
}

// ═══════════════════════════════════════════════════════════════
// ABANDON GAME (Player forfeits mid-game)
// ═══════════════════════════════════════════════════════════════

export const abandonGame = onCall<{ gameId: string }>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { gameId } = request.data;
  const playerId = request.auth.uid;

  if (!gameId || typeof gameId !== "string") {
    throw new HttpsError("invalid-argument", "Missing gameId");
  }

  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (transaction) => {
    const gameDoc = await transaction.get(gameRef);
    if (!gameDoc.exists) throw new HttpsError("not-found", "Game not found");

    const game = gameDoc.data() as Game;

    if (!game.playerIds.includes(playerId)) {
      throw new HttpsError("permission-denied", "Not a player in this game");
    }

    if (
      game.status === "in_progress" ||
      game.status === "challenge_pending" ||
      game.status === "word_call_pending"
    ) {
      // Player is leaving an active game — give the opponent 60 s to wait.
      // The opponent can choose to quit immediately or wait for auto-win.
      transaction.update(gameRef, {
        status: "waiting_for_rejoin",
        abandonedBy: playerId,
        rejoinDeadline: Timestamp.fromMillis(Date.now() + 60 * 1000),
        pendingChallenge: null,
        pendingWordCall: null,
        turnDeadline: null,
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (game.status === "waiting_for_rejoin") {
      if (game.abandonedBy === playerId) {
        // Player A called abandon again — no-op (use rejoinGame to come back)
        return;
      }
      // Player B chose to quit while waiting — no winner, both forfeited
      transaction.update(gameRef, {
        status: "abandoned",
        winnerId: null,
        winnerName: null,
        endReason: "both_forfeited",
        abandonedBy: FieldValue.delete(),
        rejoinDeadline: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    // completed / abandoned — no-op
  });

  // Cancel the lobby so matchmaking won't redirect back here
  try {
    const lobbySnap = await db
      .collection("lobbies")
      .where("gameId", "==", gameId)
      .limit(1)
      .get();
    if (!lobbySnap.empty) {
      await lobbySnap.docs[0].ref.update({
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  } catch {
    // Non-critical
  }

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════
// REJOIN GAME (Player A returns within the 60-second window)
// ═══════════════════════════════════════════════════════════════

export const rejoinGame = onCall<{ gameId: string }>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { gameId } = request.data;
  const playerId = request.auth.uid;

  if (!gameId || typeof gameId !== "string") {
    throw new HttpsError("invalid-argument", "Missing gameId");
  }

  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (transaction) => {
    const gameDoc = await transaction.get(gameRef);
    if (!gameDoc.exists) throw new HttpsError("not-found", "Game not found");

    const game = gameDoc.data() as Game;

    if (game.status !== "waiting_for_rejoin") {
      throw new HttpsError("failed-precondition", "Game is not waiting for rejoin");
    }
    if (game.abandonedBy !== playerId) {
      throw new HttpsError("permission-denied", "You did not abandon this game");
    }
    if (game.rejoinDeadline && game.rejoinDeadline.toDate() < new Date()) {
      throw new HttpsError("deadline-exceeded", "Rejoin window has expired");
    }

    transaction.update(gameRef, {
      status: "in_progress",
      abandonedBy: FieldValue.delete(),
      rejoinDeadline: FieldValue.delete(),
      turnDeadline: calculateTurnDeadline(game.settings),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════
// CLAIM ABANDON WIN (Player B calls when the rejoin timer expires)
// ═══════════════════════════════════════════════════════════════

export const claimAbandonWin = onCall<{ gameId: string }>(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in");
  }

  const { gameId } = request.data;
  const playerId = request.auth.uid;

  if (!gameId || typeof gameId !== "string") {
    throw new HttpsError("invalid-argument", "Missing gameId");
  }

  const gameRef = db.collection("games").doc(gameId);

  await db.runTransaction(async (transaction) => {
    const gameDoc = await transaction.get(gameRef);
    if (!gameDoc.exists) throw new HttpsError("not-found", "Game not found");

    const game = gameDoc.data() as Game;

    if (game.status !== "waiting_for_rejoin") {
      throw new HttpsError("failed-precondition", "Game is not waiting for rejoin");
    }

    if (!game.playerIds.includes(playerId)) {
      throw new HttpsError("permission-denied", "Not a player in this game");
    }

    // Only the non-abandoning player can claim the win
    if (game.abandonedBy === playerId) {
      throw new HttpsError("permission-denied", "You abandoned this game");
    }

    // Deadline must have passed
    if (game.rejoinDeadline && game.rejoinDeadline.toDate() > new Date()) {
      throw new HttpsError("failed-precondition", "Rejoin window has not expired yet");
    }

    const winnerName = game.players[playerId]?.displayName ?? null;
    const wordPot = game.wordPot ?? 0;
    const currentScore = game.players[playerId]?.score ?? 0;

    transaction.update(gameRef, {
      status: "completed",
      winnerId: playerId,
      winnerName,
      endReason: "opponent_forfeited",
      [`players.${playerId}.score`]: currentScore + wordPot,
      wordPot: 0,
      abandonedBy: FieldValue.delete(),
      rejoinDeadline: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  // Cancel the lobby
  try {
    const lobbySnap = await db
      .collection("lobbies")
      .where("gameId", "==", gameId)
      .limit(1)
      .get();
    if (!lobbySnap.empty) {
      await lobbySnap.docs[0].ref.update({
        status: "cancelled",
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  } catch { /* non-critical */ }

  return { success: true };
});

// ═══════════════════════════════════════════════════════════════
// CLEANUP STALE GAMES (Scheduled)
// Abandons in-progress games that haven't been updated in 5+ minutes.
// This covers force-close, network loss, and any other case where
// abandonGame was never explicitly called.
// ═══════════════════════════════════════════════════════════════

export const cleanupStaleGames = onSchedule("every 2 minutes", async () => {
  const staleThreshold = Timestamp.fromMillis(
    Date.now() - 5 * 60 * 1000 // 5 minutes ago
  );

  // Query only by updatedAt — single-field index, no composite index needed.
  // Filter active statuses in code to avoid a missing composite index error.
  const snapshot = await db
    .collection("games")
    .where("updatedAt", "<", staleThreshold)
    .limit(50)
    .get();

  const activeStatuses = new Set(["in_progress", "challenge_pending", "word_call_pending"]);
  const staleGameDocs = snapshot.docs.filter(
    (doc) => activeStatuses.has(doc.data().status)
  );

  if (staleGameDocs.length === 0) {
    console.log("No stale games found");
    return;
  }

  // Phase 2: resolve expired waiting_for_rejoin games → opponent wins
  const waitingSnapshot = await db
    .collection("games")
    .where("status", "==", "waiting_for_rejoin")
    .limit(20)
    .get();

  const now = new Date();
  const expiredWaiting = waitingSnapshot.docs.filter((doc) => {
    const deadline = doc.data().rejoinDeadline as Timestamp | undefined;
    return deadline && deadline.toDate() < now;
  });

  for (const gameDoc of expiredWaiting) {
    try {
      const game = gameDoc.data() as Game;
      const winnerId = game.playerIds.find((id: string) => id !== game.abandonedBy) ?? null;
      const winnerName = winnerId ? (game.players[winnerId]?.displayName ?? null) : null;
      const wordPot = game.wordPot ?? 0;
      const winnerScore = winnerId ? (game.players[winnerId]?.score ?? 0) : 0;

      await db.runTransaction(async (tx) => {
        const freshDoc = await tx.get(gameDoc.ref);
        if (!freshDoc.exists) return;
        if (freshDoc.data()?.status !== "waiting_for_rejoin") return;

        const updates: Record<string, unknown> = {
          status: "completed",
          winnerId,
          winnerName,
          endReason: "opponent_forfeited",
          abandonedBy: FieldValue.delete(),
          rejoinDeadline: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        };

        // Award the word pot to the winner's score
        if (winnerId && wordPot > 0) {
          updates[`players.${winnerId}.score`] = winnerScore + wordPot;
          updates.wordPot = 0;
        }

        tx.update(gameDoc.ref, updates);
      });

      try {
        const lobbySnap = await db
          .collection("lobbies")
          .where("gameId", "==", gameDoc.id)
          .limit(1)
          .get();
        if (!lobbySnap.empty) {
          await lobbySnap.docs[0].ref.update({
            status: "cancelled",
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      } catch { /* non-critical */ }

      console.log(`Expired rejoin: game ${gameDoc.id}, winner: ${winnerName}`);
    } catch (err) {
      console.error(`Failed to resolve expired rejoin for game ${gameDoc.id}:`, err);
    }
  }

  console.log(`Found ${staleGameDocs.length} stale games to abandon`);

  for (const gameDoc of staleGameDocs) {
    try {
      const game = gameDoc.data() as Game;

      // Award win to the opponent of whoever should have moved next.
      // For in_progress: currentPlayerIndex is the player who hasn't moved.
      // For pending states: same logic — the current player is the slow one.
      const offenderId = game.playerIds[game.currentPlayerIndex];
      const winnerId = game.playerIds.find((id: string) => id !== offenderId) ?? null;
      const winnerName = winnerId ? (game.players[winnerId]?.displayName ?? null) : null;

      await db.runTransaction(async (tx) => {
        const freshDoc = await tx.get(gameDoc.ref);
        if (!freshDoc.exists) return;
        const fresh = freshDoc.data() as Game;
        // Skip if already resolved (race condition guard)
        if (fresh.status === "completed" || fresh.status === "abandoned") return;

        tx.update(gameDoc.ref, {
          status: "abandoned",
          winnerId,
          winnerName,
          endReason: "opponent_forfeited",
          pendingChallenge: null,
          pendingWordCall: null,
          turnDeadline: null,
          updatedAt: FieldValue.serverTimestamp(),
        });
      });

      // Mark linked lobby as cancelled
      try {
        const lobbySnap = await db
          .collection("lobbies")
          .where("gameId", "==", gameDoc.id)
          .limit(1)
          .get();
        if (!lobbySnap.empty) {
          await lobbySnap.docs[0].ref.update({
            status: "cancelled",
            updatedAt: FieldValue.serverTimestamp(),
          });
        }
      } catch {
        // Non-critical
      }

      console.log(`Abandoned stale game ${gameDoc.id}, winner: ${winnerName}`);
    } catch (err) {
      console.error(`Failed to abandon game ${gameDoc.id}:`, err);
    }
  }
});
