import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game.dart';

/// Result of a challenge response
class ChallengeResult {
  final bool wasWordValid;
  final String? failureReason;
  final String? winnerId;
  final String? winnerName;
  final int totalAwarded;

  const ChallengeResult({
    required this.wasWordValid,
    this.failureReason,
    this.winnerId,
    this.winnerName,
    this.totalAwarded = 0,
  });
}

/// Result of a word call response
class WordCallResult {
  final String responseType;
  final bool wasCalledWordValid;
  final bool? wasContinuationValid;
  final String? winnerId;
  final String? winnerName;
  final int pointsAwarded;

  const WordCallResult({
    required this.responseType,
    required this.wasCalledWordValid,
    this.wasContinuationValid,
    this.winnerId,
    this.winnerName,
    this.pointsAwarded = 0,
  });
}

/// Game service provider
final gameServiceProvider = Provider<GameService>((ref) {
  return GameService(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

/// Service for game operations
class GameService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  GameService(this._firestore, this._functions);

  /// Collection reference
  CollectionReference<Map<String, dynamic>> get _gamesCollection =>
      _firestore.collection('games');

  /// Watch a game for real-time updates
  Stream<Game?> watchGame(String gameId) {
    return _gamesCollection.doc(gameId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Game.fromFirestore(doc);
    });
  }

  /// Get a game by ID
  Future<Game?> getGame(String gameId) async {
    final doc = await _gamesCollection.doc(gameId).get();
    if (!doc.exists) return null;
    return Game.fromFirestore(doc);
  }

  /// Submit a move (add a letter)
  Future<void> submitMove(String gameId, String letter) async {
    final callable = _functions.httpsCallable('submitMove');
    await callable.call<void>({
      'gameId': gameId,
      'letter': letter.toUpperCase(),
    });
  }

  /// Initiate a challenge
  Future<void> initiateChallenge(String gameId) async {
    final callable = _functions.httpsCallable('initiateChallenge');
    await callable.call<void>({
      'gameId': gameId,
    });
  }

  /// Respond to a challenge with a claimed word
  /// Returns the validation result for debugging
  Future<ChallengeResult> respondToChallenge(String gameId, String claimedWord) async {
    final callable = _functions.httpsCallable('respondToChallenge');
    final result = await callable.call<Map<String, dynamic>>({
      'gameId': gameId,
      'claimedWord': claimedWord.toUpperCase(),
    });

    final data = result.data;
    final validationResult = data['validationResult'] as Map<String, dynamic>?;
    final scoringResult = data['scoringResult'] as Map<String, dynamic>?;

    return ChallengeResult(
      wasWordValid: validationResult?['isValid'] as bool? ?? false,
      failureReason: validationResult?['failureReason'] as String?,
      winnerId: scoringResult?['winnerId'] as String?,
      winnerName: scoringResult?['winnerName'] as String?,
      totalAwarded: scoringResult?['totalAwarded'] as int? ?? 0,
    );
  }

  /// Get player's active games
  Stream<List<Game>> watchPlayerGames(String playerId) {
    return _gamesCollection
        .where('playerIds', arrayContains: playerId)
        .where('status', isEqualTo: 'in_progress')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Game.fromFirestore(doc)).toList();
    });
  }

  /// Get player's completed games (history)
  Future<List<Game>> getPlayerGameHistory(String playerId, {int limit = 10}) async {
    final snapshot = await _gamesCollection
        .where('playerIds', arrayContains: playerId)
        .where('status', isEqualTo: 'completed')
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => Game.fromFirestore(doc)).toList();
  }

  /// Call a word (declare the word is complete)
  Future<void> callWord(String gameId, String calledWord) async {
    final callable = _functions.httpsCallable('callWord');
    await callable.call<void>({
      'gameId': gameId,
      'calledWord': calledWord.toUpperCase(),
    });
  }

  /// Respond to a word call
  /// responseType: 'continue', 'challenge', or 'accept'
  Future<WordCallResult> respondToWordCall(
    String gameId,
    String responseType, {
    String? continuationWord,
  }) async {
    final callable = _functions.httpsCallable('respondToWordCall');
    final result = await callable.call<Map<String, dynamic>>({
      'gameId': gameId,
      'responseType': responseType,
      if (continuationWord != null) 'continuationWord': continuationWord.toUpperCase(),
    });

    final data = result.data;

    return WordCallResult(
      responseType: data['responseType'] as String? ?? responseType,
      wasCalledWordValid: data['wasCalledWordValid'] as bool? ?? false,
      wasContinuationValid: data['wasContinuationValid'] as bool?,
      winnerId: data['winnerId'] as String?,
      winnerName: data['winnerName'] as String?,
      pointsAwarded: data['pointsAwarded'] as int? ?? 0,
    );
  }
}
