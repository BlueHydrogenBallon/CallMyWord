import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../config/avatars.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../providers/friend_provider.dart';
import '../providers/presence_provider.dart';
import '../providers/profile_provider.dart';
import '../services/share_service.dart';
import '../services/user_service.dart';
import '../widgets/avatar_picker_dialog.dart';
import 'friends_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.profile),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(S.errorMsg(e.toString()))),
        data: (profile) {
          if (profile == null) {
            return Center(child: Text(S.somethingWentWrong));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(currentUserProfileProvider);
              ref.invalidate(gameHistoryProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(profile, colorScheme),
                  const SizedBox(height: 24),
                  _buildStatsSection(profile, colorScheme),
                  const SizedBox(height: 24),
                  _buildFriendsSection(colorScheme),
                  const SizedBox(height: 24),
                  _buildGameHistorySection(colorScheme),
                  const SizedBox(height: 24),
                  _buildInviteCodeSection(profile, colorScheme),
                  const SizedBox(height: 24),
                  _buildAccountSection(profile, colorScheme),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────

  Widget _buildHeader(UserProfile profile, ColorScheme colorScheme) {
    final avatar = getAvatarOption(profile.avatarUrl);
    final d = profile.createdAt;
    final memberDate = '${d.day}/${d.month}/${d.year}';

    return Column(
      children: [
        // Avatar
        GestureDetector(
          onTap: () => _showAvatarPicker(profile),
          child: Stack(
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: avatar.color,
                child: Icon(avatar.icon, size: 48, color: Colors.white),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: colorScheme.primaryContainer,
                  child: Icon(Icons.edit, size: 16,
                      color: colorScheme.onPrimaryContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Username
        GestureDetector(
          onTap: () => _showChangeUsername(profile),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile.displayName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.edit, size: 18, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Member since
        Text(
          '${S.memberSince} $memberDate',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  // ─── Stats ───────────────────────────────────────────────────────────

  Widget _buildStatsSection(UserProfile profile, ColorScheme colorScheme) {
    final winRatePercent = (profile.winRate * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(S.statistics, colorScheme),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildStatCard(S.gamesPlayedLabel, '${profile.gamesPlayed}',
                Icons.sports_esports, colorScheme),
            const SizedBox(width: 8),
            _buildStatCard(S.gamesWonLabel, '${profile.gamesWon}',
                Icons.emoji_events, colorScheme),
            const SizedBox(width: 8),
            _buildStatCard(S.winRateLabel, '$winRatePercent%',
                Icons.percent, colorScheme),
            const SizedBox(width: 8),
            _buildStatCard(S.totalPointsLabel, '${profile.totalPointsScored}',
                Icons.star, colorScheme),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, ColorScheme colorScheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Friends ─────────────────────────────────────────────────────────

  Widget _buildFriendsSection(ColorScheme colorScheme) {
    final friendsAsync = ref.watch(friendsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader(S.friends, colorScheme),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              ),
              child: Text(S.viewAll),
            ),
          ],
        ),
        friendsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (friends) {
            if (friends.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  S.noFriendsYet,
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            }
            return SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: friends.length > 8 ? 8 : friends.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final friend = friends[index];
                  final avatar = getAvatarOption(friend.avatarUrl);
                  return Column(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: avatar.color,
                            child: Icon(avatar.icon,
                                size: 20, color: Colors.white),
                          ),
                          if (friend.isOnline)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colorScheme.surface,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        friend.displayName.length > 8
                            ? '${friend.displayName.substring(0, 7)}…'
                            : friend.displayName,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  // ─── Game History ────────────────────────────────────────────────────

  Widget _buildGameHistorySection(ColorScheme colorScheme) {
    final historyAsync = ref.watch(gameHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(S.gameHistory, colorScheme),
        const SizedBox(height: 8),
        historyAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(S.errorMsg(e.toString())),
          data: (games) {
            if (games.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    S.noGamesYet,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              );
            }

            final displayGames = games.length > 5 ? games.sublist(0, 5) : games;

            return Column(
              children: [
                ...displayGames.map((game) => _buildGameHistoryItem(game, colorScheme)),
                if (games.length > 5)
                  TextButton(
                    onPressed: () {
                      // Could navigate to a full game history screen
                    },
                    child: Text('${S.viewAll} (${games.length})'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildGameHistoryItem(Map<String, dynamic> game, ColorScheme colorScheme) {
    final won = game['won'] as bool? ?? false;
    final playerScore = game['playerScore'] as int? ?? 0;
    final opponentNames = (game['opponentNames'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .join(', ') ??
        '?';
    final opponentScores = game['opponentScores'] as Map<String, dynamic>? ?? {};
    final topOpponentScore = opponentScores.values.isEmpty
        ? 0
        : opponentScores.values.fold<int>(
            0, (max, v) {
              final score = v is int ? v : 0;
              return score > max ? score : max;
            });

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            won ? Icons.emoji_events : Icons.close,
            color: won ? Colors.amber : Colors.grey,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${S.vs} $opponentNames',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$playerScore - $topOpponentScore',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: won
                  ? Colors.green.withOpacity(0.15)
                  : Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              won ? S.won : S.lost,
              style: TextStyle(
                color: won ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Invite Code ─────────────────────────────────────────────────────

  Widget _buildInviteCodeSection(UserProfile profile, ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.card_giftcard),
        label: Text(S.shareInviteCode),
        onPressed: () => _showInviteCodeDialog(),
      ),
    );
  }

  Future<void> _showInviteCodeDialog() async {
    String? code;
    String? error;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            if (code == null && error == null) {
              ref.read(userServiceProvider).generateInviteCode().then((c) {
                if (ctx.mounted) setState(() => code = c);
              }).catchError((e) {
                if (ctx.mounted) setState(() => error = e.toString());
              });
            }

            return AlertDialog(
              title: Text(S.inviteCode),
              content: code == null && error == null
                  ? const SizedBox(
                      height: 80,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : error != null
                      ? Text(S.errorMsg(error!))
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: code!));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(S.inviteCopied)),
                                );
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 16, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        code!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 4,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.copy,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              S.tapToCopyCode,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
              actions: [
                if (code != null)
                  TextButton.icon(
                    icon: const Icon(Icons.share),
                    label: Text(S.share),
                    onPressed: () {
                      ref.read(shareServiceProvider).shareInvite(code!);
                    },
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(S.close),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── Account ─────────────────────────────────────────────────────────

  Widget _buildAccountSection(UserProfile profile, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(S.account, colorScheme),
        const SizedBox(height: 8),
        _buildAccountTile(
          icon: Icons.logout,
          title: S.signOut,
          subtitle: '',
          onTap: () => _signOut(),
          isDestructive: true,
        ),
      ],
    );
  }

  Widget _buildAccountTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.red : null),
      title: Text(
        title,
        style: TextStyle(color: isDestructive ? Colors.red : null),
      ),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
          ),
    );
  }

  // ─── Actions ─────────────────────────────────────────────────────────

  void _showAvatarPicker(UserProfile profile) {
    showDialog(
      context: context,
      builder: (_) => AvatarPickerDialog(
        currentAvatarKey: profile.avatarUrl,
        onSelected: (key) async {
          final userId = ref.read(currentUserIdProvider);
          if (userId == null) return;
          await ref.read(userServiceProvider).updateAvatar(userId, key);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.avatarUpdated)),
            );
          }
        },
      ),
    );
  }

  void _showChangeUsername(UserProfile profile) {
    final controller = TextEditingController(text: profile.displayName);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(S.changeUsername),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(hintText: S.usernameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.length < 2) return;
              final userId = ref.read(currentUserIdProvider);
              if (userId == null) return;
              await ref.read(userServiceProvider).updateDisplayName(userId, name);
              if (mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(S.usernameUpdated)),
                );
              }
            },
            child: Text(S.save),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    ref.read(presenceManagerProvider).stopPresence();
    await ref.read(authServiceProvider).signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
