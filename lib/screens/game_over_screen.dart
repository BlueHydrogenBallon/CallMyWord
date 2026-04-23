import 'dart:math';

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/game.dart';
import '../providers/auth_provider.dart';
import '../services/ad_service.dart';
import '../widgets/web_interstitial_overlay.dart';
import 'matchmaking_screen.dart';

/// Screen shown when a game ends
class GameOverScreen extends ConsumerStatefulWidget {
  final Game game;

  const GameOverScreen({super.key, required this.game});

  @override
  ConsumerState<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends ConsumerState<GameOverScreen> {
  late final ConfettiController _confettiController;
  late final bool _didWin;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(currentUserIdProvider);
    _didWin = userId != null && widget.game.didPlayerWin(userId);
    _confettiController = ConfettiController(duration: const Duration(seconds: 4));
    if (_didWin) {
      _confettiController.play();
    }
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    final didWin = userId != null && widget.game.didPlayerWin(userId);

    // Build ranked player list sorted by score descending
    final rankedPlayers = widget.game.playerIds.map((pid) {
      final player = widget.game.getPlayer(pid);
      return (
        playerId: pid,
        displayName: player?.displayName ?? 'Player',
        score: player?.score ?? 0,
        isMe: pid == userId,
        isWinner: pid == widget.game.winnerId,
      );
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Result icon
                    Icon(
                      didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                      size: 80,
                      color: didWin ? Colors.amber : Colors.grey,
                    ),

                    const SizedBox(height: 24),

                    // Result text
                    Text(
                      didWin ? S.victory : S.defeat,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: didWin ? Colors.amber.shade700 : Colors.grey.shade700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // End reason
                    if (widget.game.endReason != null)
                      Text(
                        _formatEndReason(widget.game.endReason!),
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),

                    const SizedBox(height: 48),

                    // Ranked player results
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < rankedPlayers.length; i++)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: i < rankedPlayers.length - 1 ? 8 : 0,
                              ),
                              child: Row(
                                children: [
                                  // Rank / trophy
                                  SizedBox(
                                    width: 32,
                                    child: rankedPlayers[i].isWinner
                                        ? Icon(Icons.emoji_events,
                                            color: Colors.amber.shade600, size: 24)
                                        : Text(
                                            '#${i + 1}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey[500],
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Player name
                                  Expanded(
                                    child: Text(
                                      rankedPlayers[i].isMe
                                          ? S.you
                                          : rankedPlayers[i].displayName,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: rankedPlayers[i].isMe
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: rankedPlayers[i].isWinner
                                            ? Colors.amber.shade700
                                            : null,
                                      ),
                                    ),
                                  ),
                                  // Score
                                  Text(
                                    '${rankedPlayers[i].score}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: rankedPlayers[i].isWinner
                                          ? Colors.amber.shade700
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Last word played
                    if (widget.game.currentWord.isNotEmpty) ...[
                      Text(
                        S.finalWordFragment,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.game.currentWord,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],

                    // Play again button
                    ElevatedButton.icon(
                      onPressed: () => _playAgain(context),
                      icon: const Icon(Icons.replay),
                      label: Text(S.playAgain),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Home button
                    TextButton(
                      onPressed: () => _goHome(context),
                      child: Text(S.backToHome),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Confetti from top-left
          Align(
            alignment: Alignment.topLeft,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: pi / 4,
              colors: const [
                Colors.amber,
                Colors.orange,
                Colors.yellow,
                Colors.white,
                Colors.deepOrange,
              ],
              numberOfParticles: 20,
              emissionFrequency: 0.05,
              gravity: 0.2,
            ),
          ),

          // Confetti from top-right
          Align(
            alignment: Alignment.topRight,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: 3 * pi / 4,
              colors: const [
                Colors.amber,
                Colors.orange,
                Colors.yellow,
                Colors.white,
                Colors.deepOrange,
              ],
              numberOfParticles: 20,
              emissionFrequency: 0.05,
              gravity: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  String _formatEndReason(String reason) {
    switch (reason) {
      case 'target_reached':
        return S.winnerReachedScore(widget.game.winnerName!, widget.game.settings.targetScore);
      case 'challenge_won':
        return S.winnerWonChallenge(widget.game.winnerName!);
      case 'challenge_lost':
        return S.challengeFailedWordValid;
      case 'challenge_timeout':
        return S.challengeTimedOut;
      case 'forfeit':
      case 'opponent_forfeited':
        return S.opponentForfeited;
      default:
        return reason;
    }
  }

  void _playAgain(BuildContext context) => _navigateWithAd(context, startNewGame: true);
  void _goHome(BuildContext context) => _navigateWithAd(context, startNewGame: false);

  void _navigateWithAd(BuildContext context, {required bool startNewGame}) {
    void navigate() {
      if (!mounted) return;
      // Pop back to home first
      Navigator.of(context).popUntil((route) => route.isFirst);
      // If "Play Again", push straight into matchmaking for a new game
      if (startNewGame) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MatchmakingScreen()),
        );
      }
    }

    if (kIsWeb) {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        pageBuilder: (ctx, _, __) =>
            WebInterstitialOverlay(onClose: () {
              Navigator.of(ctx).pop();
              navigate();
            }),
      );
    } else {
      ref.read(adServiceProvider).showInterstitialIfReady(onComplete: navigate);
    }
  }
}
