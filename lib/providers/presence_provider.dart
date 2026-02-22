import 'dart:async';

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

/// Manages user presence (online/offline status) with heartbeat
class PresenceManager {
  final Ref _ref;
  Timer? _heartbeatTimer;
  bool _isActive = false;

  static const _heartbeatInterval = Duration(seconds: 30);

  PresenceManager(this._ref);

  /// Start presence tracking (call when app becomes active)
  Future<void> startPresence() async {
    if (_isActive) return;

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null) return;

    _isActive = true;
    debugPrint('Starting presence for user: $userId');

    try {
      // Set online immediately
      final presenceService = _ref.read(presenceServiceProvider);
      await presenceService.setOnline(userId);
      _ref.read(userOnlineStatusProvider.notifier).state = true;

      // Start heartbeat timer
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) async {
        final currentUserId = _ref.read(currentUserIdProvider);
        if (currentUserId != null && _isActive) {
          try {
            await presenceService.heartbeat(currentUserId);
            debugPrint('Heartbeat sent for user: $currentUserId');
          } catch (e) {
            debugPrint('Error sending heartbeat: $e');
          }
        }
      });
    } catch (e) {
      debugPrint('Error starting presence: $e');
      _isActive = false;
    }
  }

  /// Stop presence tracking (call when app becomes inactive)
  Future<void> stopPresence() async {
    if (!_isActive) return;

    _isActive = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

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

  /// Check if presence is currently active
  bool get isActive => _isActive;

  /// Dispose the manager
  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isActive = false;
  }
}
