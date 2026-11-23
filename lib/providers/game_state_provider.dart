import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game.dart';
import '../providers/auth_provider.dart';
import '../services/game_service.dart';

/// When true, background collection listeners are paused to save Firestore reads.
/// Set to true when the user enters an active game, false when they leave.
final isInActiveGameProvider = StateProvider<bool>((ref) => false);

/// Streams the single game that the current user left and can still rejoin.
/// Emits null when no such game exists or the deadline has passed.
final rejoinableGameProvider = StreamProvider.autoDispose<Game?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return ref.read(gameServiceProvider).watchRejoinableGame(userId);
});
