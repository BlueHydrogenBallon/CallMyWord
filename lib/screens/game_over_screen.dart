import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game.dart';
import '../providers/auth_provider.dart';

/// Screen shown when a game ends
class GameOverScreen extends ConsumerWidget {
  final Game game;

  const GameOverScreen({super.key, required this.game});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    final didWin = userId != null && game.didPlayerWin(userId);
    final myPlayer = userId != null ? game.getPlayer(userId) : null;
    final opponent = userId != null ? game.getOpponent(userId) : null;

    return Scaffold(
      body: SafeArea(
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
                  didWin ? 'Victory!' : 'Defeat',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: didWin ? Colors.amber.shade700 : Colors.grey.shade700,
                  ),
                ),

                const SizedBox(height: 8),

                // End reason
                if (game.endReason != null)
                  Text(
                    _formatEndReason(game.endReason!),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),

                const SizedBox(height: 48),

                // Score comparison
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // My score
                      _ScoreColumn(
                        label: 'You',
                        score: myPlayer?.score ?? 0,
                        isWinner: didWin,
                      ),

                      const SizedBox(width: 32),

                      // VS divider
                      Text(
                        'vs',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[400],
                        ),
                      ),

                      const SizedBox(width: 32),

                      // Opponent score
                      _ScoreColumn(
                        label: opponent?.displayName ?? 'Opponent',
                        score: opponent?.score ?? 0,
                        isWinner: !didWin,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // Last word played
                if (game.currentWord.isNotEmpty) ...[
                  Text(
                    'Final word fragment:',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    game.currentWord,
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
                  label: const Text('Play Again'),
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
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatEndReason(String reason) {
    switch (reason) {
      case 'target_reached':
        return '${game.winnerName} reached ${game.settings.targetScore} points!';
      case 'challenge_won':
        return '${game.winnerName} won the challenge!';
      case 'challenge_lost':
        return 'Challenge failed - word was valid!';
      case 'challenge_timeout':
        return 'Challenge timed out!';
      case 'forfeit':
        return 'Opponent forfeited';
      default:
        return reason;
    }
  }

  void _playAgain(BuildContext context) {
    // Pop back to home, then navigate to matchmaking
    Navigator.of(context).popUntil((route) => route.isFirst);
    // The home screen will handle starting a new game
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

class _ScoreColumn extends StatelessWidget {
  final String label;
  final int score;
  final bool isWinner;

  const _ScoreColumn({
    required this.label,
    required this.score,
    required this.isWinner,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWinner)
              Icon(
                Icons.star,
                size: 20,
                color: Colors.amber.shade600,
              ),
            Text(
              '$score',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: isWinner ? Colors.amber.shade700 : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
