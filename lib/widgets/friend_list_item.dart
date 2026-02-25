import 'package:flutter/material.dart';

import '../config/app_strings.dart';
import '../models/friend.dart';

/// Widget displaying a single friend in the friends list
class FriendListItem extends StatelessWidget {
  final Friend friend;
  final VoidCallback? onChallenge;

  const FriendListItem({
    super.key,
    required this.friend,
    this.onChallenge,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              friend.displayName.isNotEmpty
                  ? friend.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Online indicator (green/grey dot)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: friend.isOnline ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        friend.displayName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        friend.isOnline ? S.online : _formatLastActive(friend.lastActiveAt),
        style: TextStyle(
          color: friend.isOnline ? Colors.green : Colors.grey,
          fontSize: 12,
        ),
      ),
      trailing: friend.isOnline && onChallenge != null
          ? ElevatedButton(
              onPressed: onChallenge,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(S.challenge),
            )
          : null,
    );
  }

  String _formatLastActive(DateTime? lastActive) {
    if (lastActive == null) return S.offline;

    final now = DateTime.now();
    final difference = now.difference(lastActive);

    if (difference.inMinutes < 1) {
      return S.justNow;
    } else if (difference.inMinutes < 60) {
      return S.minutesAgo(difference.inMinutes);
    } else if (difference.inHours < 24) {
      return S.hoursAgo(difference.inHours);
    } else if (difference.inDays < 7) {
      return S.daysAgo(difference.inDays);
    } else {
      return S.overAWeekAgo;
    }
  }
}
