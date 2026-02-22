import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Presence service provider
final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService(FirebaseFirestore.instance);
});

/// Service for managing user presence (online/offline status)
class PresenceService {
  final FirebaseFirestore _firestore;

  PresenceService(this._firestore);

  /// Collection reference
  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _firestore.collection('users');

  /// Set user as online and update heartbeat
  Future<void> setOnline(String userId) async {
    await _usersCollection.doc(userId).update({
      'isOnline': true,
      'lastHeartbeat': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Set user as offline
  Future<void> setOffline(String userId) async {
    await _usersCollection.doc(userId).update({
      'isOnline': false,
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Send heartbeat (called periodically to maintain online status)
  Future<void> heartbeat(String userId) async {
    await _usersCollection.doc(userId).update({
      'lastHeartbeat': FieldValue.serverTimestamp(),
      'lastActiveAt': FieldValue.serverTimestamp(),
    });
  }

  /// Watch a specific user's online status
  Stream<bool> watchUserPresence(String userId) {
    return _usersCollection.doc(userId).snapshots().map((doc) {
      if (!doc.exists) return false;
      return doc.data()?['isOnline'] as bool? ?? false;
    });
  }

  /// Get user's last active timestamp
  Future<DateTime?> getLastActive(String userId) async {
    final doc = await _usersCollection.doc(userId).get();
    if (!doc.exists) return null;

    final timestamp = doc.data()?['lastActiveAt'] as Timestamp?;
    return timestamp?.toDate();
  }
}
