import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/friend_challenge.dart';
import '../providers/auth_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/friend_challenge_provider.dart';
import '../providers/presence_provider.dart';
import '../services/user_service.dart';
import '../widgets/incoming_challenge_dialog.dart';
import 'auth_screen.dart';
import 'friends_screen.dart';
import 'matchmaking_screen.dart';
import 'party_setup_screen.dart';

/// Home screen / Lobby - entry point of the app
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  String? _lastShownChallengeId;
  bool _musicStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start presence after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPresence();
    });
  }

  void _ensureMusicStarted() {
    if (!_musicStarted) {
      _musicStarted = true;
      ref.read(backgroundMusicProvider).startMusic();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final presenceManager = ref.read(presenceManagerProvider);
    final musicService = ref.read(backgroundMusicProvider);

    switch (state) {
      case AppLifecycleState.resumed:
        // Ensure profile exists when app resumes
        _startPresence();
        // Resume music if it was playing before
        musicService.resumeIfNeeded();
        break;
      case AppLifecycleState.detached:
        // Only stop presence when app is actually closing, not just losing focus
        presenceManager.stopPresence();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Don't stop presence on paused/inactive - user might just switch tabs
        // The heartbeat will timeout after 2 minutes of inactivity if truly gone
        break;
      case AppLifecycleState.hidden:
        // Do nothing for hidden state
        break;
    }
  }

  void _startPresence() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    // Ensure user profile exists in Firestore
    try {
      final userService = ref.read(userServiceProvider);
      await userService.ensureUserProfile(
        userId: user.uid,
        defaultDisplayName: user.displayName ??
            (user.isAnonymous ? 'Guest${user.uid.substring(0, 6)}' : 'User'),
        isAnonymous: user.isAnonymous,
      );

      // Start presence tracking after profile is ensured
      ref.read(presenceManagerProvider).startPresence();
    } catch (e) {
      debugPrint('Error ensuring user profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final incomingChallengesAsync = ref.watch(incomingChallengesProvider);

    // Listen for incoming challenges and show dialog
    ref.listen<AsyncValue<List<FriendChallenge>>>(
      incomingChallengesProvider,
      (previous, next) {
        next.whenData((challenges) {
          if (challenges.isNotEmpty) {
            final challenge = challenges.first;
            // Only show if we haven't shown this challenge before
            if (_lastShownChallengeId != challenge.id) {
              _lastShownChallengeId = challenge.id;
              _showIncomingChallengeDialog(challenge);
            }
          }
        });
      },
    );

    return Scaffold(
      body: GestureDetector(
        onTap: _ensureMusicStarted,
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top bar: profile (left) and music (right)
                      _buildTopBar(authState),

                      // Main content
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Logo / Title
                          Center(
                            child: Image.asset(
                              'assets/images/logo.png',
                              height: 100,
                            ),
                          ),

                          const SizedBox(height: 16),

                          Center(
                            child: Text(
                              S.appSubtitle,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Colors.grey,
                                  ),
                            ),
                          ),

                          const SizedBox(height: 48),

                          // Incoming challenges banner
                          _buildIncomingChallengesBanner(incomingChallengesAsync),

                          const SizedBox(height: 24),

                          // Play buttons
                          authState.when(
                            data: (user) {
                              if (user == null) {
                                return Center(
                                  child: ElevatedButton(
                                    onPressed: () => _onSignInPressed(context),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 8),
                                      child: Text(
                                        S.signIn,
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  // New Game button
                                  Center(
                                    child: SizedBox(
                                      width: 250,
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _onNewGamePressed(context, ref),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                          child: Text(
                                            S.newGame,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // Challenge a Friend button
                                  Center(
                                    child: SizedBox(
                                      width: 250,
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _onChallengeAFriendPressed(context),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                          child: Text(
                                            S.challengeAFriend,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 16),

                                  // Multiplayer Party button
                                  Center(
                                    child: SizedBox(
                                      width: 250,
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _onMultiplayerPartyPressed(context),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                          child: Text(
                                            S.multiplayerParty,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                            loading: () =>
                                const Center(child: CircularProgressIndicator()),
                            error: (error, _) => Column(
                              children: [
                                Text(
                                  S.errorMsg(error.toString()),
                                  style: const TextStyle(color: Colors.red),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () =>
                                      ref.invalidate(authStateProvider),
                                  child: Text(S.retry),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // How to play button
                          Center(
                            child: TextButton(
                              onPressed: () => _showHowToPlay(context),
                              child: Text(S.howToPlay),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
            );
          },
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingChallengesBanner(
      AsyncValue<List<FriendChallenge>> challengesAsync) {
    return challengesAsync.when(
      data: (challenges) {
        if (challenges.isEmpty) return const SizedBox.shrink();

        final challenge = challenges.first;
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () => _showIncomingChallengeDialog(challenge),
            child: Row(
              children: [
                Icon(
                  Icons.sports_esports,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.challengesYou(challenge.challengerName),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        S.tapToRespond(challenge.remainingSeconds),
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildTopBar(AsyncValue<User?> authState) {
    final isMuted = ref.watch(musicMutedProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Profile (left)
        authState.when(
          data: (user) {
            if (user == null) return const SizedBox(width: 48);
            final displayName = user.isAnonymous
                ? S.guest
                : (user.displayName ?? user.email ?? 'User');
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.account_circle, size: 32),
                  offset: const Offset(0, 40),
                  onSelected: (value) {
                    switch (value) {
                      case 'upgrade':
                        _onSignInPressed(context);
                        break;
                      case 'signout':
                        _onSignOut(ref);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (user.isAnonymous)
                      PopupMenuItem(
                        value: 'upgrade',
                        child: Row(
                          children: [
                            const Icon(Icons.upgrade, size: 20),
                            const SizedBox(width: 8),
                            Text(S.upgradeAccount),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'signout',
                      child: Row(
                        children: [
                          const Icon(Icons.logout, size: 20),
                          const SizedBox(width: 8),
                          Text(S.signOut),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            );
          },
          loading: () => const SizedBox(width: 48),
          error: (_, __) => const SizedBox(width: 48),
        ),

        // Music toggle (right)
        IconButton(
          icon: Icon(
            isMuted ? Icons.music_off : Icons.music_note,
            size: 28,
          ),
          onPressed: () {
            ref.read(backgroundMusicProvider).toggleMute();
          },
        ),
      ],
    );
  }

  void _showIncomingChallengeDialog(FriendChallenge challenge) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => IncomingChallengeDialog(challenge: challenge),
    );
  }

  void _onNewGamePressed(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const MatchmakingScreen(),
      ),
    );
  }

  void _onChallengeAFriendPressed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const FriendsScreen(),
      ),
    );
  }

  void _onMultiplayerPartyPressed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PartySetupScreen(),
      ),
    );
  }

  void _onSignInPressed(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AuthScreen(),
      ),
    );
  }

  Future<void> _onSignOut(WidgetRef ref) async {
    // Stop presence before signing out
    ref.read(presenceManagerProvider).stopPresence();

    final authService = ref.read(authServiceProvider);
    await authService.signOut();
  }

  void _showHowToPlay(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.howToPlay),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(S.howToPlayInstructions),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.gotIt),
          ),
        ],
      ),
    );
  }
}
