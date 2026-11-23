import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../providers/auth_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/game_state_provider.dart';
import '../services/dictionary_service.dart';
import '../services/game_service.dart';
import '../widgets/game_keyboard.dart';
import '../widgets/player_score_card.dart';
import '../widgets/challenge_dialog.dart';
import 'game_over_screen.dart';

/// Main game screen - compact layout for iPhone SE
class GameScreen extends ConsumerStatefulWidget {
  final String gameId;

  const GameScreen({super.key, required this.gameId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  bool _isSubmitting = false;
  String? _error;
  StreamSubscription<Game?>? _gameSubscription;
  Game? _currentGame;
  bool? _wasMyTurn;
  String? _lastChallengeId;
  String? _lastWordCallId;

  // Pot result overlay state
  bool _showPotOverlay = false;
  bool _potWon = false;
  int _potAmount = 0;
  String? _potWord;
  bool _potWordValid = true;
  String? _potWordPlayerName;
  String? _potLoserWord;
  bool? _potLoserWordValid;
  String? _potLoserPlayerName;
  String? _potWinnerName;
  String? _potDefinition;
  int _potCountdown = 10;
  Timer? _potCountdownTimer;
  Timer? _abandonTimer;
  Timer? _rejoinCountdownTimer;
  int _rejoinSecondsLeft = 60;
  late final ConfettiController _potConfettiController;

  // Letter → pot animations
  final GlobalKey _potKey = GlobalKey();
  OverlayEntry? _flyOverlayEntry;
  late final AnimationController _flyController;
  late final AnimationController _bubbleController;
  String _bubbleText = '';
  int? _frozenPot;   // pot value frozen while tile is in flight
  int? _flyingPts;   // points on the tile in flight

  // Track history lengths to detect new entries
  int _lastChallengeHistoryLength = 0;
  int _lastWordCallHistoryLength = 0;

  // Inline challenge response state
  final TextEditingController _challengeWordController = TextEditingController();
  final FocusNode _challengeFocusNode = FocusNode();
  String? _challengeError;

  // Inline word call response state
  final TextEditingController _continuationWordController = TextEditingController();
  final FocusNode _continuationFocusNode = FocusNode();
  String? _wordCallError;
  bool _showContinueInput = false;
  bool _wordCallExpired = false;

  // Inline call word (initiating) state
  final TextEditingController _callWordController = TextEditingController();
  final FocusNode _callWordFocusNode = FocusNode();
  String? _callWordError;
  bool _showCallWordInput = false;

  void _rebuild() => setState(() {});

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _potConfettiController = ConfettiController(duration: const Duration(seconds: 2));
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _flyController.addListener(() => setState(() {}));
    _flyController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _flyOverlayEntry?.remove();
        _flyOverlayEntry = null;
        setState(() {
          _frozenPot = null;
          _flyingPts = null;
        });
      }
    });
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _bubbleController.addListener(() => setState(() {}));
    _callWordController.addListener(_rebuild);
    _continuationWordController.addListener(_rebuild);
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      void hideKeyboard() => SystemChannels.textInput.invokeMethod('TextInput.hide');
      _challengeFocusNode.addListener(() { if (_challengeFocusNode.hasFocus) hideKeyboard(); });
      _continuationFocusNode.addListener(() { if (_continuationFocusNode.hasFocus) hideKeyboard(); });
      _callWordFocusNode.addListener(() { if (_callWordFocusNode.hasFocus) hideKeyboard(); });
    }
    _watchGame();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(isInActiveGameProvider.notifier).state = true;
    });
  }

  @override
  void dispose() {
    ref.read(isInActiveGameProvider.notifier).state = false;
    WidgetsBinding.instance.removeObserver(this);
    _gameSubscription?.cancel();
    _potCountdownTimer?.cancel();
    _abandonTimer?.cancel();
    _rejoinCountdownTimer?.cancel();
    _potConfettiController.dispose();
    _flyController.dispose();
    _bubbleController.dispose();
    _flyOverlayEntry?.remove();
    _flyOverlayEntry = null;
    _callWordController.removeListener(_rebuild);
    _continuationWordController.removeListener(_rebuild);
    _challengeWordController.dispose();
    _challengeFocusNode.dispose();
    _continuationWordController.dispose();
    _continuationFocusNode.dispose();
    _callWordController.dispose();
    _callWordFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(backgroundMusicProvider).resumeIfNeeded();
      _abandonTimer?.cancel();
      _abandonTimer = null;
      // If we abandoned and came back within the window, auto-rejoin
      final userId = ref.read(currentUserIdProvider);
      final game = _currentGame;
      if (game != null &&
          game.isWaitingForRejoin &&
          game.abandonedBy == userId) {
        ref.read(gameServiceProvider).rejoinGame(widget.gameId).catchError((_) {});
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // If the player backgrounds/closes the app mid-game, abandon after 60s
      // so the opponent isn't left waiting indefinitely.
      _abandonTimer ??= Timer(const Duration(seconds: 60), () {
        final game = _currentGame;
        if (game != null && !game.isGameOver) {
          ref.read(gameServiceProvider).abandonGame(widget.gameId).catchError((_) {});
        }
      });
    }
  }

  void _watchGame() {
    final gameService = ref.read(gameServiceProvider);
    _gameSubscription = gameService.watchGame(widget.gameId).listen(
      (game) {
        if (!mounted) return;

        if (game == null) {
          setState(() {
            _error = S.gameNotFound;
          });
          return;
        }

        setState(() {
          _currentGame = game;
        });

        if (game.isGameOver) {
          _rejoinCountdownTimer?.cancel();
          _rejoinCountdownTimer = null;
          _navigateToGameOver(game);
          return;
        }

        // Start or stop the rejoin countdown for Player B
        final userId = ref.read(currentUserIdProvider);
        if (game.isWaitingForRejoin &&
            userId != null &&
            game.abandonedBy != userId &&
            game.rejoinDeadline != null) {
          _startRejoinCountdown(game.rejoinDeadline!);
        } else if (!game.isWaitingForRejoin) {
          _rejoinCountdownTimer?.cancel();
          _rejoinCountdownTimer = null;
        }
        final isMyTurn = userId != null && game.isPlayerTurn(userId);

        // Play "your turn" sound when it becomes the player's turn
        if (isMyTurn && _wasMyTurn == false) {
          ref.read(soundEffectsProvider).play(SoundEffect.yourTurn);
        }
        _wasMyTurn = isMyTurn;

        if (userId != null && game.isChallengedPlayer(userId)) {
          final challengeId = '${game.turnNumber}_${game.pendingChallenge?.challengerId}';

          // Play "challenged" sound and start clock when player gets challenged
          if (_lastChallengeId != challengeId) {
            final sfx = ref.read(soundEffectsProvider);
            sfx.play(SoundEffect.challenged);
            // Start clock sound after a short delay to let challenged sound play
            Future.delayed(const Duration(milliseconds: 500), () {
              sfx.startClockSound();
            });
            _lastChallengeId = challengeId;
            // Pre-fill the challenge word controller
            _challengeWordController.text = game.currentWord;
            _challengeError = null;
          }
        } else {
          // Stop clock sound when challenge ends
          if (_lastChallengeId != null) {
            ref.read(soundEffectsProvider).stopClockSound();
            _lastChallengeId = null;
            _challengeWordController.clear();
            _challengeError = null;
          }
        }

        // Handle word call response (multi-player aware)
        final isWcResponder = userId != null && game.isWordCallResponder(userId);
        final needsWordCallAttention = userId != null &&
            game.isWordCallParticipant(userId) &&
            !game.hasVotedOnWordCall(userId);
        if (isWcResponder || needsWordCallAttention) {
          final wordCallId = '${game.turnNumber}_${game.pendingWordCall?.callerId}';

          // Play sound and start clock when player needs to respond to word call
          if (_lastWordCallId != wordCallId) {
            final sfx = ref.read(soundEffectsProvider);
            sfx.play(SoundEffect.challenged);
            Future.delayed(const Duration(milliseconds: 500), () {
              sfx.startClockSound();
            });
            _lastWordCallId = wordCallId;
            // Pre-fill the continuation word controller
            _continuationWordController.text = game.pendingWordCall?.wordFragment ?? '';
            _wordCallError = null;
            _showContinueInput = false;
            _wordCallExpired = false;
          }
        } else {
          // Stop clock sound when word call ends
          if (_lastWordCallId != null) {
            ref.read(soundEffectsProvider).stopClockSound();
            _lastWordCallId = null;
            _continuationWordController.clear();
            _wordCallError = null;
            _showContinueInput = false;
            _wordCallExpired = false;
          }
        }

        // Detect new challenge history entries and show overlay
        if (game.challengeHistory.length > _lastChallengeHistoryLength && userId != null) {
          final latestEntry = game.challengeHistory.last;
          final didWin = latestEntry.winnerId == userId;
          final word = latestEntry.claimedWord ?? latestEntry.wordFragment;
          _showPotResultOverlay(
            didWin,
            latestEntry.pointsAwarded,
            word,
            wordValid: latestEntry.wasWordValid,
            wordPlayerName: latestEntry.challengedPlayerName,
            winnerName: latestEntry.winnerName,
          );
        }
        _lastChallengeHistoryLength = game.challengeHistory.length;

        // Detect new word call history entries and show overlay
        if (game.wordCallHistory.length > _lastWordCallHistoryLength && userId != null) {
          final latestEntry = game.wordCallHistory.last;
          final didWin = latestEntry.winnerId == userId;
          final hasContinuation = latestEntry.responseType == 'continue' &&
              latestEntry.continuationWord != null;
          final continuationWon = latestEntry.wasContinuationValid == true;

          final String? word;
          final bool wordValid;
          final String? wordPlayerName;
          final String? loserWord;
          final bool? loserWordValid;
          final String? loserPlayerName;

          if (hasContinuation && continuationWon) {
            word = latestEntry.continuationWord;
            wordValid = true;
            wordPlayerName = latestEntry.responderName;
            loserWord = latestEntry.calledWord;
            loserWordValid = latestEntry.wasCalledWordValid;
            loserPlayerName = latestEntry.callerName;
          } else if (hasContinuation) {
            word = latestEntry.calledWord;
            wordValid = latestEntry.wasCalledWordValid;
            wordPlayerName = latestEntry.callerName;
            loserWord = latestEntry.continuationWord;
            loserWordValid = latestEntry.wasContinuationValid ?? false;
            loserPlayerName = latestEntry.responderName;
          } else {
            word = latestEntry.calledWord;
            wordValid = latestEntry.wasCalledWordValid;
            wordPlayerName = latestEntry.callerName;
            loserWord = null;
            loserWordValid = null;
            loserPlayerName = null;
          }

          _showPotResultOverlay(
            didWin,
            latestEntry.pointsAwarded,
            word,
            loserWord: loserWord,
            wordValid: wordValid,
            wordPlayerName: wordPlayerName,
            loserWordValid: loserWordValid,
            loserPlayerName: loserPlayerName,
            winnerName: latestEntry.winnerName,
          );
        }
        _lastWordCallHistoryLength = game.wordCallHistory.length;
      },
      onError: (error) {
        setState(() {
          _error = error.toString();
        });
      },
    );
  }

  void _navigateToGameOver(Game game) {
    _gameSubscription?.cancel();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameOverScreen(game: game),
        ),
      );
    });
  }

  void _startRejoinCountdown(DateTime deadline) {
    // Don't restart if already ticking toward the same deadline
    if (_rejoinCountdownTimer?.isActive == true) return;
    _rejoinCountdownTimer?.cancel();
    setState(() {
      _rejoinSecondsLeft = deadline.difference(DateTime.now()).inSeconds.clamp(0, 60);
    });
    _rejoinCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = deadline.difference(DateTime.now()).inSeconds.clamp(0, 60);
      setState(() => _rejoinSecondsLeft = remaining);
      if (remaining <= 0) {
        timer.cancel();
        _claimAbandonWin();
      }
    });
  }

  /// Called when the rejoin countdown expires — claim the win from the backend.
  /// Retries once after a short delay to handle client/server clock skew.
  Future<void> _claimAbandonWin() async {
    debugPrint('[REJOIN] _claimAbandonWin called for game ${widget.gameId}');
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (!mounted) return;
        await ref.read(gameServiceProvider).claimAbandonWin(widget.gameId);
        debugPrint('[REJOIN] claimAbandonWin succeeded on attempt $attempt');
        return;
      } catch (e) {
        debugPrint('[REJOIN] claimAbandonWin attempt $attempt failed: $e');
        if (attempt < 2) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }
  }

  Future<void> _submitLetter(String letter) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.submitMove(widget.gameId, letter);
    } catch (e) {
      setState(() {
        _error = _parseError(e.toString());
      });
      _showErrorSnackbar(_error!);
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _initiateChallenge() async {
    final game = _currentGame;
    if (game == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ChallengeDialog(
        opponentName: game.currentPlayer?.displayName ?? 'Opponent',
        currentWord: game.currentWord,
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.initiateChallenge(widget.gameId);
    } catch (e) {
      setState(() {
        _error = _parseError(e.toString());
      });
      _showErrorSnackbar(_error!);
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _submitChallengeResponse() async {
    final game = _currentGame;
    if (game == null || game.pendingChallenge == null) return;

    final claimedWord = _challengeWordController.text.trim().toUpperCase();
    final fragment = game.currentWord;

    // Validate: must contain the fragment
    if (!claimedWord.contains(fragment)) {
      setState(() {
        _challengeError = S.wordMustContain(fragment);
      });
      return;
    }

    // Validate: minimum 4 characters
    if (claimedWord.length < 4) {
      setState(() {
        _challengeError = S.wordMinLength;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _challengeError = null;
    });

    // Stop clock sound when submitting
    ref.read(soundEffectsProvider).stopClockSound();

    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.respondToChallenge(widget.gameId, claimedWord);
    } catch (e) {
      setState(() {
        _challengeError = _parseError(e.toString());
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _voteOnChallenge(String vote) async {
    setState(() => _isSubmitting = true);
    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.voteOnChallenge(widget.gameId, vote);
    } catch (e) {
      // Silently handle — vote may have been recorded already
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _startCallWord() {
    final game = _currentGame;
    if (game == null) return;

    setState(() {
      _showCallWordInput = true;
      _callWordController.text = game.currentWord;
      _callWordError = null;
    });
  }

  void _cancelCallWord() {
    setState(() {
      _showCallWordInput = false;
      _callWordController.clear();
      _callWordError = null;
    });
  }

  Future<void> _submitCallWord() async {
    final game = _currentGame;
    if (game == null) return;

    final calledWord = _callWordController.text.trim().toUpperCase();
    final fragment = game.currentWord;

    // Validate: must start with current fragment
    if (!calledWord.startsWith(fragment)) {
      setState(() {
        _callWordError = 'Word must start with "$fragment"';
      });
      return;
    }

    // Validate: must be longer than fragment
    if (calledWord.length <= fragment.length) {
      setState(() {
        _callWordError = 'Enter the complete word you were building';
      });
      return;
    }

    // Validate: minimum 4 characters
    if (calledWord.length < 4) {
      setState(() {
        _callWordError = S.wordMinLength;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _callWordError = null;
    });

    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.callWord(widget.gameId, calledWord);
      // Hide the input on success
      setState(() {
        _showCallWordInput = false;
        _callWordController.clear();
      });
    } catch (e) {
      setState(() {
        _callWordError = _parseError(e.toString());
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  void _handleWordCallContinue() {
    setState(() {
      _showContinueInput = true;
      _wordCallError = null;
    });
  }

  Future<void> _submitWordCallContinuation() async {
    final game = _currentGame;
    if (game == null || game.pendingWordCall == null) return;

    final word = _continuationWordController.text.trim().toUpperCase();
    final fragment = game.pendingWordCall!.wordFragment;

    // Validate: must start with the original fragment
    if (!word.startsWith(fragment)) {
      setState(() {
        _wordCallError = 'Word must start with "$fragment"';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _wordCallError = null;
    });

    ref.read(soundEffectsProvider).stopClockSound();

    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.respondToWordCall(
        widget.gameId,
        'continue',
        continuationWord: word,
      );
    } catch (e) {
      setState(() {
        _wordCallError = _parseError(e.toString());
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleWordCallChallenge() async {
    setState(() {
      _isSubmitting = true;
    });

    ref.read(soundEffectsProvider).stopClockSound();

    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.respondToWordCall(widget.gameId, 'challenge');
    } catch (e) {
      setState(() {
        _wordCallError = _parseError(e.toString());
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _handleWordCallTimeExpired() async {
    // Auto-accept when time runs out so the caller's word gets validated immediately
    if (!mounted || _isSubmitting || _wordCallExpired) return;
    ref.read(soundEffectsProvider).stopClockSound();
    setState(() {
      _showContinueInput = false;
      _wordCallError = null;
      _wordCallExpired = true;
    });
    // If the server rejects due to deadline race, ignore the error —
    // the server's scheduled timeout handler will resolve it.
    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.respondToWordCall(widget.gameId, 'accept');
    } catch (_) {
      // Silently ignore — server cron will handle timeout resolution
    }
  }

  Future<void> _handleWordCallAccept() async {
    setState(() {
      _isSubmitting = true;
    });

    ref.read(soundEffectsProvider).stopClockSound();

    try {
      final gameService = ref.read(gameServiceProvider);
      await gameService.respondToWordCall(widget.gameId, 'accept');
    } catch (e) {
      setState(() {
        _wordCallError = _parseError(e.toString());
      });
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }


  void _showPotResultOverlay(
    bool won,
    int amount,
    String? word, {
    String? loserWord,
    bool wordValid = true,
    String? wordPlayerName,
    bool? loserWordValid,
    String? loserPlayerName,
    String? winnerName,
  }) {
    _potCountdownTimer?.cancel();
    setState(() {
      _showPotOverlay = true;
      _potWon = won;
      _potAmount = amount;
      _potWord = word;
      _potWordValid = wordValid;
      _potWordPlayerName = wordPlayerName;
      _potLoserWord = loserWord;
      _potLoserWordValid = loserWordValid;
      _potLoserPlayerName = loserPlayerName;
      _potWinnerName = winnerName;
      _potDefinition = null;
      _potCountdown = 15;
    });
    if (won) _potConfettiController.play();
    if (word != null) _fetchDefinition(word);

    _potCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _potCountdown--);
      if (_potCountdown <= 0) {
        timer.cancel();
        _dismissPotOverlay();
      }
    });
  }

  void _dismissPotOverlay() {
    _potCountdownTimer?.cancel();
    _potCountdownTimer = null;
    if (mounted && _showPotOverlay) {
      setState(() => _showPotOverlay = false);
    }
  }

  Future<void> _fetchDefinition(String word) async {
    try {
      final definition = await DictionaryService.lookup(word, isGreek: kIsGreek);
      if (mounted) setState(() => _potDefinition = definition ?? '');
    } catch (_) {
      if (mounted) setState(() => _potDefinition = '');
    }
  }

  String _parseError(String error) {
    if (error.contains('not your turn') || error.contains('Not your turn')) {
      return S.notYourTurn;
    } else if (error.contains('invalid letter') ||
        error.contains('must be a single') ||
        error.contains('invalid-argument')) {
      return S.invalidLetter;
    } else if (error.contains('not enough letters')) {
      return S.needMoreLetters;
    } else if (error.contains('deadline-exceeded') ||
        error.contains('Response time has expired')) {
      return S.timeExpired;
    }
    return S.somethingWentWrong;
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    final game = _currentGame;

    if (_error != null && game == null) {
      return Scaffold(
        appBar: AppBar(title: Text(S.game)),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(S.goBack),
              ),
            ],
          ),
        ),
      );
    }

    if (game == null) {
      return Scaffold(
        appBar: AppBar(title: Text(S.game)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Opponent left — show the waiting screen to Player B
    if (game.isWaitingForRejoin &&
        userId != null &&
        game.abandonedBy != userId) {
      return _buildWaitingForRejoinScreen(game);
    }

    final myPlayer = userId != null ? game.getPlayer(userId) : null;
    final otherPlayers = userId != null ? game.getOtherPlayers(userId) : <MapEntry<String, Player>>[];
    final isMyTurn = userId != null && game.isPlayerTurn(userId);
    final isChallenged = userId != null && game.isChallengedPlayer(userId);
    final isChallenger = userId != null && game.isChallenger(userId);

    final isMusicMuted = ref.watch(musicMutedProvider);
    final isSfxMuted = ref.watch(soundEffectsMutedProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(S.turnNumber(game.wordTurnNumber)),
        toolbarHeight: 44,
        automaticallyImplyLeading: false,
        actions: [
          // Sound effects toggle
          IconButton(
            icon: Icon(
              isSfxMuted ? Icons.volume_off : Icons.volume_up,
              size: 20,
            ),
            onPressed: () => ref.read(soundEffectsProvider).toggleMute(),
            tooltip: isSfxMuted ? S.unmuteSound : S.muteSound,
          ),
          // Music toggle
          IconButton(
            icon: Icon(
              isMusicMuted ? Icons.music_off : Icons.music_note,
              size: 20,
            ),
            onPressed: () => ref.read(backgroundMusicProvider).toggleMute(),
            tooltip: isMusicMuted ? S.unmuteMusic : S.muteMusic,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => _showExitDialog(),
          ),
        ],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Top: Score cards (dynamic for 2-4 players)
                Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = (constraints.maxWidth - 8) / 2 - 4;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      // "You" card
                      SizedBox(
                        width: cardWidth,
                        child: PlayerScoreCard(
                          player: myPlayer,
                          label: myPlayer?.displayName.isNotEmpty == true
                              ? myPlayer!.displayName
                              : S.you,
                          isCurrentTurn: isMyTurn,
                          targetScore: game.settings.targetScore,
                          accentColor: Colors.green,
                        ),
                      ),
                      // Other players
                      for (final entry in otherPlayers)
                        SizedBox(
                          width: cardWidth,
                          child: PlayerScoreCard(
                            player: entry.value,
                            label: entry.value.displayName,
                            isCurrentTurn: game.isInProgress &&
                                game.playerIds[game.currentPlayerIndex] == entry.key,
                            targetScore: game.settings.targetScore,
                            accentColor: Colors.lightBlue,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Middle: Word display, pot, history (flexible, scrollable)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ConstrainedBox(
                      // Ensure content fills the available height so it stays
                      // centered. On very small viewports the box can shrink and
                      // the user can scroll to see all content.
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Word display
                          _buildWordDisplay(game),

                          const SizedBox(height: 8),

                          // Word pot + Challenge history row
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (game.wordPot > 0) _buildPotDisplay(game),
                            ],
                          ),

                          // Challenge & Word Call history (compact)
                          if ((game.challengeHistory.isNotEmpty || game.wordCallHistory.isNotEmpty) && userId != null) ...[
                            const SizedBox(height: 8),
                            _buildGameHistory(game, userId),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom: Challenge UI, Word Call UI, and/or Keyboard
            if (game.isChallengePending)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildChallengePendingUI(game, isChallenged, isChallenger),
                    // Show keyboard for challenged player to type their word
                    if (isChallenged)
                      GameKeyboard(
                        language: kDictionary,
                        onLetterPressed: (letter, _) {
                          // Append letter to challenge word controller
                          final currentText = _challengeWordController.text;
                          _challengeWordController.text = currentText + letter.toUpperCase();
                          _challengeWordController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _challengeWordController.text.length),
                          );
                        },
                        onBackspace: () {
                          final text = _challengeWordController.text;
                          if (text.isNotEmpty) {
                            _challengeWordController.text = text.substring(0, text.length - 1);
                            _challengeWordController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _challengeWordController.text.length),
                            );
                          }
                        },
                        enabled: !_isSubmitting,
                      ),
                  ],
                ),
              )
            else if (game.isWordCallPending)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildWordCallPendingUI(game, userId),
                    // Show keyboard for responder when entering continuation word
                    if (userId != null && game.isWordCallResponder(userId) && _showContinueInput)
                      GameKeyboard(
                        language: kDictionary,
                        onLetterPressed: (letter, _) {
                          // Append letter to continuation word controller
                          final currentText = _continuationWordController.text;
                          _continuationWordController.text = currentText + letter.toUpperCase();
                          _continuationWordController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _continuationWordController.text.length),
                          );
                        },
                        onBackspace: _continuationWordController.text.length > (game.pendingWordCall?.wordFragment.length ?? 0)
                            ? () {
                                final text = _continuationWordController.text;
                                _continuationWordController.text = text.substring(0, text.length - 1);
                                _continuationWordController.selection = TextSelection.fromPosition(
                                  TextPosition(offset: _continuationWordController.text.length),
                                );
                              }
                            : null,
                        enabled: !_isSubmitting,
                      ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Call Word inline UI (when active)
                    if (_showCallWordInput)
                      _buildCallWordInputUI(game)
                    else ...[
                      // Turn indicator + Challenge button row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildTurnIndicator(game, isMyTurn),
                            if (isMyTurn && game.canChallenge && !_isSubmitting) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 32,
                                child: OutlinedButton.icon(
                                  onPressed: _initiateChallenge,
                                  icon: const Icon(Icons.gavel, size: 16),
                                  label: Text(S.challenge, style: const TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    foregroundColor: Colors.orange.shade700,
                                    side: BorderSide(color: Colors.orange.shade700),
                                  ),
                                ),
                              ),
                            ],
                            if (isMyTurn && game.canCallWord && !_isSubmitting) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 32,
                                child: OutlinedButton.icon(
                                  onPressed: _startCallWord,
                                  icon: const Icon(Icons.check_circle_outline, size: 16),
                                  label: Text(S.callWord, style: const TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    foregroundColor: Colors.green.shade700,
                                    side: BorderSide(color: Colors.green.shade700),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Keyboard
                    GameKeyboard(
                      language: kDictionary,
                      onLetterPressed: _showCallWordInput
                          ? (letter, _) {
                              // Append letter to call word controller
                              final currentText = _callWordController.text;
                              _callWordController.text = currentText + letter.toUpperCase();
                              _callWordController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _callWordController.text.length),
                              );
                            }
                          : (letter, keyCenter) {
                              _triggerLetterAnimation(letter, keyCenter);
                              _submitLetter(letter);
                            },
                      onBackspace: _showCallWordInput
                          ? (_callWordController.text.length > game.currentWord.length
                              ? () {
                                  final text = _callWordController.text;
                                  _callWordController.text = text.substring(0, text.length - 1);
                                  _callWordController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _callWordController.text.length),
                                  );
                                }
                              : null)
                          : null,
                      enabled: _showCallWordInput ? !_isSubmitting : (isMyTurn && !_isSubmitting),
                    ),
                  ],
                ),
              ),
          ],
            ),
          ),

          // Pot result overlay
          if (_showPotOverlay) _buildPotResultOverlay(),
        ],
      ),
    );
  }

  Widget _buildPotResultOverlay() {
    final isWon = _potWon;
    final amount = _potAmount;
    final word = _potWord;
    final loserWord = _potLoserWord;
    final definition = _potDefinition;

    // Resolve winner label ("You" for current player, actual name otherwise)
    final userId = ref.read(currentUserIdProvider);
    final myDisplayName = _currentGame?.getPlayer(userId ?? '')?.displayName;
    final winnerLabel = isWon ? S.you : (_potWinnerName ?? '');

    // "You" substitution helper for words box
    String labelFor(String? name) =>
        (name != null && name == myDisplayName) ? S.you : (name ?? '');

    // Build ranked words list (high → low points)
    final wordItems = [
      if (word != null)
        (word: word, playerName: _potWordPlayerName, isValid: _potWordValid,
            pts: calculateWordPoints(word)),
      if (loserWord != null)
        (word: loserWord, playerName: _potLoserPlayerName,
            isValid: _potLoserWordValid ?? false,
            pts: calculateWordPoints(loserWord)),
    ]..sort((a, b) {
      if (a.isValid != b.isValid) return a.isValid ? -1 : 1;
      return b.pts.compareTo(a.pts);
    });

    return Positioned.fill(
      child: Stack(
        children: [
          // Full-screen background (always fills the entire body area)
          Positioned.fill(
            child: ColoredBox(
              color: isWon
                  ? Colors.green.shade900.withAlpha(217)
                  : Colors.red.shade900.withAlpha(217),
            ),
          ),
          // Scrollable content on top
          SingleChildScrollView(
              padding: const EdgeInsets.only(top: 32, bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Icon
                  Icon(
                    isWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                    size: 64,
                    color: Colors.white,
                  ),

                  const SizedBox(height: 16),

                  // 2. "You won / lost the pot"
                  Text(
                    isWon ? S.potWon : S.potLost,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3a. Winner sentence (without the word)
                  Text(
                    amount == 0
                        ? S.bothWordsInvalid
                        : _potWordValid
                            ? (isWon
                                ? S.wonWithWordYouPts(amount)
                                : S.wonWithWord(winnerLabel, amount))
                            : (isWon
                                ? S.wonChallengeYou(amount)
                                : S.wonChallenge(winnerLabel, amount)),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),

                  // 3b. Winning word — separate line, bold & large
                  if (_potWordValid && word != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      word.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 4,
                      ),
                    ),
                  ],

                  // 4. Definition (only for valid winning word)
                  if (_potWordValid && word != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 100),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(60),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: definition == null
                          ? const Center(
                              child: SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white54,
                                ),
                              ),
                            )
                          : definition.isEmpty
                              ? const Text(
                                  'No definition found',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white38,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: Text(
                                    definition,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white70,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                    ),
                  ],

                  // 5. Words box (ranked high → low)
                  if (wordItems.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (int i = 0; i < wordItems.length; i++) ...[
                          if (i > 0) const SizedBox(height: 6),
                          _buildWordBreakdownRow(
                            playerName: labelFor(wordItems[i].playerName),
                            word: wordItems[i].word,
                            isValid: wordItems[i].isValid,
                            points: wordItems[i].pts,
                          ),
                        ],
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),

                  // 6. Countdown sentence
                  Text(
                    S.nextRoundIn(_potCountdown),
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          if (isWon)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _potConfettiController,
                blastDirectionality: BlastDirectionality.explosive,
                colors: const [
                  Colors.green,
                  Colors.lightGreen,
                  Colors.white,
                  Colors.yellow,
                  Colors.lime,
                ],
                numberOfParticles: 15,
                emissionFrequency: 0.03,
                maxBlastForce: 20,
                minBlastForce: 8,
                gravity: 0.3,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWordBreakdownRow({
    String? playerName,
    required String word,
    required bool isValid,
    required int points,
  }) {
    final bgColor = isValid ? Colors.green.shade900 : Colors.grey.shade800;
    final showName = playerName != null && playerName.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Username column
          if (showName) ...[
            SizedBox(
              width: 72,
              child: Text(
                playerName,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              width: 1,
              height: 18,
              color: Colors.white24,
              margin: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ],
          // Word column
          Expanded(
            child: Text(
              word.toUpperCase(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isValid ? Colors.white : Colors.white54,
                letterSpacing: 1.5,
                decoration: isValid ? null : TextDecoration.lineThrough,
                decorationColor: Colors.white54,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 18,
            color: Colors.white24,
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          // Points column
          Text(
            isValid ? '$points pts' : '—',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // ── Pot display with animated "+X" bubble ──────────────────────────────────

  Widget _buildPotDisplay(Game game) {
    final bubbleOpacity = (1.0 - CurvedAnimation(
      parent: _bubbleController,
      curve: const Interval(0.33, 1.0, curve: Curves.easeOut),
    ).value).clamp(0.0, 1.0);

    // While a tile is in flight: show old value until the tile starts fading
    // (flyController >= 0.7), then flip to old + pts so it's revealed on arrival.
    int displayPot;
    if (_frozenPot != null && _flyController.isAnimating) {
      displayPot = (_flyController.value >= 0.7)
          ? _frozenPot! + (_flyingPts ?? 0)
          : _frozenPot!;
    } else {
      displayPot = game.wordPot;
    }

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          key: _potKey,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            S.pot(displayPot),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.amber.shade900,
            ),
          ),
        ),
        if (_bubbleText.isNotEmpty)
          Positioned.fill(
            child: Opacity(
              opacity: bubbleOpacity,
              child: Center(
                child: Text(
                  _bubbleText,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade900,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Letter → pot animation trigger ────────────────────────────────────────

  void _triggerLetterAnimation(String letter, Offset keyCenter) {
    final userId = ref.read(currentUserIdProvider);
    final game = _currentGame;
    if (game == null || userId == null) return;
    if (!game.isPlayerTurn(userId)) return;

    final pts = calculateWordPoints(letter);
    if (pts <= 0) return;
    final text = '+$pts';

    // Flying tile: skip if submitting or building a call-word buffer
    if (_isSubmitting || _showCallWordInput) {
      setState(() { _bubbleText = text; });
      _bubbleController.forward(from: 0.0);
      return;
    }

    final potBox = _potKey.currentContext?.findRenderObject() as RenderBox?;
    if (potBox == null || !mounted) {
      setState(() { _bubbleText = text; });
      _bubbleController.forward(from: 0.0);
      return;
    }
    final potCenter = potBox.localToGlobal(
      Offset(potBox.size.width / 2, potBox.size.height / 2),
    );

    // Cancel any in-flight tile and freeze the current pot value
    final oldEntry = _flyOverlayEntry;
    _flyOverlayEntry = null;
    oldEntry?.remove();
    _flyController.stop();
    setState(() {
      _bubbleText = text;
      _frozenPot = game.wordPot;
      _flyingPts = pts;
    });
    _bubbleController.forward(from: 0.0);

    final entry = _buildFlyingTileEntry(
      text: text,
      startPosition: keyCenter,
      endPosition: potCenter,
    );
    _flyOverlayEntry = entry;
    Overlay.of(context).insert(entry);
    _flyController.forward(from: 0.0);
  }

  // ── Flying tile OverlayEntry ───────────────────────────────────────────────

  OverlayEntry _buildFlyingTileEntry({
    required String text,
    required Offset startPosition,
    required Offset endPosition,
  }) {
    final posAnim = CurvedAnimation(
      parent: _flyController,
      curve: Curves.easeInOut,
    );
    final fadeAnim = CurvedAnimation(
      parent: _flyController,
      curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
    );

    return OverlayEntry(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AnimatedBuilder(
          animation: _flyController,
          builder: (context, _) {
            final pos = Offset.lerp(
              Offset(startPosition.dx - 14, startPosition.dy - 19),
              Offset(endPosition.dx - 14, endPosition.dy - 19),
              posAnim.value,
            )!;
            final opacity = (1.0 - fadeAnim.value).clamp(0.0, 1.0);

            return Positioned(
              left: pos.dx,
              top: pos.dy,
              child: IgnorePointer(
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 28,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(60),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Word display ───────────────────────────────────────────────────────────

  Widget _buildWordDisplay(Game game) {
    final word = game.currentWord;

    if (word.isEmpty) {
      return Text(
        S.startWithAnyLetter,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[500],
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        word,
        style: const TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          letterSpacing: 6,
        ),
      ),
    );
  }

  Widget _buildGameHistory(Game game, String userId) {
    // Combine challenge and word call history into a single list with timestamps
    final List<_HistoryEntry> entries = [];

    // Add challenge history entries
    for (final entry in game.challengeHistory) {
      entries.add(_HistoryEntry(
        word: entry.claimedWord ?? entry.wordFragment,
        didWin: entry.winnerId == userId,
        pointsAwarded: entry.pointsAwarded,
        timestamp: entry.timestamp,
        type: 'challenge',
      ));
    }

    // Add word call history entries
    for (final entry in game.wordCallHistory) {
      final word = (entry.wasContinuationValid == true && entry.continuationWord != null)
          ? entry.continuationWord!
          : entry.calledWord;
      entries.add(_HistoryEntry(
        word: word,
        didWin: entry.winnerId == userId,
        pointsAwarded: entry.pointsAwarded,
        timestamp: entry.timestamp,
        type: entry.responseType,
      ));
    }

    // Sort by timestamp descending (newest first)
    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Container(
      constraints: const BoxConstraints(maxHeight: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...entries.map((entry) {
                final pointsText = entry.didWin ? '+${entry.pointsAwarded}' : '-${entry.pointsAwarded}';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.word,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: entry.didWin ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: entry.didWin ? Colors.green.shade100 : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          pointsText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: entry.didWin ? Colors.green.shade700 : Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTurnIndicator(Game game, bool isMyTurn) {
    final color = isMyTurn ? Colors.green : Colors.lightBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade400, width: 1.5),
      ),
      child: Text(
        isMyTurn ? S.yourTurn : S.opponentsTurn,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: color.shade800,
        ),
      ),
    );
  }

  Widget _buildChallengePendingUI(
    Game game,
    bool isChallenged,
    bool isChallenger,
  ) {
    final challenge = game.pendingChallenge!;
    final colorScheme = Theme.of(context).colorScheme;
    final userId = ref.read(currentUserIdProvider);

    // Multi-player: check if this player is an "other" who can vote
    final canVoteOnChallenge = userId != null && challenge.canVote(userId);
    final hasVotedOnChallenge = userId != null && challenge.hasVoted(userId);

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with title and timer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.gavel, size: 24, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    S.challengeExclaim,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
              _ChallengeTimer(deadline: challenge.responseDeadline),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isChallenged
                ? S.challengesYou(challenge.challengerName)
                : '${challenge.challengerName} challenges ${challenge.challengedPlayerName}',
            style: const TextStyle(fontSize: 13),
          ),

          if (isChallenged) ...[
            const SizedBox(height: 12),
            Text(
              S.enterWordContaining(game.currentWord),
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _challengeWordController,
              focusNode: _challengeFocusNode,
              autofocus: true,
              readOnly: !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS),
              showCursor: true,
              textCapitalization: TextCapitalization.characters,
              enabled: !_isSubmitting,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  return newValue.copyWith(
                    text: newValue.text.toUpperCase(),
                  );
                }),
              ],
              decoration: InputDecoration(
                hintText: S.wordHintChallenge,
                errorText: _challengeError,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              onSubmitted: (_) => _submitChallengeResponse(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: FilledButton(
                onPressed: _isSubmitting ? null : _submitChallengeResponse,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(S.submitWord),
              ),
            ),
          ],

          // Multi-player: voting UI for other players
          if (canVoteOnChallenge) ...[
            const SizedBox(height: 12),
            Text(
              'Do you think ${challenge.challengedPlayerName} is bluffing?',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildResponseOptionButton(
                    icon: Icons.gavel,
                    label: 'Join Challenge',
                    color: colorScheme.error,
                    onPressed: _isSubmitting ? null : () => _voteOnChallenge('join'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildResponseOptionButton(
                    icon: Icons.remove_circle_outline,
                    label: 'Pass',
                    color: colorScheme.outline,
                    onPressed: _isSubmitting ? null : () => _voteOnChallenge('pass'),
                  ),
                ),
              ],
            ),
          ],

          // Multi-player: show "voted" confirmation
          if (hasVotedOnChallenge) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text(
                  'You voted: ${challenge.otherPlayerVotes[userId]?.type == 'join' ? 'Join Challenge' : 'Pass'}',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],

          // Show vote count for multi-player games
          if (challenge.otherPlayerIds.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '${challenge.otherPlayerVotes.length}/${challenge.otherPlayerIds.length} other players voted',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWordCallPendingUI(Game game, String? userId) {
    final wordCall = game.pendingWordCall!;
    final isResponder = userId != null && game.isWordCallResponder(userId);
    final isCaller = userId != null && game.isWordCaller(userId);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with title and timer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, size: 24, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text(
                    S.wordCalled,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              _ChallengeTimer(
                deadline: wordCall.responseDeadline,
                onExpired: isResponder && !game.hasVotedOnWordCall(userId)
                    ? () => _handleWordCallTimeExpired()
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Called word display
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              wordCall.calledWord,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
                color: colorScheme.onPrimaryContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                S.fragment(wordCall.wordFragment),
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                S.points(calculateWordPoints(wordCall.calledWord)),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),

          if (isCaller) ...[
            const SizedBox(height: 8),
            if (wordCall.isMultiPlayer) ...[
              Text(
                'Waiting for responses (${wordCall.votesCollected}/${wordCall.votesNeeded})',
                style: const TextStyle(fontSize: 13),
              ),
            ] else ...[
              Text(
                S.waitingFor(wordCall.responderName),
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ],

          if (isResponder && !_wordCallExpired) ...[
            const SizedBox(height: 12),
            if (_showContinueInput)
              _buildContinueInputUI(wordCall, colorScheme)
            else
              _buildWordCallOptionsUI(colorScheme),
          ],

          if (isResponder && _wordCallExpired) ...[
            const SizedBox(height: 12),
            Text(
              S.timeExpired,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
          ],

          // Multi-player: show "already voted" confirmation
          if (userId != null && game.hasVotedOnWordCall(userId)) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text(
                  'You voted: ${wordCall.responderVotes[userId]?.type ?? 'unknown'}',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Waiting for others (${wordCall.votesCollected}/${wordCall.votesNeeded})',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWordCallOptionsUI(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          S.howDoYouRespond,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(height: 8),
        // Three inline buttons
        Row(
          children: [
            Expanded(
              child: _buildResponseOptionButton(
                icon: Icons.add_circle_outline,
                label: S.continueWord,
                color: colorScheme.primary,
                onPressed: _isSubmitting ? null : _handleWordCallContinue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResponseOptionButton(
                icon: Icons.gavel,
                label: S.challenge,
                color: colorScheme.error,
                onPressed: _isSubmitting ? null : _handleWordCallChallenge,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResponseOptionButton(
                icon: Icons.check_circle_outline,
                label: S.acceptWord,
                color: colorScheme.tertiary,
                onPressed: _isSubmitting ? null : _handleWordCallAccept,
              ),
            ),
          ],
        ),
        if (_isSubmitting) ...[
          const SizedBox(height: 8),
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }

  Widget _buildResponseOptionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        side: BorderSide(color: color.withAlpha(128)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueInputUI(PendingWordCall wordCall, ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          S.enterLongerWordStartingWith(wordCall.wordFragment),
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _continuationWordController,
          focusNode: _continuationFocusNode,
          autofocus: true,
          readOnly: !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS),
          showCursor: true,
          textCapitalization: TextCapitalization.characters,
          enabled: !_isSubmitting,
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              if (newValue.text.length < wordCall.wordFragment.length) return oldValue;
              return newValue.copyWith(text: newValue.text.toUpperCase());
            }),
          ],
          decoration: InputDecoration(
            hintText: S.wordHintContinuation(wordCall.wordFragment),
            errorText: _wordCallError,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          onSubmitted: (_) => _submitWordCallContinuation(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: _isSubmitting
                  ? null
                  : () => setState(() {
                        _showContinueInput = false;
                        _wordCallError = null;
                      }),
              child: Text(S.back),
            ),
            const Spacer(),
            FilledButton(
              onPressed: _isSubmitting ? null : _submitWordCallContinuation,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(S.submit),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCallWordInputUI(Game game) {
    final colorScheme = Theme.of(context).colorScheme;
    final fragment = game.currentWord;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 20, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                S.callYourWord,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            S.currentFragment(fragment),
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _callWordController,
            focusNode: _callWordFocusNode,
            autofocus: true,
            readOnly: !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS),
            showCursor: true,
            textCapitalization: TextCapitalization.characters,
            enabled: !_isSubmitting,
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) {
                if (newValue.text.length < fragment.length) return oldValue;
                return newValue.copyWith(text: newValue.text.toUpperCase());
              }),
            ],
            decoration: InputDecoration(
              hintText: S.wordHintCallWord,
              errorText: _callWordError,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            onSubmitted: (_) => _submitCallWord(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: _isSubmitting ? null : _cancelCallWord,
                child: Text(S.cancel),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _isSubmitting ? null : _submitCallWord,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(S.callWord),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showExitDialog() async {
    // Capture ref-dependent values BEFORE the async gap
    final gameService = ref.read(gameServiceProvider);
    final gameId = widget.gameId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.leaveGame),
        content: Text(S.leaveGameConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.stay),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(S.leave),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      // Fire-and-forget abandon — gameService is a captured local, no ref needed
      gameService.abandonGame(gameId).catchError((_) {});
    }
  }

  Widget _buildWaitingForRejoinScreen(Game game) {
    final opponentName = game.playerIds
        .where((id) => id != game.abandonedBy)
        .map((id) => game.players[id]?.displayName ?? '')
        .firstOrNull ?? '';
    final abandonerName = game.abandonedBy != null
        ? (game.players[game.abandonedBy!]?.displayName ?? S.leave)
        : S.leave;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person_off_outlined, size: 64, color: Colors.orange),
                const SizedBox(height: 24),
                Text(
                  S.opponentLeftTitle,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  S.opponentLeftBody(_rejoinSecondsLeft),
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Countdown ring
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: _rejoinSecondsLeft / 60,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _rejoinSecondsLeft > 15 ? Colors.orange : Colors.red,
                        ),
                      ),
                    ),
                    Text(
                      '$_rejoinSecondsLeft',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                // Wait — just shows their current score context
                Text(
                  opponentName.isNotEmpty
                      ? '${S.waitAndWin} — $opponentName'
                      : S.waitAndWin,
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
                const SizedBox(height: 24),
                // Quit button
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await ref.read(gameServiceProvider).abandonGame(widget.gameId);
                    } catch (_) {}
                    if (mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.exit_to_app, color: Colors.red),
                  label: Text(
                    S.quitAndLose,
                    style: const TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  abandonerName,
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact countdown timer widget
class _ChallengeTimer extends StatefulWidget {
  final DateTime deadline;
  final VoidCallback? onExpired;

  const _ChallengeTimer({required this.deadline, this.onExpired});

  @override
  State<_ChallengeTimer> createState() => _ChallengeTimerState();
}

class _ChallengeTimerState extends State<_ChallengeTimer> {
  Timer? _timer;
  int _secondsRemaining = 0;
  bool _expiredFired = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateRemaining() {
    final remaining = widget.deadline.difference(DateTime.now()).inSeconds;
    setState(() {
      _secondsRemaining = remaining > 0 ? remaining : 0;
    });
    // Fire the callback 2 seconds early to give the HTTP request time
    // to reach the server before the deadline passes.
    if (remaining <= 2 && !_expiredFired && widget.onExpired != null) {
      _expiredFired = true;
      widget.onExpired!.call();
    }
    if (_secondsRemaining <= 0) {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrgent = _secondsRemaining <= 10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.red.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${_secondsRemaining}s',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: isUrgent ? Colors.red.shade700 : Colors.grey.shade700,
        ),
      ),
    );
  }
}

/// Helper class for combined game history display
class _HistoryEntry {
  final String word;
  final bool didWin;
  final int pointsAwarded;
  final DateTime timestamp;
  final String type;

  _HistoryEntry({
    required this.word,
    required this.didWin,
    required this.pointsAwarded,
    required this.timestamp,
    required this.type,
  });
}
