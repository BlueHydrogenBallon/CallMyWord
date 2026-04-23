import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/lobby.dart';
import '../providers/auth_provider.dart';
import '../services/game_service.dart';
import '../services/matchmaking_service.dart';
import '../services/user_service.dart';
import 'game_screen.dart';

/// Matchmaking screen - finds or creates a game lobby
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> {
  String? _lobbyId;
  String? _error;
  bool _isCancelling = false;
  StreamSubscription<Lobby?>? _lobbySubscription;

  @override
  void initState() {
    super.initState();
    _startMatchmaking();
  }

  @override
  void dispose() {
    _lobbySubscription?.cancel();
    super.dispose();
  }

  Future<void> _startMatchmaking() async {
    setState(() {
      _error = null;
    });

    try {
      final user = ref.read(currentUserProvider);
      final matchmakingService = ref.read(matchmakingServiceProvider);

      // Get player name from Firestore profile (has username set by user),
      // falling back to Firebase Auth displayName
      final profile = await ref.read(userServiceProvider).getUserProfile(user!.uid);
      final playerName = profile?.displayName ?? user.displayName ?? 'Player';

      // Join or create lobby
      final result = await matchmakingService.joinOrCreateLobby(playerName);
      _lobbyId = result.lobbyId;

      // If game is already ready (matched immediately), verify it's still
      // active before navigating.  An old lobby whose game just ended can
      // be returned by the backend in a narrow race window.
      if (result.isGameReady && result.gameId != null) {
        if (result.alreadyJoined) {
          final gameDoc = await ref
              .read(gameServiceProvider)
              .getGame(result.gameId!);
          if (gameDoc == null || gameDoc.isGameOver) {
            // Stale game — restart matchmaking for a fresh lobby.
            _startMatchmaking();
            return;
          }
        }
        _navigateToGame(result.gameId!);
        return;
      }

      // Otherwise, watch the lobby for changes
      _watchLobby(result.lobbyId);
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    }
  }

  void _watchLobby(String lobbyId) {
    final matchmakingService = ref.read(matchmakingServiceProvider);
    _lobbySubscription = matchmakingService.watchLobby(lobbyId).listen(
      (lobby) {
        if (lobby == null) {
          setState(() {
            _error = S.lobbyCancelled;
          });
          return;
        }

        // Game started - navigate to game screen
        if (lobby.hasStarted && lobby.gameId != null) {
          _navigateToGame(lobby.gameId!);
        }

        // Lobby was cancelled
        if (lobby.status == LobbyStatus.cancelled) {
          setState(() {
            _error = S.matchmakingCancelled;
          });
        }
      },
      onError: (error) {
        setState(() {
          _error = error.toString();
        });
      },
    );
  }

  void _navigateToGame(String gameId) {
    _lobbySubscription?.cancel();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => GameScreen(gameId: gameId),
      ),
    );
  }

  Future<void> _cancelMatchmaking() async {
    if (_lobbyId == null || _isCancelling) return;

    setState(() {
      _isCancelling = true;
    });

    try {
      final matchmakingService = ref.read(matchmakingServiceProvider);
      await matchmakingService.leaveLobby(_lobbyId!);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to cancel: $e';
        _isCancelling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.findingGame),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_error != null) ...[
                  // Error state
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    S.somethingWentWrong,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _startMatchmaking,
                    child: Text(S.tryAgain),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(S.goBack),
                  ),
                ] else ...[
                  // Searching state
                  const SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(strokeWidth: 4),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    S.lookingForOpponent,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    S.matchmakingSubtitle,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 48),
                  OutlinedButton(
                    onPressed: _isCancelling ? null : _cancelMatchmaking,
                    child: _isCancelling
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(S.cancel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),          // SafeArea
          ),      // Expanded
          // Banner ad removed — AdWidget PlatformView causes touch interception on Android.
        ],        // Column children
      ),          // body Column
    );
  }
}
