import 'dart:async';

import 'package:flutter/material.dart';

/// Dialog for responding to a challenge with a claimed word
class ChallengeResponseDialog extends StatefulWidget {
  final String wordFragment;
  final int secondsRemaining;

  const ChallengeResponseDialog({
    super.key,
    required this.wordFragment,
    required this.secondsRemaining,
  });

  @override
  State<ChallengeResponseDialog> createState() =>
      _ChallengeResponseDialogState();
}

class _ChallengeResponseDialogState extends State<ChallengeResponseDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _timer;
  int _secondsLeft = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.secondsRemaining;
    _controller.text = widget.wordFragment;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );

    // Start countdown
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _secondsLeft--;
        if (_secondsLeft <= 0) {
          _timer?.cancel();
          Navigator.of(context).pop(null); // Time's up
        }
      });
    });

    // Auto-focus the text field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final word = _controller.text.trim().toUpperCase();

    if (word.isEmpty) {
      setState(() {
        _error = 'Please enter a word';
      });
      return;
    }

    if (!word.contains(widget.wordFragment.toUpperCase())) {
      setState(() {
        _error = 'Word must contain "${widget.wordFragment}"';
      });
      return;
    }

    if (word.length < 4) {
      setState(() {
        _error = 'Word must be at least 4 letters';
      });
      return;
    }

    Navigator.of(context).pop(word);
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _secondsLeft <= 10;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Prove Your Word')),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isUrgent ? Colors.red.shade100 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_secondsLeft}s',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isUrgent ? Colors.red.shade700 : Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter a valid word containing "${widget.wordFragment}":',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // Word input
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            decoration: InputDecoration(
              hintText: 'Enter your word',
              errorText: _error,
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.spellcheck),
            ),
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) {
                setState(() {
                  _error = null;
                });
              }
            },
          ),

          const SizedBox(height: 12),

          // Hint
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The word must be in the dictionary and at least 4 letters.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        ElevatedButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Submit Word'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
