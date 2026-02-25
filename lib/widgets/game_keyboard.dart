import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/audio_provider.dart';

/// On-screen keyboard for letter input - compact version for small screens
class GameKeyboard extends ConsumerWidget {
  final void Function(String letter) onLetterPressed;
  final bool enabled;
  final String language;
  final VoidCallback? onBackspace;

  const GameKeyboard({
    super.key,
    required this.onLetterPressed,
    this.enabled = true,
    this.language = 'english',
    this.onBackspace,
  });

  static const _englishRows = [
    ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
    ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
    ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
  ];

  static const _greekRows = [
    ['Ε', 'Ρ', 'Τ', 'Υ', 'Θ', 'Ι', 'Ο', 'Π'],
    ['Α', 'Σ', 'Δ', 'Φ', 'Γ', 'Η', 'Ξ', 'Κ', 'Λ'],
    ['Ζ', 'Χ', 'Ψ', 'Ω', 'Β', 'Ν', 'Μ'],
  ];

  /// English Scrabble-style letter point values
  static const _englishPoints = {
    'A': 1, 'B': 3, 'C': 3, 'D': 2, 'E': 1,
    'F': 4, 'G': 2, 'H': 4, 'I': 1, 'J': 8,
    'K': 5, 'L': 1, 'M': 3, 'N': 1, 'O': 1,
    'P': 3, 'Q': 10, 'R': 1, 'S': 1, 'T': 1,
    'U': 1, 'V': 4, 'W': 4, 'X': 8, 'Y': 4,
    'Z': 10,
  };

  /// Greek Scrabble-style letter point values
  static const _greekPoints = {
    'Α': 1, 'Β': 8, 'Γ': 4, 'Δ': 4, 'Ε': 1,
    'Ζ': 10, 'Η': 1, 'Θ': 10, 'Ι': 1, 'Κ': 2,
    'Λ': 3, 'Μ': 3, 'Ν': 1, 'Ξ': 10, 'Ο': 1,
    'Π': 2, 'Ρ': 2, 'Σ': 1, 'Τ': 1, 'Υ': 2,
    'Φ': 8, 'Χ': 8, 'Ψ': 10, 'Ω': 3,
  };

  List<List<String>> get _rows =>
      language == 'greek' ? _greekRows : _englishRows;

  Map<String, int> get _letterPoints =>
      language == 'greek' ? _greekPoints : _englishPoints;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = _rows;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < rows.length; i++)
            _buildRow(context, ref, rows[i], isLastRow: i == rows.length - 1),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, WidgetRef ref, List<String> letters,
      {bool isLastRow = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ...letters.map((letter) => _buildKey(context, ref, letter)),
          if (isLastRow && onBackspace != null)
            _buildBackspaceKey(context, ref),
        ],
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
                  ref
                      .read(soundEffectsProvider)
                      .play(SoundEffect.letterClick);
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

  Widget _buildBackspaceKey(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: enabled
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: enabled ? onBackspace : null,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 42,
            height: 38,
            alignment: Alignment.center,
            child: Icon(
              Icons.backspace_outlined,
              size: 18,
              color: enabled
                  ? colorScheme.onSecondaryContainer
                  : colorScheme.onSurface.withAlpha(102),
            ),
          ),
        ),
      ),
    );
  }
}
