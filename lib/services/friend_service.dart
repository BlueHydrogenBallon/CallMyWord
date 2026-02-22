import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend.dart';

/// Friend service provider
final friendServiceProvider = Provider<FriendService>((ref) {
  return FriendService(
    FirebaseFirestore.instance,
    FirebaseFunctions.instance,
  );
});

/// Service for friend-related operations
class FriendService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  FriendService(this._firestore, this._functions);

  /// Get friends subcollection reference for a user
  CollectionReference<Map<String, dynamic>> _friendsCollection(String userId) =>
      _firestore.collection('users').doc(userId).collection('friends');

  /// Watch all friends for a user
  Stream<List<Friend>> watchFriends(String userId) {
    return _friendsCollection(userId)
        .where('status', isEqualTo: FriendStatus.accepted.name)
        .orderBy('displayName')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Friend.fromFirestore(doc)).toList();
    });
  }

  /// Watch pending friend requests (incoming)
  Stream<List<Friend>> watchPendingRequests(String userId) {
    return _friendsCollection(userId)
        .where('status', isEqualTo: FriendStatus.pending.name)
        .snapshots()
        .map((snapshot) {
      // Filter out outgoing requests (where addedBy == userId) in code
      return snapshot.docs
          .map((doc) => Friend.fromFirestore(doc))
          .where((friend) => friend.addedBy != userId)
          .toList();
    });
  }

  /// Watch online friends only
  Stream<List<Friend>> watchOnlineFriends(String userId) {
    return _friendsCollection(userId)
        .where('status', isEqualTo: FriendStatus.accepted.name)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Friend.fromFirestore(doc)).toList();
    });
  }

  /// Add friend by invite code
  Future<void> addFriendByCode(String inviteCode) async {
    final callable = _functions.httpsCallable('addFriendByCode');
    await callable.call<void>({
      'inviteCode': inviteCode.toUpperCase().trim(),
    });
  }

  /// Accept a friend request
  Future<void> acceptFriendRequest(String friendUserId) async {
    final callable = _functions.httpsCallable('acceptFriendRequest');
    await callable.call<void>({
      'friendUserId': friendUserId,
    });
  }

  /// Decline a friend request
  Future<void> declineFriendRequest(String friendUserId) async {
    final callable = _functions.httpsCallable('declineFriendRequest');
    await callable.call<void>({
      'friendUserId': friendUserId,
    });
  }

  /// Remove a friend
  Future<void> removeFriend(String friendUserId) async {
    final callable = _functions.httpsCallable('removeFriend');
    await callable.call<void>({
      'friendUserId': friendUserId,
    });
  }

  /// Block a friend
  Future<void> blockFriend(String friendUserId) async {
    final callable = _functions.httpsCallable('blockFriend');
    await callable.call<void>({
      'friendUserId': friendUserId,
    });
  }

  /// Get or generate an invite code for the current user
  Future<String> getOrCreateInviteCode() async {
    final callable = _functions.httpsCallable('generateInviteCode');
    final result = await callable.call<Map<String, dynamic>>({});
    return result.data['inviteCode'] as String;
  }

  /// Get user's current invite code from their profile (without generating new one)
  Future<String?> getInviteCode(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return null;
    return doc.data()?['inviteCode'] as String?;
  }

  /// Find user by invite code
  Future<Map<String, dynamic>?> findUserByInviteCode(String inviteCode) async {
    final snapshot = await _firestore
        .collection('users')
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase().trim())
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final doc = snapshot.docs.first;
    return {
      'userId': doc.id,
      'displayName': doc.data()['displayName'],
      'avatarUrl': doc.data()['avatarUrl'],
    };
  }
}
