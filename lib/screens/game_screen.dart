import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game.dart';
import '../providers/auth_provider.dart';
import '../providers/audio_provider.dart';
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
    with WidgetsBindingObserver {
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

  // Track history lengths to detect new entries
  int _lastChallengeHistoryLength = 0;
  int _lastWordCallHistoryLength = 0;

  // Inline challenge response state
  final TextEditingController _challengeWordController = TextEditingController();
  String? _challengeError;

  // Inline word call response state
  final TextEditingController _continuationWordController = TextEditingController();
  String? _wordCallError;
  bool _showContinueInput = false;

  // Inline call word (initiating) state
  final TextEditingController _callWordController = TextEditingController();
  String? _callWordError;
  bool _showCallWordInput = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchGame();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gameSubscription?.cancel();
    _challengeWordController.dispose();
    _continuationWordController.dispose();
    _callWordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Resume music if it was playing before
      ref.read(backgroundMusicProvider).resumeIfNeeded();
    }
  }

  void _watchGame() {
    final gameService = ref.read(gameServiceProvider);
    _gameSubscription = gameService.watchGame(widget.gameId).listen(
      (game) {
        if (game == null) {
          setState(() {
            _error = 'Game not found';
          });
          return;
        }

        setState(() {
          _currentGame = game;
        });

        if (game.isGameOver) {
          _navigateToGameOver(game);
          return;
        }

        final userId = ref.read(currentUserIdProvider);
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

        // Handle word call response
        if (userId != null && game.isWordCallResponder(userId)) {
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
          }
        } else {
          // Stop clock sound when word call ends
          if (_lastWordCallId != null) {
            ref.read(soundEffectsProvider).stopClockSound();
            _lastWordCallId = null;
            _continuationWordController.clear();
            _wordCallError = null;
            _showContinueInput = false;
          }
        }

        // Detect new challenge history entries and show overlay
        if (game.challengeHistory.length > _lastChallengeHistoryLength && userId != null) {
          final latestEntry = game.challengeHistory.last;
          final didWin = latestEntry.winnerId == userId;
          _showPotResultOverlay(didWin, latestEntry.pointsAwarded);
        }
        _lastChallengeHistoryLength = game.challengeHistory.length;

        // Detect new word call history entries and show overlay
        if (game.wordCallHistory.length > _lastWordCallHistoryLength && userId != null) {
          final latestEntry = game.wordCallHistory.last;
          final didWin = latestEntry.winnerId == userId;
          _showPotResultOverlay(didWin, latestEntry.pointsAwarded);
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => GameOverScreen(game: game),
      ),
    );
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
        _challengeError = 'Word must contain "$fragment"';
      });
      return;
    }

    // Validate: minimum 4 characters
    if (claimedWord.length < 4) {
      setState(() {
        _challengeError = 'Word must be at least 4 letters';
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
        _callWordError = 'Word must be at least 4 letters';
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
    final calledWord = game.pendingWordCall!.calledWord;

    // Validate: must start with the original fragment
    if (!word.startsWith(fragment)) {
      setState(() {
        _wordCallError = 'Word must start with "$fragment"';
      });
      return;
    }

    // Validate: must be longer than the called word
    if (word.length <= calledWord.length) {
      setState(() {
        _wordCallError = 'Word must be longer than "$calledWord"';
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


  void _showPotResultOverlay(bool won, int amount) {
    setState(() {
      _showPotOverlay = true;
      _potWon = won;
      _potAmount = amount;
    });

    // Auto-dismiss after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showPotOverlay = false;
        });
      }
    });
  }

  String _parseError(String error) {
    if (error.contains('not your turn')) {
      return "Not your turn";
    } else if (error.contains('invalid letter')) {
      return 'Invalid letter';
    } else if (error.contains('not enough letters')) {
      return 'Need 2+ letters to challenge';
    }
    return 'Something went wrong';
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
        appBar: AppBar(title: const Text('Game')),
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
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (game == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Game')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final myPlayer = userId != null ? game.getPlayer(userId) : null;
    final opponent = userId != null ? game.getOpponent(userId) : null;
    final isMyTurn = userId != null && game.isPlayerTurn(userId);
    final isChallenged = userId != null && game.isChallengedPlayer(userId);
    final isChallenger = userId != null && game.isChallenger(userId);

    final isMusicMuted = ref.watch(musicMutedProvider);
    final isSfxMuted = ref.watch(soundEffectsMutedProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Turn ${game.turnNumber}'),
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
            tooltip: isSfxMuted ? 'Unmute sound effects' : 'Mute sound effects',
          ),
          // Music toggle
          IconButton(
            icon: Icon(
              isMusicMuted ? Icons.music_off : Icons.music_note,
              size: 20,
            ),
            onPressed: () => ref.read(backgroundMusicProvider).toggleMute(),
            tooltip: isMusicMuted ? 'Unmute music' : 'Mute music',
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
                // Top: Score cards
                Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: PlayerScoreCard(
                      player: myPlayer,
                      label: 'You',
                      isCurrentTurn: isMyTurn,
                      targetScore: game.settings.targetScore,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PlayerScoreCard(
                      player: opponent,
                      label: opponent?.displayName ?? 'Opponent',
                      isCurrentTurn: !isMyTurn && game.isInProgress,
                      targetScore: game.settings.targetScore,
                    ),
                  ),
                ],
              ),
            ),

            // Middle: Word display, pot, history (flexible)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        if (game.wordPot > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Pot: ${game.wordPot}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
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
                        onLetterPressed: (letter) {
                          // Append letter to challenge word controller
                          final currentText = _challengeWordController.text;
                          _challengeWordController.text = currentText + letter.toUpperCase();
                          _challengeWordController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _challengeWordController.text.length),
                          );
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
                        onLetterPressed: (letter) {
                          // Append letter to continuation word controller
                          final currentText = _continuationWordController.text;
                          _continuationWordController.text = currentText + letter.toUpperCase();
                          _continuationWordController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _continuationWordController.text.length),
                          );
                        },
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
                                  label: const Text('Challenge', style: TextStyle(fontSize: 12)),
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
                                  label: const Text('Call Word', style: TextStyle(fontSize: 12)),
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
                      onLetterPressed: _showCallWordInput
                          ? (letter) {
                              // Append letter to call word controller
                              final currentText = _callWordController.text;
                              _callWordController.text = currentText + letter.toUpperCase();
                              _callWordController.selection = TextSelection.fromPosition(
                                TextPosition(offset: _callWordController.text.length),
                              );
                            }
                          : _submitLetter,
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

    return Positioned.fill(
      child: Container(
        color: isWon
            ? Colors.green.shade900.withAlpha(217)
            : Colors.red.shade900.withAlpha(217),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                size: 64,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                isWon ? 'POT WON!' : 'POT LOST',
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              if (amount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(51),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+$amount pts',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                const Text(
                  'Both words invalid',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWordDisplay(Game game) {
    final word = game.currentWord;

    if (word.isEmpty) {
      return Text(
        'Start with any letter',
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
      final word = entry.continuationWord ?? entry.calledWord;
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isMyTurn ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isMyTurn ? 'Your turn' : "Opponent's turn",
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isMyTurn ? Colors.green.shade800 : Colors.grey.shade700,
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
                    'Challenge!',
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
                ? '${challenge.challengerName} challenged you!'
                : 'Waiting for ${challenge.challengedPlayerName}...',
            style: const TextStyle(fontSize: 13),
          ),

          if (isChallenged) ...[
            const SizedBox(height: 12),
            Text(
              'Enter a valid word containing "${game.currentWord}":',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _challengeWordController,
              autofocus: true,
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
                hintText: 'e.g., FRAGILE',
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
                    : const Text('Submit Word'),
              ),
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
                    'Word Called!',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              _ChallengeTimer(deadline: wordCall.responseDeadline),
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
          Text(
            'Fragment: ${wordCall.wordFragment}',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          if (isCaller) ...[
            const SizedBox(height: 8),
            Text(
              'Waiting for ${wordCall.responderName}...',
              style: const TextStyle(fontSize: 13),
            ),
          ],

          if (isResponder) ...[
            const SizedBox(height: 12),
            if (_showContinueInput)
              _buildContinueInputUI(wordCall, colorScheme)
            else
              _buildWordCallOptionsUI(colorScheme),
          ],
        ],
      ),
    );
  }

  Widget _buildWordCallOptionsUI(ColorScheme colorScheme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'How do you respond?',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        ),
        const SizedBox(height: 8),
        // Three inline buttons
        Row(
          children: [
            Expanded(
              child: _buildResponseOptionButton(
                icon: Icons.add_circle_outline,
                label: 'Continue',
                color: colorScheme.primary,
                onPressed: _isSubmitting ? null : _handleWordCallContinue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResponseOptionButton(
                icon: Icons.gavel,
                label: 'Challenge',
                color: colorScheme.error,
                onPressed: _isSubmitting ? null : _handleWordCallChallenge,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildResponseOptionButton(
                icon: Icons.check_circle_outline,
                label: 'Accept',
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
          'Enter a longer valid word starting with "${wordCall.wordFragment}":',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _continuationWordController,
          autofocus: true,
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
            hintText: 'e.g., ${wordCall.wordFragment}FYING',
            errorText: _wordCallError,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
          ),
          onSubmitted: (_) => _submitWordCallContinuation(),
        ),
        const SizedBox(height: 4),
        Text(
          'Must be longer than "${wordCall.calledWord}" to win!',
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
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
              child: const Text('Back'),
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
                  : const Text('Submit'),
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
                'Call Your Word',
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
            'Current fragment: $fragment',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _callWordController,
            autofocus: true,
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
              hintText: 'e.g., HORSE',
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
                child: const Text('Cancel'),
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
                    : const Text('Call Word'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showExitDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Game?'),
        content: const Text('You will forfeit the game.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).pop();
    }
  }
}

/// Compact countdown timer widget
class _ChallengeTimer extends StatefulWidget {
  final DateTime deadline;

  const _ChallengeTimer({required this.deadline});

  @override
  State<_ChallengeTimer> createState() => _ChallengeTimerState();
}

class _ChallengeTimerState extends State<_ChallengeTimer> {
  Timer? _timer;
  int _secondsRemaining = 0;

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
