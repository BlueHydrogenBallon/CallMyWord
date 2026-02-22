import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../providers/auth_provider.dart';

/// User service provider
final userServiceProvider = Provider<UserService>((ref) {
  return UserService(FirebaseFirestore.instance);
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

  UserService(this._firestore);

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
    final existing = await getUserProfile(userId);
    if (existing != null) {
      // Update last active
      await updateLastActive(userId);
      return existing;
    }

    // Create new profile
    await createUserProfile(
      userId: userId,
      displayName: defaultDisplayName,
      isAnonymous: isAnonymous,
    );

    return (await getUserProfile(userId))!;
  }
}
