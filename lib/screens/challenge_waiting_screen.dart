import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/friend_challenge.dart';
import '../providers/friend_challenge_provider.dart';
import '../services/friend_challenge_service.dart';
import 'game_screen.dart';

/// Screen shown while waiting for a friend to accept a challenge
class ChallengeWaitingScreen extends ConsumerStatefulWidget {
  final String challengeId;
  final String friendName;

  const ChallengeWaitingScreen({
    super.key,
    required this.challengeId,
    required this.friendName,
  });

  @override
  ConsumerState<ChallengeWaitingScreen> createState() =>
      _ChallengeWaitingScreenState();
}

class _ChallengeWaitingScreenState
    extends ConsumerState<ChallengeWaitingScreen> {
  Timer? _countdownTimer;
  int _remainingSeconds = 60;
  bool _isCancelling = false;
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final challengeAsync = ref.watch(challengeProvider(widget.challengeId));

    return PopScope(
      canPop: false,
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) {
        if (!didPop) {
          _showCancelConfirmation();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: challengeAsync.when(
            data: (challenge) {
              if (challenge == null) {
                return _buildExpiredState();
              }

              // Handle challenge status changes
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleChallengeStatus(challenge);
              });

              return _buildWaitingState(challenge);
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
      ),
    );
  }

  Widget _buildWaitingState(FriendChallenge challenge) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated waiting indicator
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: _remainingSeconds / 60,
                    strokeWidth: 8,
                    backgroundColor: Colors.grey.shade300,
                    color: _remainingSeconds <= 10
                        ? Colors.orange
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                Text(
                  '$_remainingSeconds',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          Text(
            S.waitingForLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            widget.friendName,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            S.toAcceptChallenge,
            style: Theme.of(context).textTheme.titleMedium,
          ),

          const SizedBox(height: 48),

          // Cancel button
          OutlinedButton(
            onPressed: _isCancelling ? null : _cancelChallenge,
            child: _isCancelling
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(S.cancelChallenge),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.timer_off,
            size: 80,
            color: Colors.orange,
          ),
          const SizedBox(height: 24),
          Text(
            S.challengeExpired,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            S.didNotRespond(widget.friendName),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.goBack),
          ),
        ],
      ),
    );
  }

  void _handleChallengeStatus(FriendChallenge challenge) {
    switch (challenge.status) {
      case ChallengeStatus.accepted:
        // Navigate to game
        if (challenge.gameId != null && !_dialogShown) {
          _dialogShown = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => GameScreen(gameId: challenge.gameId!),
            ),
          );
        }
        break;

      case ChallengeStatus.declined:
        if (!_dialogShown) {
          _dialogShown = true;
          _showDeclinedDialog();
        }
        break;

      case ChallengeStatus.expired:
      case ChallengeStatus.cancelled:
        // UI will update via the state
        break;

      case ChallengeStatus.pending:
        // Still waiting
        break;
    }
  }

  void _showDeclinedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(S.challengeDeclined),
        content: Text(S.declinedYourChallenge(widget.friendName)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back
            },
            child: Text(S.ok),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.cancelChallengeQuestion),
        content: Text(S.cancelChallengeConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.no),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _cancelChallenge();
            },
            child: Text(S.yesCancel),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelChallenge() async {
    if (_isCancelling) return;

    setState(() => _isCancelling = true);

    try {
      final challengeService = ref.read(friendChallengeServiceProvider);
      await challengeService.cancelChallenge(widget.challengeId);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.errorMsg(e.toString()))),
        );
      }
    }
  }
}
