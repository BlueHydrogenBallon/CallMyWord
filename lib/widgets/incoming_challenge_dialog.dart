import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/friend_challenge.dart';
import '../services/friend_challenge_service.dart';
import '../services/party_service.dart';
import '../screens/game_screen.dart';
import '../screens/party_waiting_screen.dart';

/// Dialog shown when receiving a friend challenge
class IncomingChallengeDialog extends ConsumerStatefulWidget {
  final FriendChallenge challenge;

  const IncomingChallengeDialog({
    super.key,
    required this.challenge,
  });

  @override
  ConsumerState<IncomingChallengeDialog> createState() =>
      _IncomingChallengeDialogState();
}

class _IncomingChallengeDialogState
    extends ConsumerState<IncomingChallengeDialog> {
  Timer? _countdownTimer;
  late int _remainingSeconds;
  bool _isResponding = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.challenge.remainingSeconds;
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
        // Auto-dismiss when expired
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final isParty = widget.challenge.isParty;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            isParty ? Icons.groups : Icons.sports_esports,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(isParty ? S.partyInvite : S.gameChallenge),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Challenger info
          CircleAvatar(
            radius: 40,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              widget.challenge.challengerName.isNotEmpty
                  ? widget.challenge.challengerName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.challenge.challengerName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(isParty ? S.invitedToParty : S.wantsToPlay),

          const SizedBox(height: 24),

          // Countdown timer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: _remainingSeconds <= 10
                  ? Colors.orange.shade100
                  : colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer,
                  color: _remainingSeconds <= 10 ? Colors.orange : null,
                ),
                const SizedBox(width: 8),
                Text(
                  '${_remainingSeconds}s',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _remainingSeconds <= 10 ? Colors.orange : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: _isResponding ? null : _declineChallenge,
          child: Text(S.decline),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: _isResponding ? null : _acceptChallenge,
          child: _isResponding
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(S.accept),
        ),
      ],
    );
  }

  Future<void> _acceptChallenge() async {
    if (_isResponding) return;

    setState(() => _isResponding = true);

    try {
      if (widget.challenge.isParty) {
        // Party invite — join the lobby and go to waiting room
        final partyService = ref.read(partyServiceProvider);
        final lobbyId = widget.challenge.lobbyId;
        if (lobbyId == null) throw Exception('No lobby associated with invite');

        await partyService.joinPartyLobby(lobbyId, widget.challenge.id);

        if (mounted) {
          Navigator.of(context).pop(); // Close dialog
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PartyWaitingScreen(
                lobbyId: lobbyId,
                isHost: false,
              ),
            ),
          );
        }
      } else {
        // 1v1 challenge — accept and go directly to game
        final challengeService = ref.read(friendChallengeServiceProvider);
        final result =
            await challengeService.acceptChallenge(widget.challenge.id);

        if (mounted) {
          Navigator.of(context).pop(); // Close dialog
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => GameScreen(gameId: result.gameId),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResponding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.errorMsg(e.toString()))),
        );
      }
    }
  }

  Future<void> _declineChallenge() async {
    if (_isResponding) return;

    setState(() => _isResponding = true);

    try {
      final challengeService = ref.read(friendChallengeServiceProvider);
      await challengeService.declineChallenge(widget.challenge.id);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isResponding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.errorMsg(e.toString()))),
        );
      }
    }
  }
}
