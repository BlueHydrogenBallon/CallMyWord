import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/lobby.dart';
import '../providers/party_provider.dart';
import '../services/party_service.dart';
import 'game_screen.dart';

/// Waiting room screen for a multiplayer party lobby
class PartyWaitingScreen extends ConsumerStatefulWidget {
  final String lobbyId;
  final bool isHost;

  const PartyWaitingScreen({
    super.key,
    required this.lobbyId,
    required this.isHost,
  });

  @override
  ConsumerState<PartyWaitingScreen> createState() => _PartyWaitingScreenState();
}

class _PartyWaitingScreenState extends ConsumerState<PartyWaitingScreen> {
  bool _isStarting = false;
  bool _isLeaving = false;
  bool _navigatedToGame = false;

  @override
  Widget build(BuildContext context) {
    final lobbyAsync = ref.watch(partyLobbyProvider(widget.lobbyId));

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) {
          _onLeave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(S.partyLobby),
          automaticallyImplyLeading: false,
        ),
        body: lobbyAsync.when(
          data: (lobby) {
            // Navigate to game when started
            if (lobby.hasStarted && lobby.gameId != null && !_navigatedToGame) {
              _navigatedToGame = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => GameScreen(gameId: lobby.gameId!),
                  ),
                );
              });
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(S.gameStarting),
                  ],
                ),
              );
            }

            // Lobby was cancelled
            if (lobby.status == LobbyStatus.cancelled) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(S.partyCancelled)),
                  );
                }
              });
              return Center(child: Text(S.partyCancelledTitle));
            }

            return _buildLobbyContent(lobby);
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(S.errorMsg(error.toString())),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(S.goBack),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyContent(Lobby lobby) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Player count header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.people),
                  const SizedBox(width: 8),
                  Text(
                    S.playerCount(lobby.playerCount, lobby.maxPlayers),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Player slots
            Expanded(
              child: ListView.builder(
                itemCount: lobby.maxPlayers,
                itemBuilder: (context, index) {
                  if (index < lobby.playerIds.length) {
                    // Filled slot
                    final playerId = lobby.playerIds[index];
                    final playerName =
                        lobby.playerNames[playerId] ?? 'Player';
                    final isHost = playerId == lobby.hostId;

                    return _buildPlayerCard(
                      name: playerName,
                      status: _PlayerStatus.joined,
                      isHost: isHost,
                    );
                  } else {
                    // Empty slot - waiting
                    return _buildPlayerCard(
                      name: S.waitingForPlayer,
                      status: _PlayerStatus.waiting,
                      isHost: false,
                    );
                  }
                },
              ),
            ),

            const SizedBox(height: 16),

            // Action buttons
            if (widget.isHost) ...[
              // Host: Start Game button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      lobby.playerCount >= 2 && !_isStarting ? _onStart : null,
                  child: _isStarting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(lobby.playerCount >= 2
                          ? S.startGame(lobby.playerCount)
                          : S.waitingForPlayers),
                ),
              ),
            ] else ...[
              // Guest: waiting message
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Text(S.waitingForHostToStart),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Leave button
            TextButton(
              onPressed: _isLeaving ? null : _onLeave,
              child: Text(
                widget.isHost ? S.cancelParty : S.leaveParty,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard({
    required String name,
    required _PlayerStatus status,
    required bool isHost,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: status == _PlayerStatus.joined
              ? colorScheme.primaryContainer
              : Colors.grey.shade200,
          child: status == _PlayerStatus.joined
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : const Icon(Icons.hourglass_empty, color: Colors.grey),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: status == _PlayerStatus.waiting ? Colors.grey : null,
          ),
        ),
        subtitle: status == _PlayerStatus.waiting
            ? null
            : Text(
                isHost ? S.host : S.joined,
                style: TextStyle(
                  color: isHost ? colorScheme.primary : Colors.green,
                  fontSize: 12,
                ),
              ),
        trailing: status == _PlayerStatus.joined
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    );
  }

  Future<void> _onStart() async {
    if (_isStarting) return;

    setState(() => _isStarting = true);

    try {
      final partyService = ref.read(partyServiceProvider);
      await partyService.startPartyGame(widget.lobbyId);
      // Navigation will happen via the lobby watcher when status changes to 'started'
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.errorMsg(e.toString()))),
        );
        setState(() => _isStarting = false);
      }
    }
  }

  Future<void> _onLeave() async {
    if (_isLeaving) return;

    setState(() => _isLeaving = true);

    try {
      final partyService = ref.read(partyServiceProvider);
      await partyService.leavePartyLobby(widget.lobbyId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.errorMsg(e.toString()))),
        );
        setState(() => _isLeaving = false);
      }
    }
  }
}

enum _PlayerStatus {
  joined,
  waiting,
}
