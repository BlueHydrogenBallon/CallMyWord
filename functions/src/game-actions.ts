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
  LastAction,
  PendingChallenge,
  PendingWordCall,
  ScoringDetails,
  ChallengeHistoryEntry,
  WordCallHistoryEntry,
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
  if (!letter || typeof letter !== "string" || !/^[A-Z]$/i.test(letter)) {
    throw new HttpsError(
      "invalid-argument",
      "Letter must be a single A-Z character"
    );
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
    const letterPoints = getLetterPoints(upperLetter);
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

      // Create pending challenge
      const pendingChallenge: PendingChallenge = {
        challengerId,
        challengerName: game.players[challengerId].displayName,
        challengedPlayerId,
        challengedPlayerName: game.players[challengedPlayerId].displayName,
        wordFragment: game.currentWord,
        responseDeadline: calculateChallengeDeadline(game.settings),
        createdAt: Timestamp.now(),
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

    if (!/^[A-Z]+$/.test(normalizedWord)) {
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
        game.settings.minWordLength
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
          challenge.challengedPlayerName
        );
      } else {
        // Challenger wins
        console.log("CHALLENGER WINS - awarding points to:", challenge.challengerName);
        scoringResult = calculateChallengerWinScore(
          challenge.wordFragment,
          challenge.challengerId,
          challenge.challengerName
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
      };

      // Build game update
      const gameUpdate: Record<string, unknown> = {
        currentWord: "", // Reset word
        wordPot: 0, // Reset pot
        pendingChallenge: null,
        currentPlayerIndex: nextPlayerIndex,
        turnNumber: game.turnNumber + 1,
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
      challenge.challengerName
    );

    // Update scores
    const updatedPlayers = { ...freshGame.players };
    const previousScore = updatedPlayers[scoringResult.winnerId].score;
    const newScore = previousScore + scoringResult.totalAwarded;
    updatedPlayers[scoringResult.winnerId] = {
      ...updatedPlayers[scoringResult.winnerId],
      score: newScore,
    };

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
    };

    const gameUpdate: Record<string, unknown> = {
      currentWord: "",
      wordPot: 0,
      pendingChallenge: null,
      currentPlayerIndex: nextPlayerIndex,
      turnNumber: freshGame.turnNumber + 1,
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

    // Validate the called word
    const calledWordValid = validateClaimedWord(
      wordCall.calledWord,
      wordCall.wordFragment,
      freshGame.settings.minWordLength
    );

    let winnerId: string | null = null;
    let winnerName: string | null = null;
    let pointsAwarded = 0;
    let loserId: string;

    if (calledWordValid.isValid) {
      // Caller wins with their word (timeout = implicit accept)
      winnerId = wordCall.callerId;
      winnerName = wordCall.callerName;
      const wordPot = calculateWordPot(wordCall.wordFragment);
      const wordBonus = wordCall.calledWord.length - wordCall.wordFragment.length;
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
            wordPot: calculateWordPot(wordCall.wordFragment),
            wordBonus: wordCall.calledWord.length - wordCall.wordFragment.length,
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
    };

    const gameUpdate: Record<string, unknown> = {
      currentWord: "",
      wordPot: 0,
      pendingWordCall: null,
      currentPlayerIndex: nextPlayerIndex,
      turnNumber: freshGame.turnNumber + 1,
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

  if (!/^[A-Z]+$/.test(normalizedWord)) {
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

    // Get responder (opponent)
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

      if (wordCall.responderId !== responderId) {
        throw new HttpsError(
          "permission-denied",
          "You are not the responder"
        );
      }

      // Check deadline
      if (wordCall.responseDeadline.toDate() < new Date()) {
        throw new HttpsError("deadline-exceeded", "Response time has expired");
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

  // Continuation must be longer than called word
  if (continuationWord.length <= wordCall.calledWord.length) {
    throw new HttpsError(
      "invalid-argument",
      "Continuation word must be longer than called word"
    );
  }

  // Validate both words (ensure uppercase for dictionary lookup)
  const calledWordValid = validateClaimedWord(
    wordCall.calledWord.toUpperCase(),
    fragmentUpper,
    game.settings.minWordLength
  );
  const continuationValid = validateClaimedWord(
    continuationWord,
    fragmentUpper,
    game.settings.minWordLength
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
    const wordPot = calculateWordPot(wordCall.wordFragment);
    const wordBonus = continuationWord.length - wordCall.wordFragment.length;
    pointsAwarded = wordPot + wordBonus;
    loserId = wordCall.callerId;
  } else if (calledWordValid.isValid) {
    // Caller wins - their word was valid and continuation failed
    winnerId = wordCall.callerId;
    winnerName = wordCall.callerName;
    const wordPot = calculateWordPot(wordCall.wordFragment);
    const wordBonus = wordCall.calledWord.length - wordCall.wordFragment.length;
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
    game.settings.minWordLength
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
    const wordPot = calculateWordPot(wordCall.wordFragment);
    pointsAwarded = Math.max(2, Math.floor(wordPot * 0.3));
    loserId = wordCall.callerId;
  } else {
    // Challenge failed - caller wins with their valid word
    winnerId = wordCall.callerId;
    winnerName = wordCall.callerName;
    const wordPot = calculateWordPot(wordCall.wordFragment);
    const wordBonus = wordCall.calledWord.length - wordCall.wordFragment.length;
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
    game.settings.minWordLength
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
    const wordPot = calculateWordPot(wordCall.wordFragment);
    const wordBonus = wordCall.calledWord.length - wordCall.wordFragment.length;
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
          wordPot: calculateWordPot(wordCall.wordFragment),
          wordBonus:
            responseType === "challenge" && !wasCalledWordValid
              ? null
              : (continuationWord || wordCall.calledWord).length -
                wordCall.wordFragment.length,
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
  };

  // Build game update
  const gameUpdate: Record<string, unknown> = {
    currentWord: "",
    wordPot: 0,
    pendingWordCall: null,
    currentPlayerIndex: nextPlayerIndex,
    turnNumber: game.turnNumber + 1,
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
