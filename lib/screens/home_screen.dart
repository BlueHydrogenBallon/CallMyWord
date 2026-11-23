import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_strings.dart';
import '../models/friend_challenge.dart';
import '../models/game.dart';
import '../providers/auth_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/friend_challenge_provider.dart';
import '../providers/game_state_provider.dart';
import '../providers/presence_provider.dart';
import '../services/game_service.dart';
import '../services/user_service.dart';
import '../widgets/incoming_challenge_dialog.dart';
import 'auth_screen.dart';
import 'friends_screen.dart';
import 'game_screen.dart';
import 'matchmaking_screen.dart';
import 'party_setup_screen.dart';
import 'profile_screen.dart';

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
  bool _rejoinSheetShown = false;

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
    final musicService = ref.read(backgroundMusicProvider);

    switch (state) {
      case AppLifecycleState.resumed:
        // Re-establish presence on resume (RTDB reconnects automatically,
        // but this ensures the subscription is set up if it wasn't already).
        _startPresence();
        musicService.resumeIfNeeded();
        break;
      case AppLifecycleState.detached:
        // Explicit cleanup on app close. Even if this doesn't fire (common
        // on web), RTDB onDisconnect() handles it server-side.
        ref.read(presenceManagerProvider).stopPresence();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // RTDB onDisconnect() handles offline detection — no action needed.
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

    // Listen for a rejoinable game and auto-show the bottom sheet
    ref.listen<AsyncValue<Game?>>(
      rejoinableGameProvider,
      (previous, next) {
        next.whenData((game) {
          if (game != null && !_rejoinSheetShown) {
            _rejoinSheetShown = true;
            // Defer to after the current frame — can't show a sheet during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showRejoinSheet(game);
            });
          } else if (game == null) {
            _rejoinSheetShown = false;
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

                      // Banner ad intentionally omitted from home screen —
                      // the AdWidget PlatformView intercepts all Flutter touch
                      // events on Android. Ads are shown between games instead.
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
            final profile = ref.watch(currentUserProfileProvider).valueOrNull;
            final profileName = profile?.displayName;
            final displayName = (profileName != null && profileName.isNotEmpty)
                ? profileName
                : (user.isAnonymous
                    ? S.guest
                    : (user.displayName ?? user.email ?? 'User'));
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.account_circle, size: 32),
                  const SizedBox(width: 8),
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                ],
              ),
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

  void _showRejoinSheet(Game game) {
    final userId = ref.read(currentUserProvider)?.uid ?? '';
    final opponentName =
        game.getOpponent(userId)?.displayName ?? 'Opponent';

    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RejoinBottomSheet(
        game: game,
        opponentName: opponentName,
        onRejoin: () => _onRejoin(game),
        onForfeit: () => _onForfeit(game),
      ),
    ).then((_) {
      if (mounted) setState(() => _rejoinSheetShown = false);
    });
  }

  Future<void> _onRejoin(Game game) async {
    try {
      await ref.read(gameServiceProvider).rejoinGame(game.id);
    } catch (_) {
      // best-effort — GameScreen stream will handle current state
    }
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GameScreen(gameId: game.id)),
      );
    }
  }

  Future<void> _onForfeit(Game game) async {
    try {
      await ref.read(gameServiceProvider).abandonGame(game.id);
    } catch (_) {
      // best-effort
    }
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

// ─── Rejoin Bottom Sheet ──────────────────────────────────────────────────────

class _RejoinBottomSheet extends StatefulWidget {
  final Game game;
  final String opponentName;
  final VoidCallback onRejoin;
  final VoidCallback onForfeit;

  const _RejoinBottomSheet({
    required this.game,
    required this.opponentName,
    required this.onRejoin,
    required this.onForfeit,
  });

  @override
  State<_RejoinBottomSheet> createState() => _RejoinBottomSheetState();
}

class _RejoinBottomSheetState extends State<_RejoinBottomSheet> {
  static const int _totalWindowSeconds = 60;

  late int _secondsLeft;
  Timer? _timer;
  bool _acted = false;

  @override
  void initState() {
    super.initState();
    final deadline = widget.game.rejoinDeadline;
    if (deadline != null) {
      final remaining = deadline.difference(DateTime.now()).inSeconds;
      _secondsLeft = remaining > 0 ? remaining : 0;
    } else {
      _secondsLeft = 0;
    }

    if (_secondsLeft > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _secondsLeft = _secondsLeft > 0 ? _secondsLeft - 1 : 0);
        if (_secondsLeft == 0 && !_acted) {
          _acted = true;
          _timer?.cancel();
          Navigator.of(context).pop();
          widget.onRejoin();
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _acted) return;
        _acted = true;
        Navigator.of(context).pop();
        widget.onRejoin();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_secondsLeft / _totalWindowSeconds).clamp(0.0, 1.0);
    final currentWord = widget.game.currentWord;
    final wordPot = widget.game.wordPot;
    final isUrgent = _secondsLeft <= 15;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            S.rejoinTitle,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          Text(
            S.rejoinVs(widget.opponentName),
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.grey),
          ),

          if (currentWord.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              S.rejoinCurrentWord(currentWord),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],

          if (wordPot > 0) ...[
            const SizedBox(height: 4),
            Text(
              S.rejoinWordPot(wordPot),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.amber.shade700,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],

          const SizedBox(height: 24),

          Text(
            S.rejoinSeconds(_secondsLeft),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isUrgent ? Colors.orange : null,
                ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: isUrgent
                  ? Colors.orange
                  : Theme.of(context).colorScheme.primary,
              backgroundColor: Colors.grey.shade200,
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                if (_acted) return;
                _acted = true;
                _timer?.cancel();
                Navigator.of(context).pop();
                widget.onRejoin();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  S.rejoinNow,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          TextButton(
            onPressed: () {
              if (_acted) return;
              _acted = true;
              _timer?.cancel();
              Navigator.of(context).pop();
              widget.onForfeit();
            },
            child: Text(
              S.rejoinForfeit(widget.opponentName),
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
