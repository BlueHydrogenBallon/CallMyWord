import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Party service provider
final partyServiceProvider = Provider<PartyService>((ref) {
  return PartyService(FirebaseFunctions.instance);
});

/// Result of creating a party lobby
class CreatePartyResult {
  final String lobbyId;
  final List<String> challengeIds;

  const CreatePartyResult({
    required this.lobbyId,
    required this.challengeIds,
  });
}

/// Result of joining a party lobby
class JoinPartyResult {
  final String lobbyId;
  final int playerCount;

  const JoinPartyResult({
    required this.lobbyId,
    required this.playerCount,
  });
}

/// Service for multiplayer party operations
class PartyService {
  final FirebaseFunctions _functions;

  PartyService(this._functions);

  /// Create a party lobby and invite friends
  Future<CreatePartyResult> createPartyLobby(List<String> friendIds) async {
    final callable = _functions.httpsCallable('createPartyLobby');
    final result = await callable.call<Map<String, dynamic>>({
      'invitedFriendIds': friendIds,
    });

    final data = result.data;
    return CreatePartyResult(
      lobbyId: data['lobbyId'] as String,
      challengeIds: List<String>.from(data['challengeIds'] ?? []),
    );
  }

  /// Join a party lobby (accept invitation)
  Future<JoinPartyResult> joinPartyLobby(String lobbyId, String challengeId) async {
    final callable = _functions.httpsCallable('joinPartyLobby');
    final result = await callable.call<Map<String, dynamic>>({
      'lobbyId': lobbyId,
      'challengeId': challengeId,
    });

    final data = result.data;
    return JoinPartyResult(
      lobbyId: data['lobbyId'] as String,
      playerCount: data['playerCount'] as int,
    );
  }

  /// Start the party game (host only)
  Future<String> startPartyGame(String lobbyId) async {
    final callable = _functions.httpsCallable('startPartyGame');
    final result = await callable.call<Map<String, dynamic>>({
      'lobbyId': lobbyId,
    });

    return result.data['gameId'] as String;
  }

  /// Leave a party lobby
  Future<void> leavePartyLobby(String lobbyId) async {
    final callable = _functions.httpsCallable('leavePartyLobby');
    await callable.call<void>({
      'lobbyId': lobbyId,
    });
  }
}
