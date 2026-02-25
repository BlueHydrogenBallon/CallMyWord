import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/friend.dart';
import '../providers/friend_provider.dart';
import '../services/party_service.dart';
import 'party_waiting_screen.dart';

/// Screen for selecting friends to invite to a multiplayer party
class PartySetupScreen extends ConsumerStatefulWidget {
  const PartySetupScreen({super.key});

  @override
  ConsumerState<PartySetupScreen> createState() => _PartySetupScreenState();
}

class _PartySetupScreenState extends ConsumerState<PartySetupScreen> {
  final Set<String> _selectedFriendIds = {};
  bool _isCreating = false;
  static const int _maxInvites = 3;

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.createParty),
      ),
      body: Column(
        children: [
          // Instructions
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              S.selectFriendsToInvite(_maxInvites),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),

          // Friends list
          Expanded(
            child: friendsAsync.when(
              data: (friends) {
                // Sort: online first, then alphabetically
                final sortedFriends = List<Friend>.from(friends)
                  ..sort((a, b) {
                    if (a.isOnline && !b.isOnline) return -1;
                    if (!a.isOnline && b.isOnline) return 1;
                    return a.displayName.compareTo(b.displayName);
                  });

                if (sortedFriends.isEmpty) {
                  return _buildEmptyState();
                }

                final onlineFriends =
                    sortedFriends.where((f) => f.isOnline).toList();
                final offlineFriends =
                    sortedFriends.where((f) => !f.isOnline).toList();

                return ListView(
                  children: [
                    if (onlineFriends.isNotEmpty) ...[
                      _buildSectionHeader(S.onlineCount(onlineFriends.length)),
                      ...onlineFriends
                          .map((friend) => _buildFriendTile(friend, true)),
                    ],
                    if (offlineFriends.isNotEmpty) ...[
                      _buildSectionHeader(S.offlineCount(offlineFriends.length)),
                      ...offlineFriends
                          .map((friend) => _buildFriendTile(friend, false)),
                    ],
                  ],
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(S.errorMsg(error.toString())),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(friendsProvider),
                      child: Text(S.retry),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom bar with selection count and create button
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildFriendTile(Friend friend, bool isOnline) {
    final isSelected = _selectedFriendIds.contains(friend.odId);
    final canSelect =
        isOnline && (_selectedFriendIds.length < _maxInvites || isSelected);

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor:
                Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              friend.displayName.isNotEmpty
                  ? friend.displayName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
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
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isOnline ? null : Colors.grey,
        ),
      ),
      subtitle: Text(
        isOnline ? S.online : S.offline,
        style: TextStyle(
          color: isOnline ? Colors.green : Colors.grey,
          fontSize: 12,
        ),
      ),
      trailing: isOnline
          ? Checkbox(
              value: isSelected,
              onChanged: canSelect
                  ? (value) {
                      setState(() {
                        if (value == true) {
                          _selectedFriendIds.add(friend.odId);
                        } else {
                          _selectedFriendIds.remove(friend.odId);
                        }
                      });
                    }
                  : null,
            )
          : null,
      onTap: isOnline && canSelect
          ? () {
              setState(() {
                if (isSelected) {
                  _selectedFriendIds.remove(friend.odId);
                } else {
                  _selectedFriendIds.add(friend.odId);
                }
              });
            }
          : null,
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(26),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Text(
              S.selectedCount(_selectedFriendIds.length, _maxInvites),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _selectedFriendIds.isNotEmpty && !_isCreating
                  ? _createParty
                  : null,
              child: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(S.createParty),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 80, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              S.noFriendsYet,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              S.noFriendsAddFirst,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createParty() async {
    if (_isCreating) return;

    setState(() => _isCreating = true);

    try {
      final partyService = ref.read(partyServiceProvider);
      final result = await partyService
          .createPartyLobby(_selectedFriendIds.toList());

      if (mounted) {
        // Replace current screen with waiting screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => PartyWaitingScreen(
              lobbyId: result.lobbyId,
              isHost: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.errorMsg(e.toString()))),
        );
        setState(() => _isCreating = false);
      }
    }
  }
}
