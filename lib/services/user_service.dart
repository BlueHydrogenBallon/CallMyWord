import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../providers/auth_provider.dart';

/// User service provider
final userServiceProvider = Provider<UserService>((ref) {
  return UserService(FirebaseFirestore.instance, FirebaseFunctions.instance);
});

/// Current user profile stream
final currentUserProfileProvider = StreamProvider<UserProfile?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);

  final userService = ref.watch(userServiceProvider);
  return userService.watchUserProfile(userId);
});

/// Service for user profile operations
class UserService {
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  // In-memory profile cache to avoid redundant Firestore reads on app resume
  UserProfile? _cachedProfile;
  DateTime? _cacheTime;
  static const _cacheTtl = Duration(minutes: 5);

  UserService(this._firestore, this._functions);

  /// Collection reference
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// Get user profile by ID
  Future<UserProfile?> getUserProfile(String userId) async {
    final doc = await _usersCollection.doc(userId).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  /// Watch user profile changes
  Stream<UserProfile?> watchUserProfile(String userId) {
    return _usersCollection.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserProfile.fromFirestore(doc);
    });
  }

  /// Create user profile for new user
  Future<void> createUserProfile({
    required String userId,
    required String displayName,
    required bool isAnonymous,
  }) async {
    final profile = UserProfile(
      id: userId,
      displayName: displayName,
      isAnonymous: isAnonymous,
      createdAt: DateTime.now(),
      lastActiveAt: DateTime.now(),
    );

    await _usersCollection.doc(userId).set(profile.toFirestore());
  }

  /// Update user's display name
  Future<void> updateDisplayName(String userId, String displayName) async {
    _cachedProfile = null;
    _cacheTime = null;
    await _usersCollection.doc(userId).update({
      'displayName': displayName,
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update last active timestamp
  Future<void> updateLastActive(String userId) async {
    await _usersCollection.doc(userId).update({
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Check if user profile exists
  Future<bool> userProfileExists(String userId) async {
    final doc = await _usersCollection.doc(userId).get();
    return doc.exists;
  }

  /// Ensure user profile exists, create if not
  Future<UserProfile> ensureUserProfile({
    required String userId,
    required String defaultDisplayName,
    required bool isAnonymous,
  }) async {
    // Return cached profile if fresh (avoids redundant reads on app resume)
    if (_cachedProfile != null &&
        _cachedProfile!.id == userId &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheTtl) {
      updateLastActive(userId); // fire-and-forget write, no read needed
      return _cachedProfile!;
    }

    final existing = await getUserProfile(userId);
    if (existing != null) {
      await updateLastActive(userId);
      _cachedProfile = existing;
      _cacheTime = DateTime.now();
      return existing;
    }

    // Create new profile
    await createUserProfile(
      userId: userId,
      displayName: defaultDisplayName,
      isAnonymous: isAnonymous,
    );

    final fresh = (await getUserProfile(userId))!;
    _cachedProfile = fresh;
    _cacheTime = DateTime.now();
    return fresh;
  }

  /// Update user's avatar
  Future<void> updateAvatar(String userId, String avatarKey) async {
    _cachedProfile = null;
    _cacheTime = null;
    await _usersCollection.doc(userId).update({
      'avatarUrl': avatarKey,
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Generate (or retrieve) the invite code via Cloud Function
  Future<String> generateInviteCode() async {
    final result =
        await _functions.httpsCallable('generateInviteCode').call();
    return result.data['inviteCode'] as String;
  }

  /// Get game history via Cloud Function
  Future<List<Map<String, dynamic>>> getGameHistory({int limit = 20}) async {
    final result = await _functions
        .httpsCallable('getGameHistory')
        .call({'limit': limit});
    final games = result.data['games'] as List<dynamic>;
    return games.map((g) => Map<String, dynamic>.from(g as Map)).toList();
  }
}
