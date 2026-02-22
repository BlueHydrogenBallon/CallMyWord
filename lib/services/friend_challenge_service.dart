import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend_challenge.dart';

/// Friend challenge service provider
final friendChallengeServiceProvider = Provider<FriendChallengeService>((ref) {
  return FriendChallengeService(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

/// Result of challenging a friend
class FriendChallengeResult {
  final String challengeId;
  final String? lobbyId;

  const FriendChallengeResult({
    required this.challengeId,
    this.lobbyId,
  });
}

/// Result of accepting a challenge
class AcceptChallengeResult {
  final String gameId;
  final String lobbyId;

  const AcceptChallengeResult({
    required this.gameId,
    required this.lobbyId,
  });
}

/// Service for friend challenge operations
class FriendChallengeService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  FriendChallengeService(this._firestore, this._functions);

  /// Collection reference
  CollectionReference<Map<String, dynamic>> get _challengesCollection =>
      _firestore.collection('friendChallenges');

  /// Challenge a friend
  Future<FriendChallengeResult> challengeFriend(String friendUserId) async {
    final callable = _functions.httpsCallable('challengeFriend');
    final result = await callable.call<Map<String, dynamic>>({
      'friendUserId': friendUserId,
    });

    final data = result.data;
    return FriendChallengeResult(
      challengeId: data['challengeId'] as String,
      lobbyId: data['lobbyId'] as String?,
    );
  }

  /// Accept a challenge
  Future<AcceptChallengeResult> acceptChallenge(String challengeId) async {
    final callable = _functions.httpsCallable('acceptFriendChallenge');
    final result = await callable.call<Map<String, dynamic>>({
      'challengeId': challengeId,
    });

    final data = result.data;
    return AcceptChallengeResult(
      gameId: data['gameId'] as String,
      lobbyId: data['lobbyId'] as String,
    );
  }

  /// Decline a challenge
  Future<void> declineChallenge(String challengeId) async {
    final callable = _functions.httpsCallable('declineFriendChallenge');
    await callable.call<void>({
      'challengeId': challengeId,
    });
  }

  /// Cancel an outgoing challenge
  Future<void> cancelChallenge(String challengeId) async {
    final callable = _functions.httpsCallable('cancelFriendChallenge');
    await callable.call<void>({
      'challengeId': challengeId,
    });
  }

  /// Watch incoming challenges (where current user is the challenged)
  Stream<List<FriendChallenge>> watchIncomingChallenges(String userId) {
    return _challengesCollection
        .where('challengedId', isEqualTo: userId)
        .where('status', isEqualTo: ChallengeStatus.pending.name)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FriendChallenge.fromFirestore(doc))
          .toList();
    });
  }

  /// Watch outgoing challenges (where current user is the challenger)
  Stream<List<FriendChallenge>> watchOutgoingChallenges(String userId) {
    return _challengesCollection
        .where('challengerId', isEqualTo: userId)
        .where('status', isEqualTo: ChallengeStatus.pending.name)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => FriendChallenge.fromFirestore(doc))
          .toList();
    });
  }

  /// Watch a specific challenge
  Stream<FriendChallenge?> watchChallenge(String challengeId) {
    return _challengesCollection.doc(challengeId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return FriendChallenge.fromFirestore(doc);
    });
  }

  /// Get a specific challenge
  Future<FriendChallenge?> getChallenge(String challengeId) async {
    final doc = await _challengesCollection.doc(challengeId).get();
    if (!doc.exists) return null;
    return FriendChallenge.fromFirestore(doc);
  }
}
