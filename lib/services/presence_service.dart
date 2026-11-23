import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Presence service provider
final presenceServiceProvider = Provider<PresenceService>((ref) {
  return PresenceService(
    FirebaseFirestore.instance,
    FirebaseDatabase.instance,
  );
});

/// Service for managing user presence using Firebase RTDB onDisconnect().
///
/// How it works:
/// 1. Client writes {online: true} to RTDB `/status/{uid}`.
/// 2. Client registers onDisconnect() to write {online: false} — this runs
///    server-side when the connection drops (tab close, crash, network loss).
/// 3. A Cloud Function listens to RTDB `/status/{uid}` changes and mirrors
///    the status to Firestore (user doc + friend subcollections).
///
/// This eliminates the need for periodic heartbeats and scheduled cleanup.
class PresenceService {
  final FirebaseFirestore _firestore;
  final FirebaseDatabase _database;

  PresenceService(this._firestore, this._database);

  /// Reference to this user's RTDB presence node
  DatabaseReference _statusRef(String userId) =>
      _database.ref('status/$userId');

  /// Set up presence for the given user.
  ///
  /// Immediately writes online status and registers onDisconnect handler.
  /// Also sets up a listener on `.info/connected` to re-register on reconnect.
  ///
  /// Returns the stream subscription that must be cancelled on dispose.
  StreamSubscription<DatabaseEvent> setupPresence(String userId) {
    final userStatusRef = _statusRef(userId);

    final onlineData = <String, dynamic>{
      'online': true,
      'lastChanged': ServerValue.timestamp,
    };
    final offlineData = <String, dynamic>{
      'online': false,
      'lastChanged': ServerValue.timestamp,
    };

    // Do an immediate write attempt (don't wait for .info/connected)
    _writePresence(userStatusRef, onlineData, offlineData, userId);

    // Listen to RTDB connection state for reconnects
    return _database.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value as bool? ?? false;
      debugPrint('RTDB .info/connected = $connected for user $userId');

      if (connected) {
        _writePresence(userStatusRef, onlineData, offlineData, userId);
      }
    });
  }

  /// Write online status and register onDisconnect handler.
  Future<void> _writePresence(
    DatabaseReference ref,
    Map<String, dynamic> onlineData,
    Map<String, dynamic> offlineData,
    String userId,
  ) async {
    try {
      // Register the onDisconnect handler first (server-side)
      await ref.onDisconnect().set(offlineData);
      debugPrint('RTDB: onDisconnect registered for $userId');

      // Then set the current status to online
      await ref.set(onlineData);
      debugPrint('RTDB: user $userId set online');
    } catch (e) {
      debugPrint('RTDB presence error for $userId: $e');
    }
  }

  /// Explicitly set user offline (e.g. on sign-out).
  Future<void> setOffline(String userId) async {
    try {
      await _statusRef(userId).set({
        'online': false,
        'lastChanged': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Error setting offline: $e');
    }
  }

  /// Watch a specific user's online status (reads from Firestore).
  Stream<bool> watchUserPresence(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return false;
      return doc.data()?['isOnline'] as bool? ?? false;
    });
  }

  /// Get user's last active timestamp
  Future<DateTime?> getLastActive(String userId) async {
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return null;
    final timestamp = doc.data()?['lastActiveAt'] as Timestamp?;
    return timestamp?.toDate();
  }
}
