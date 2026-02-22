import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Dialog for initiating a "Call the Word" action
/// Player enters the complete word they were building toward
class CallWordDialog extends StatefulWidget {
  final String currentFragment;
  final void Function(String word) onSubmit;

  const CallWordDialog({
    super.key,
    required this.currentFragment,
    required this.onSubmit,
  });

  @override
  State<CallWordDialog> createState() => _CallWordDialogState();
}

class _CallWordDialogState extends State<CallWordDialog> {
  late TextEditingController _controller;
  String? _errorText;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with current fragment
    _controller = TextEditingController(text: widget.currentFragment);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final word = _controller.text.trim().toUpperCase();

    // Validate: must start with current fragment
    if (!word.startsWith(widget.currentFragment)) {
      setState(() {
        _errorText = 'Word must start with "${widget.currentFragment}"';
      });
      return;
    }

    // Validate: must be longer than fragment (at least complete a word)
    if (word.length <= widget.currentFragment.length) {
      setState(() {
        _errorText = 'Enter the complete word you were building';
      });
      return;
    }

    // Validate: minimum 4 characters
    if (word.length < 4) {
      setState(() {
        _errorText = 'Word must be at least 4 letters';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });

    // onSubmit callback handles Navigator.pop() with the word
    widget.onSubmit(word);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Call Your Word'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current fragment: ${widget.currentFragment}',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Enter the complete word you were building:',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
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
              hintText: 'e.g., HORSE',
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Text(
            'Your opponent can:\n'
            '• Continue with a longer word\n'
            '• Challenge if they think it\'s invalid\n'
            '• Accept and let you win the pot',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Call Word'),
        ),
      ],
    );
  }
}
