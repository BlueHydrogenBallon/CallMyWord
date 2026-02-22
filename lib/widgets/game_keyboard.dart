import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_provider.dart';

/// On-screen keyboard for letter input - compact version for small screens
class GameKeyboard extends ConsumerWidget {
  final void Function(String letter) onLetterPressed;
  final bool enabled;

  const GameKeyboard({
    super.key,
    required this.onLetterPressed,
    this.enabled = true,
  });

  static const _rows = [
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  /// Scrabble-style letter point values
  static const _letterPoints = {
    'A': 1, 'B': 3, 'C': 3, 'D': 2, 'E': 1,
    'F': 4, 'G': 2, 'H': 4, 'I': 1, 'J': 8,
    'K': 5, 'L': 1, 'M': 3, 'N': 1, 'O': 1,
    'P': 3, 'Q': 10, 'R': 1, 'S': 1, 'T': 1,
    'U': 1, 'V': 4, 'W': 4, 'X': 8, 'Y': 4,
    'Z': 10,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _rows.map((row) => _buildRow(context, ref, row)).toList(),
      ),
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, List<String> letters) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: letters.map((letter) => _buildKey(context, ref, letter)).toList(),
      ),
    );
  }

  Widget _buildKey(BuildContext context, WidgetRef ref, String letter) {
    final colorScheme = Theme.of(context).colorScheme;
    final points = _letterPoints[letter] ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: enabled
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: enabled
              ? () {
                  // Play letter click sound
                  ref.read(soundEffectsProvider).play(SoundEffect.letterClick);
                  onLetterPressed(letter);
                }
              : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 28,
            height: 38,
            padding: const EdgeInsets.all(1),
            child: Stack(
              children: [
                // Letter in center
                Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: enabled
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface.withAlpha(102),
                    ),
                  ),
                ),
                // Point value in bottom-right corner (Scrabble style)
                Positioned(
                  right: 1,
                  bottom: 0,
                  child: Text(
                    '$points',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? colorScheme.onPrimaryContainer.withAlpha(179)
                          : colorScheme.onSurface.withAlpha(77),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
