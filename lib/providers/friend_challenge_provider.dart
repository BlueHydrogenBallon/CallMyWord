import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend_challenge.dart';
import '../services/friend_challenge_service.dart';
import 'auth_provider.dart';
import 'game_state_provider.dart';

/// Stream of incoming challenges (where current user is the challenged)
final incomingChallengesProvider = StreamProvider<List<FriendChallenge>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  // Pause listener during active gameplay — user cannot accept challenges mid-game
  if (ref.watch(isInActiveGameProvider)) return Stream.value([]);

  final challengeService = ref.watch(friendChallengeServiceProvider);
  return challengeService.watchIncomingChallenges(userId);
});

/// Stream of outgoing challenges (where current user is the challenger)
final outgoingChallengesProvider = StreamProvider<List<FriendChallenge>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final challengeService = ref.watch(friendChallengeServiceProvider);
  return challengeService.watchOutgoingChallenges(userId);
});

/// Watch a specific challenge by ID
final challengeProvider =
    StreamProvider.family<FriendChallenge?, String>((ref, challengeId) {
  final challengeService = ref.watch(friendChallengeServiceProvider);
  return challengeService.watchChallenge(challengeId);
});

/// Count of incoming challenges
final incomingChallengeCountProvider = Provider<int>((ref) {
  return ref.watch(incomingChallengesProvider).value?.length ?? 0;
});

/// Whether there are any active incoming challenges
final hasIncomingChallengesProvider = Provider<bool>((ref) {
  return ref.watch(incomingChallengeCountProvider) > 0;
});
