import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend.dart';
import '../services/friend_service.dart';
import 'auth_provider.dart';

/// Watch a specific user's online status directly from their user doc.
/// This is the source of truth — no dependency on friend subcollection propagation.
final userOnlineStatusStreamProvider = StreamProvider.family<bool, String>((ref, userId) {
  return FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .snapshots()
      .map((doc) => doc.data()?['isOnline'] as bool? ?? false);
});

/// Raw friends from Firestore subcollection (without live online status).
/// Invalidate this to force a refresh of the friends list.
final rawFriendsProvider = StreamProvider<List<Friend>>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value([]);

  final friendService = ref.watch(friendServiceProvider);
  return friendService.watchFriends(userId);
});

/// Stream of all accepted friends with live online status from their user docs.
/// This replaces the old friendsProvider that relied on propagated isOnline.
final friendsProvider = Provider<AsyncValue<List<Friend>>>((ref) {
  final rawFriends = ref.watch(rawFriendsProvider);

  return rawFriends.whenData((friends) {
    return friends.map((friend) {
      // Watch each friend's user doc for live online status
      final onlineAsync = ref.watch(userOnlineStatusStreamProvider(friend.odId));
      final isOnline = onlineAsync.valueOrNull ?? friend.isOnline;
      return friend.copyWith(isOnline: isOnline);
    }).toList();
  });
});

/// Online friends derived client-side from [friendsProvider].
final onlineFriendsProvider = Provider<List<Friend>>((ref) {
  return ref.watch(friendsProvider).valueOrNull?.where((f) => f.isOnline).toList() ?? [];
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
