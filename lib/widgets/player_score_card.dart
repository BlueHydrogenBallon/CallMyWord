import 'package:flutter/material.dart';

import '../models/player.dart';

/// Displays a player's score and status - compact version for small screens
class PlayerScoreCard extends StatelessWidget {
  final Player? player;
  final String label;
  final bool isCurrentTurn;
  final int targetScore;
  final MaterialColor accentColor;

  const PlayerScoreCard({
    super.key,
    required this.player,
    required this.label,
    this.isCurrentTurn = false,
    this.targetScore = 50,
    this.accentColor = Colors.green,
  });

  @override
  Widget build(BuildContext context) {
    final score = player?.score ?? 0;
    final progress = (score / targetScore).clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;

    final progressColor = accentColor.shade400;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrentTurn
            ? accentColor.shade50
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: isCurrentTurn
            ? Border.all(color: accentColor.shade400, width: 2)
            : null,
      ),
      child: Row(
        children: [
          // Turn indicator dot
          if (isCurrentTurn)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: accentColor.shade500,
                shape: BoxShape.circle,
              ),
            ),
          // Player name
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Circular progress with score inside
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    backgroundColor: Colors.grey.shade600,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$score',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        height: 1,
                      ),
                    ),
                    Text(
                      '/$targetScore',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[500],
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
