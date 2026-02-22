import 'package:flutter/material.dart';

/// Dialog to confirm initiating a challenge
class ChallengeDialog extends StatelessWidget {
  final String opponentName;
  final String currentWord;

  const ChallengeDialog({
    super.key,
    required this.opponentName,
    required this.currentWord,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.gavel, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          const Text('Challenge?'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You think "$currentWord" isn\'t leading to a real word?',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'If you challenge:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                _buildBullet(
                  '$opponentName must prove they have a valid word',
                  Colors.grey[600]!,
                ),
                _buildBullet(
                  'If they can\'t, you win the Bluff Bonus!',
                  Colors.green.shade700,
                ),
                _buildBullet(
                  'If they can, they win the Word Pot + Bonus',
                  Colors.red.shade700,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.gavel, size: 18),
          label: const Text('Challenge!'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildBullet(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: color)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
