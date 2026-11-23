import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game.dart';

/// Response type for word call
enum WordCallResponseType {
  continueWord,
  challenge,
  accept;

  String toFirestore() {
    switch (this) {
      case WordCallResponseType.continueWord:
        return 'continue';
      case WordCallResponseType.challenge:
        return 'challenge';
      case WordCallResponseType.accept:
        return 'accept';
    }
  }
}

/// Dialog for responding to an opponent's word call
class CallWordResponseDialog extends StatefulWidget {
  final PendingWordCall wordCall;
  final void Function(WordCallResponseType type, String? continuationWord) onRespond;

  const CallWordResponseDialog({
    super.key,
    required this.wordCall,
    required this.onRespond,
  });

  @override
  State<CallWordResponseDialog> createState() => _CallWordResponseDialogState();
}

class _CallWordResponseDialogState extends State<CallWordResponseDialog> {
  Timer? _timer;
  int _secondsRemaining = 30;
  bool _showContinueInput = false;
  final TextEditingController _continueController = TextEditingController();
  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.wordCall.secondsRemaining;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _continueController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsRemaining = widget.wordCall.secondsRemaining;
        if (_secondsRemaining <= 0) {
          timer.cancel();
        }
      });
    });
  }

  void _handleContinue() {
    setState(() {
      _showContinueInput = true;
      // Pre-fill with the original fragment, not the called word
      _continueController.text = widget.wordCall.wordFragment;
    });
  }

  void _submitContinuation() {
    final word = _continueController.text.trim().toUpperCase();
    final fragment = widget.wordCall.wordFragment;

    // Validate: must start with the original fragment
    if (!word.startsWith(fragment)) {
      setState(() {
        _errorText = 'Word must start with "$fragment"';
      });
      return;
    }

    // Validate: must be longer than the called word (to beat it)
    if (word.length <= widget.wordCall.calledWord.length) {
      setState(() {
        _errorText = 'Word must be longer than "${widget.wordCall.calledWord}"';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    // onRespond callback handles Navigator.pop() with the result
    widget.onRespond(WordCallResponseType.continueWord, word);
  }

  void _handleChallenge() {
    setState(() => _isSubmitting = true);
    // onRespond callback handles Navigator.pop() with the result
    widget.onRespond(WordCallResponseType.challenge, null);
  }

  void _handleAccept() {
    setState(() => _isSubmitting = true);
    // onRespond callback handles Navigator.pop() with the result
    widget.onRespond(WordCallResponseType.accept, null);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false, // Prevent dismissing with back button
      child: AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Word Called!'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _secondsRemaining <= 10
                    ? colorScheme.error
                    : colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${_secondsRemaining}s',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _secondsRemaining <= 10
                      ? colorScheme.onError
                      : colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        content: _showContinueInput
            ? _buildContinueInput(colorScheme)
            : _buildMainContent(colorScheme),
        actions: _showContinueInput
            ? [
                TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() => _showContinueInput = false),
                  child: const Text('Back'),
                ),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submitContinuation,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Submit'),
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildMainContent(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyLarge,
            children: [
              TextSpan(
                text: widget.wordCall.callerName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const TextSpan(text: ' called: '),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.wordCall.calledWord,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: colorScheme.onPrimaryContainer,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Fragment: ${widget.wordCall.wordFragment}',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'How do you respond?',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        _buildResponseButton(
          icon: Icons.add_circle_outline,
          label: 'Continue',
          description: 'Type a longer valid word to win',
          color: colorScheme.primary,
          onPressed: _isSubmitting ? null : _handleContinue,
        ),
        const SizedBox(height: 8),
        _buildResponseButton(
          icon: Icons.gavel,
          label: 'Challenge',
          description: 'Dispute - you think it\'s not a real word',
          color: colorScheme.error,
          onPressed: _isSubmitting ? null : _handleChallenge,
        ),
        const SizedBox(height: 8),
        _buildResponseButton(
          icon: Icons.check_circle_outline,
          label: 'Accept',
          description: 'Concede - let them win the pot',
          color: colorScheme.tertiary,
          onPressed: _isSubmitting ? null : _handleAccept,
        ),
      ],
    );
  }

  Widget _buildContinueInput(ColorScheme colorScheme) {
    final fragment = widget.wordCall.wordFragment;
    final calledWord = widget.wordCall.calledWord;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fragment: $fragment',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          'They called: $calledWord',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Enter a longer valid word starting from the fragment:',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _continueController,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              return newValue.copyWith(
                text: newValue.text.toUpperCase(),
              );
            }),
          ],
          decoration: InputDecoration(
            hintText: 'e.g., ${fragment}FYING',
            errorText: _errorText,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submitContinuation(),
        ),
        const SizedBox(height: 8),
        Text(
          'Must be longer than "$calledWord" to win!',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildResponseButton({
    required IconData icon,
    required String label,
    required String description,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: BorderSide(color: color.withAlpha(128)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
