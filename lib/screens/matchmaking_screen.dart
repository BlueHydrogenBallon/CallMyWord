import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lobby.dart';
import '../providers/auth_provider.dart';
import '../services/matchmaking_service.dart';
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

      // Get player name from auth or use default
      final playerName = user?.displayName ?? 'Player';

      // Join or create lobby
      final result = await matchmakingService.joinOrCreateLobby(playerName);
      _lobbyId = result.lobbyId;

      // If game is already ready (matched immediately), go to game
      if (result.isGameReady && result.gameId != null) {
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
            _error = 'Lobby was cancelled';
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
            _error = 'Matchmaking was cancelled';
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
        title: const Text('Finding Game'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
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
                    'Something went wrong',
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
                    child: const Text('Try Again'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Go Back'),
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
                    'Looking for opponent...',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This usually takes a few seconds',
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
                        : const Text('Cancel'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
