import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Music muted state provider
final musicMutedProvider = StateProvider<bool>((ref) => false);

/// Sound effects muted state provider
final soundEffectsMutedProvider = StateProvider<bool>((ref) => false);

/// Background music service provider - singleton instance
final backgroundMusicProvider = Provider<BackgroundMusicService>((ref) {
  final service = BackgroundMusicService(ref);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Sound effects service provider - singleton instance
final soundEffectsProvider = Provider<SoundEffectsService>((ref) {
  final service = SoundEffectsService(ref);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// Service for managing background music
class BackgroundMusicService {
  final Ref _ref;
  late final AudioPlayer _player;
  bool _isInitialized = false;
  bool _shouldBePlaying = false; // Track user intent, not actual player state

  // Use MP3 for web compatibility (WAV not supported on web browsers)
  static const String _assetPath = 'audio/background_music.mp3';

  BackgroundMusicService(this._ref) {
    _player = AudioPlayer();
    _player.onPlayerStateChanged.listen((state) {
      debugPrint('AudioPlayer state: $state');

      // If music should be playing but stopped unexpectedly (audio focus loss on Android),
      // try to restart it
      if (_shouldBePlaying && state == PlayerState.stopped) {
        final isMuted = _ref.read(musicMutedProvider);
        if (!isMuted) {
          debugPrint('Music stopped unexpectedly, restarting...');
          _restartMusic();
        }
      }
    });
  }

  /// Restart music after unexpected stop
  Future<void> _restartMusic() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      if (_shouldBePlaying && !_ref.read(musicMutedProvider)) {
        await _player.play(AssetSource(_assetPath));
        debugPrint('Music restarted');
      }
    } catch (e) {
      debugPrint('Error restarting music: $e');
    }
  }

  /// Initialize and start playing background music
  Future<void> startMusic() async {
    debugPrint('startMusic() called, isInitialized: $_isInitialized, shouldBePlaying: $_shouldBePlaying');

    try {
      final isMuted = _ref.read(musicMutedProvider);

      if (isMuted) {
        debugPrint('Music is muted, not starting');
        return;
      }

      _shouldBePlaying = true;

      if (!_isInitialized) {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(0.5);
        _isInitialized = true;
        debugPrint('AudioPlayer initialized');
      }

      // Check actual player state
      final currentState = _player.state;
      if (currentState == PlayerState.playing) {
        debugPrint('Music already playing');
        return;
      }

      debugPrint('Attempting to play: $_assetPath');
      await _player.play(AssetSource(_assetPath));
      debugPrint('Play command sent');

    } catch (e, stack) {
      debugPrint('Error starting background music: $e');
      debugPrint('Stack trace: $stack');
    }
  }

  /// Toggle music mute state
  Future<void> toggleMute() async {
    final isMuted = _ref.read(musicMutedProvider);
    _ref.read(musicMutedProvider.notifier).state = !isMuted;

    debugPrint('toggleMute() called, was muted: $isMuted, shouldBePlaying: $_shouldBePlaying');

    try {
      if (!isMuted) {
        // Muting - pause the music
        _shouldBePlaying = false;
        await _player.pause();
        debugPrint('Music paused');
      } else {
        // Unmuting - start/resume the music
        _shouldBePlaying = true;

        // Always try to play fresh to ensure it starts
        await _player.stop();
        await _player.play(AssetSource(_assetPath));
        debugPrint('Music resumed');
      }
    } catch (e) {
      debugPrint('Error toggling music: $e');
    }
  }

  /// Stop the music
  Future<void> stopMusic() async {
    _shouldBePlaying = false;
    await _player.stop();
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  /// Resume music if it should be playing (call when app resumes)
  Future<void> resumeIfNeeded() async {
    if (_shouldBePlaying && !_ref.read(musicMutedProvider)) {
      final currentState = _player.state;
      if (currentState != PlayerState.playing) {
        debugPrint('Resuming music on app resume');
        await _player.play(AssetSource(_assetPath));
      }
    }
  }

  /// Dispose the player
  void dispose() {
    _player.dispose();
  }
}

/// Sound effect types
enum SoundEffect {
  letterClick,
  yourTurn,
  challenged,
}

/// Service for managing sound effects
class SoundEffectsService {
  final Ref _ref;
  final AudioPlayer _player = AudioPlayer();
  final AudioPlayer _clockPlayer = AudioPlayer();
  bool _isInitialized = false;
  bool _isClockInitialized = false;

  // Sound effect file paths (MP3 for web compatibility)
  static const Map<SoundEffect, String> _soundPaths = {
    SoundEffect.letterClick: 'audio/sfx_letter_click.mp3',
    SoundEffect.yourTurn: 'audio/sfx_your_turn.mp3',
    SoundEffect.challenged: 'audio/sfx_challenged.mp3',
  };

  static const String _clockPath = 'audio/sfx_clock.mp3';

  SoundEffectsService(this._ref);

  /// Play a sound effect (plays once and stops)
  Future<void> play(SoundEffect effect) async {
    final isMuted = _ref.read(soundEffectsMutedProvider);
    if (isMuted) return;

    try {
      // Initialize player to play once (not loop)
      if (!_isInitialized) {
        await _player.setReleaseMode(ReleaseMode.stop);
        _isInitialized = true;
      }

      final path = _soundPaths[effect];
      if (path != null) {
        // Stop any currently playing sound before playing new one
        await _player.stop();
        await _player.play(AssetSource(path));
      }
    } catch (e) {
      debugPrint('Error playing sound effect: $e');
    }
  }

  /// Start the clock ticking sound (loops until stopped)
  Future<void> startClockSound() async {
    final isMuted = _ref.read(soundEffectsMutedProvider);
    if (isMuted) return;

    try {
      if (!_isClockInitialized) {
        await _clockPlayer.setReleaseMode(ReleaseMode.loop);
        _isClockInitialized = true;
      }

      await _clockPlayer.play(AssetSource(_clockPath));
      debugPrint('Clock sound started');
    } catch (e) {
      debugPrint('Error starting clock sound: $e');
    }
  }

  /// Stop the clock ticking sound
  Future<void> stopClockSound() async {
    try {
      await _clockPlayer.stop();
      debugPrint('Clock sound stopped');
    } catch (e) {
      debugPrint('Error stopping clock sound: $e');
    }
  }

  /// Toggle sound effects mute state
  void toggleMute() {
    final isMuted = _ref.read(soundEffectsMutedProvider);
    _ref.read(soundEffectsMutedProvider.notifier).state = !isMuted;

    // Stop clock sound if muting
    if (!isMuted) {
      _clockPlayer.stop();
    }

    debugPrint('Sound effects ${!isMuted ? "muted" : "unmuted"}');
  }

  /// Dispose the players
  void dispose() {
    _player.dispose();
    _clockPlayer.dispose();
  }
}
