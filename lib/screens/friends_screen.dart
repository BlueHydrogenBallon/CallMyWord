import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/friend.dart';
import '../providers/friend_provider.dart';
import '../services/friend_service.dart';
import '../services/friend_challenge_service.dart';
import '../widgets/friend_list_item.dart';
import '../widgets/invite_friend_dialog.dart';
import 'challenge_waiting_screen.dart';

/// Screen for managing friends and challenging them to games
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsProvider);
    final pendingRequestsAsync = ref.watch(pendingFriendRequestsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'Invite Friend',
            onPressed: _showInviteDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(friendsProvider);
          ref.invalidate(pendingFriendRequestsProvider);
        },
        child: CustomScrollView(
          slivers: [
            // Pending requests section
            pendingRequestsAsync.when(
              data: (pendingRequests) {
                if (pendingRequests.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: _buildPendingRequestsSection(pendingRequests),
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // Friends list
            friendsAsync.when(
              data: (friends) {
                if (friends.isEmpty) {
                  return SliverFillRemaining(
                    child: _buildEmptyState(),
                  );
                }

                // Sort friends: online first, then alphabetically
                final sortedFriends = List<Friend>.from(friends)
                  ..sort((a, b) {
                    if (a.isOnline && !b.isOnline) return -1;
                    if (!a.isOnline && b.isOnline) return 1;
                    return a.displayName.compareTo(b.displayName);
                  });

                // Split into online and offline sections
                final onlineFriends = sortedFriends.where((f) => f.isOnline).toList();
                final offlineFriends = sortedFriends.where((f) => !f.isOnline).toList();

                return SliverList(
                  delegate: SliverChildListDelegate([
                    if (onlineFriends.isNotEmpty) ...[
                      _buildSectionHeader('Online (${onlineFriends.length})'),
                      ...onlineFriends.map((friend) => FriendListItem(
                            friend: friend,
                            onChallenge: () => _challengeFriend(friend),
                          )),
                    ],
                    if (offlineFriends.isNotEmpty) ...[
                      _buildSectionHeader('Offline (${offlineFriends.length})'),
                      ...offlineFriends.map((friend) => FriendListItem(
                            friend: friend,
                            onChallenge: null, // Can't challenge offline friends
                          )),
                    ],
                  ]),
                );
              },
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error loading friends: $error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(friendsProvider),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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

  Widget _buildPendingRequestsSection(List<Friend> requests) {
    return Container(
      color: Theme.of(context).colorScheme.primaryContainer.withAlpha(77),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Friend Requests (${requests.length})',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...requests.map((request) => _buildPendingRequestItem(request)),
        ],
      ),
    );
  }

  Widget _buildPendingRequestItem(Friend request) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(request.displayName[0].toUpperCase()),
        ),
        title: Text(request.displayName),
        subtitle: const Text('Wants to be your friend'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              tooltip: 'Accept',
              onPressed: () => _acceptRequest(request),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              tooltip: 'Decline',
              onPressed: () => _declineRequest(request),
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
            const Icon(
              Icons.people_outline,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Invite friends to play Call My Word together!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showInviteDialog,
              icon: const Icon(Icons.person_add),
              label: const Text('Invite Friend'),
            ),
          ],
        ),
      ),
    );
  }

  void _showInviteDialog() {
    showDialog(
      context: context,
      builder: (context) => const InviteFriendDialog(),
    );
  }

  Future<void> _acceptRequest(Friend request) async {
    try {
      final friendService = ref.read(friendServiceProvider);
      await friendService.acceptFriendRequest(request.odId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${request.displayName} is now your friend!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _declineRequest(Friend request) async {
    try {
      final friendService = ref.read(friendServiceProvider);
      await friendService.declineFriendRequest(request.odId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _challengeFriend(Friend friend) async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final challengeService = ref.read(friendChallengeServiceProvider);
      final result = await challengeService.challengeFriend(friend.odId);

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChallengeWaitingScreen(
              challengeId: result.challengeId,
              friendName: friend.displayName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
