import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/lobby.dart';

/// Matchmaking service provider
final matchmakingServiceProvider = Provider<MatchmakingService>((ref) {
  return MatchmakingService(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

/// Result of joining or creating a lobby
class MatchResult {
  final String lobbyId;
  final String? gameId;
  final bool alreadyJoined;

  const MatchResult({
    required this.lobbyId,
    this.gameId,
    this.alreadyJoined = false,
  });

  /// Check if game is ready to start
  bool get isGameReady => gameId != null;
}

/// Service for matchmaking operations
class MatchmakingService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  MatchmakingService(this._firestore, this._functions);

  /// Collection reference
  CollectionReference<Map<String, dynamic>> get _lobbiesCollection =>
      _firestore.collection('lobbies');

  /// Join or create a lobby
  /// This calls a Cloud Function that handles the matchmaking atomically
  Future<MatchResult> joinOrCreateLobby(String playerName) async {
    final callable = _functions.httpsCallable('joinOrCreateLobby');
    final result = await callable.call<Map<String, dynamic>>({
      'playerName': playerName,
      'dictionary': kDictionary,
    });

    final data = result.data;
    return MatchResult(
      lobbyId: data['lobbyId'] as String,
      gameId: data['gameId'] as String?,
      alreadyJoined: data['alreadyJoined'] as bool? ?? false,
    );
  }

  /// Leave a lobby
  Future<void> leaveLobby(String lobbyId) async {
    final callable = _functions.httpsCallable('leaveLobby');
    await callable.call<void>({
      'lobbyId': lobbyId,
    });
  }

  /// Watch a specific lobby for changes
  Stream<Lobby?> watchLobby(String lobbyId) {
    return _lobbiesCollection.doc(lobbyId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Lobby.fromFirestore(doc);
    });
  }

  /// Get available lobbies (waiting status)
  Stream<List<Lobby>> watchAvailableLobbies() {
    return _lobbiesCollection
        .where('status', isEqualTo: 'waiting')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Lobby.fromFirestore(doc)).toList();
    });
  }
}
