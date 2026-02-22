import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend.dart';
import '../services/friend_service.dart';
import 'auth_provider.dart';

/// Stream of all accepted friends for the current user
final friendsProvider = StreamProvider<List<Friend>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final friendService = ref.watch(friendServiceProvider);
  return friendService.watchFriends(userId);
});

/// Stream of online friends only
final onlineFriendsProvider = StreamProvider<List<Friend>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final friendService = ref.watch(friendServiceProvider);
  return friendService.watchOnlineFriends(userId);
});

/// Stream of pending friend requests (incoming)
final pendingFriendRequestsProvider = StreamProvider<List<Friend>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final friendService = ref.watch(friendServiceProvider);
  return friendService.watchPendingRequests(userId);
});

/// Count of pending friend requests
final pendingRequestCountProvider = Provider<int>((ref) {
  return ref.watch(pendingFriendRequestsProvider).value?.length ?? 0;
});

/// Current user's invite code
final userInviteCodeProvider = FutureProvider<String?>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final friendService = ref.watch(friendServiceProvider);
  return friendService.getInviteCode(userId);
});
