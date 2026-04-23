import 'package:flutter/material.dart';

import '../config/avatars.dart';

/// Dialog that displays a grid of predefined avatars for the user to pick from.
class AvatarPickerDialog extends StatelessWidget {
  final String? currentAvatarKey;
  final ValueChanged<String> onSelected;

  const AvatarPickerDialog({
    super.key,
    this.currentAvatarKey,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose Avatar'),
      content: SizedBox(
        width: double.maxFinite,
        child: GridView.builder(
          shrinkWrap: true,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemCount: kAvatarOptions.length,
          itemBuilder: (context, index) {
            final avatar = kAvatarOptions[index];
            final isSelected = avatar.key == (currentAvatarKey ?? kDefaultAvatarKey);

            return GestureDetector(
              onTap: () {
                onSelected(avatar.key);
                Navigator.of(context).pop();
              },
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        )
                      : null,
                ),
                child: CircleAvatar(
                  backgroundColor: avatar.color,
                  child: Icon(
                    avatar.icon,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
