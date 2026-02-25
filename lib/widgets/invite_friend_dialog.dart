import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../providers/auth_provider.dart';
import '../services/friend_service.dart';
import '../services/share_service.dart';
import '../services/user_service.dart';

/// Dialog for inviting friends and adding friends by code
class InviteFriendDialog extends ConsumerStatefulWidget {
  const InviteFriendDialog({super.key});

  @override
  ConsumerState<InviteFriendDialog> createState() => _InviteFriendDialogState();
}

class _InviteFriendDialogState extends ConsumerState<InviteFriendDialog> {
  final _codeController = TextEditingController();
  String? _inviteCode;
  bool _isLoadingCode = false;
  bool _isAddingFriend = false;
  String? _error;
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    // Small delay to ensure user profile is created
    Future.delayed(const Duration(milliseconds: 500), _loadInviteCode);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadInviteCode() async {
    setState(() {
      _isLoadingCode = true;
      _error = null;
    });

    try {
      // First, ensure user profile exists
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw Exception('Not signed in');
      }

      final userService = ref.read(userServiceProvider);
      await userService.ensureUserProfile(
        userId: user.uid,
        defaultDisplayName: user.displayName ??
            (user.isAnonymous ? 'Guest${user.uid.substring(0, 6)}' : 'User'),
        isAnonymous: user.isAnonymous,
      );

      // Now generate/get the invite code
      final friendService = ref.read(friendServiceProvider);
      final code = await friendService.getOrCreateInviteCode();

      if (mounted) {
        setState(() {
          _inviteCode = code;
          _isLoadingCode = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingCode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(S.inviteAFriend),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Your invite code section
            Text(
              S.yourInviteCode,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            _buildInviteCodeSection(),

            const SizedBox(height: 16),

            // Share buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ShareButton(
                  icon: Icons.email,
                  label: 'Email',
                  onTap: _inviteCode != null ? _shareViaEmail : null,
                ),
                _ShareButton(
                  icon: Icons.link,
                  label: S.copy,
                  onTap: _inviteCode != null ? _copyLink : null,
                ),
                _ShareButton(
                  icon: Icons.share,
                  label: S.share,
                  onTap: _inviteCode != null ? _shareGeneric : null,
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Add friend by code section
            Text(
              S.haveFriendsCode,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                hintText: S.enter6LetterCode,
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              onChanged: (_) {
                if (_error != null || _successMessage != null) {
                  setState(() {
                    _error = null;
                    _successMessage = null;
                  });
                }
              },
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),

            if (_successMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _successMessage!,
                  style: const TextStyle(color: Colors.green),
                ),
              ),

            const SizedBox(height: 16),

            ElevatedButton(
              onPressed: _isAddingFriend ? null : _addFriendByCode,
              child: _isAddingFriend
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(S.addFriend),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.close),
        ),
      ],
    );
  }

  Widget _buildInviteCodeSection() {
    if (_isLoadingCode) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_inviteCode == null) {
      return Column(
        children: [
          Text(
            _error ?? 'Failed to load invite code',
            style: const TextStyle(color: Colors.red, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _loadInviteCode,
            icon: const Icon(Icons.refresh),
            label: Text(S.retry),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        _inviteCode!,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _shareViaEmail() async {
    if (_inviteCode == null) return;

    final shareService = ref.read(shareServiceProvider);
    final success = await shareService.shareViaEmail(_inviteCode!);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  Future<void> _copyLink() async {
    if (_inviteCode == null) return;

    final shareService = ref.read(shareServiceProvider);
    await shareService.copyInviteLink(_inviteCode!);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.inviteCopied)),
      );
    }
  }

  Future<void> _shareGeneric() async {
    if (_inviteCode == null) return;

    final shareService = ref.read(shareServiceProvider);
    await shareService.shareInvite(_inviteCode!);
  }

  Future<void> _addFriendByCode() async {
    final code = _codeController.text.trim().toUpperCase();

    if (code.length != 6) {
      setState(() => _error = S.enter6LetterCodeError);
      return;
    }

    setState(() {
      _isAddingFriend = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final friendService = ref.read(friendServiceProvider);
      await friendService.addFriendByCode(code);

      if (mounted) {
        setState(() {
          _isAddingFriend = false;
          _successMessage = S.friendRequestSent;
          _codeController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAddingFriend = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }
}

/// Share button widget
class _ShareButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ShareButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: onTap != null ? 1.0 : 0.5,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
