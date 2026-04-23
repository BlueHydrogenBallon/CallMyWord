import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/presence_service.dart';
import 'auth_provider.dart';

/// Presence manager provider
final presenceManagerProvider = Provider<PresenceManager>((ref) {
  final manager = PresenceManager(ref);
  ref.onDispose(() {
    manager.dispose();
  });
  return manager;
});

/// Current user's online status
final userOnlineStatusProvider = StateProvider<bool>((ref) => false);

/// Manages user presence via Firebase RTDB onDisconnect().
///
/// No heartbeat timer needed — RTDB handles disconnect detection server-side.
class PresenceManager {
  final Ref _ref;
  StreamSubscription<DatabaseEvent>? _presenceSubscription;
  bool _isActive = false;

  PresenceManager(this._ref);

  /// Start presence tracking.
  Future<void> startPresence() async {
    if (_isActive) return;

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    _isActive = true;
    debugPrint('Starting RTDB presence for user: $userId');

    try {
      final presenceService = _ref.read(presenceServiceProvider);
      _presenceSubscription = presenceService.setupPresence(userId);
      _ref.read(userOnlineStatusProvider.notifier).state = true;
    } catch (e) {
      debugPrint('Error starting presence: $e');
      _isActive = false;
    }
  }

  /// Stop presence tracking (e.g. on sign-out).
  Future<void> stopPresence() async {
    if (!_isActive) return;

    _isActive = false;
    await _presenceSubscription?.cancel();
    _presenceSubscription = null;

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    debugPrint('Stopping presence for user: $userId');

    try {
      final presenceService = _ref.read(presenceServiceProvider);
      await presenceService.setOffline(userId);
      _ref.read(userOnlineStatusProvider.notifier).state = false;
    } catch (e) {
      debugPrint('Error stopping presence: $e');
    }
  }

  bool get isActive => _isActive;

  void dispose() {
    _presenceSubscription?.cancel();
    _presenceSubscription = null;
    _isActive = false;
  }
}
