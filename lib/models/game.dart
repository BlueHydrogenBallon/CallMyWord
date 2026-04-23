import 'package:cloud_firestore/cloud_firestore.dart';
import 'player.dart';

/// Game status enum
enum GameStatus {
  inProgress,
  challengePending,
  wordCallPending,
  completed,
  abandoned,
  waitingForRejoin;

  static GameStatus fromString(String value) {
    switch (value) {
      case 'in_progress':
        return GameStatus.inProgress;
      case 'challenge_pending':
        return GameStatus.challengePending;
      case 'word_call_pending':
        return GameStatus.wordCallPending;
      case 'completed':
        return GameStatus.completed;
      case 'abandoned':
        return GameStatus.abandoned;
      case 'waiting_for_rejoin':
        return GameStatus.waitingForRejoin;
      default:
        return GameStatus.inProgress;
    }
  }

  String toFirestore() {
    switch (this) {
      case GameStatus.inProgress:
        return 'in_progress';
      case GameStatus.challengePending:
        return 'challenge_pending';
      case GameStatus.wordCallPending:
        return 'word_call_pending';
      case GameStatus.completed:
        return 'completed';
      case GameStatus.abandoned:
        return 'abandoned';
      case GameStatus.waitingForRejoin:
        return 'waiting_for_rejoin';
    }
  }
}

/// Vote by another player on an active challenge
class ChallengeVote {
  final String type; // "join" or "pass"
  final String playerName;

  const ChallengeVote({required this.type, required this.playerName});

  factory ChallengeVote.fromMap(Map<String, dynamic> map) {
    return ChallengeVote(
      type: map['type'] ?? 'pass',
      playerName: map['playerName'] ?? 'Unknown',
    );
  }

  bool get isJoin => type == 'join';
}

/// Pending challenge data
class PendingChallenge {
  final String challengerId;
  final String challengerName;
  final String challengedPlayerId;
  final String challengedPlayerName;
  final String wordFragment;
  final DateTime responseDeadline;
  final DateTime createdAt;
  // Multi-player fields
  final List<String> otherPlayerIds;
  final Map<String, ChallengeVote> otherPlayerVotes;

  const PendingChallenge({
    required this.challengerId,
    required this.challengerName,
    required this.challengedPlayerId,
    required this.challengedPlayerName,
    required this.wordFragment,
    required this.responseDeadline,
    required this.createdAt,
    this.otherPlayerIds = const [],
    this.otherPlayerVotes = const {},
  });

  factory PendingChallenge.fromMap(Map<String, dynamic> map) {
    // Parse other player votes
    final votesData = map['otherPlayerVotes'] as Map<String, dynamic>? ?? {};
    final votes = <String, ChallengeVote>{};
    votesData.forEach((id, voteData) {
      votes[id] = ChallengeVote.fromMap(voteData as Map<String, dynamic>);
    });

    return PendingChallenge(
      challengerId: map['challengerId'] ?? '',
      challengerName: map['challengerName'] ?? 'Unknown',
      challengedPlayerId: map['challengedPlayerId'] ?? '',
      challengedPlayerName: map['challengedPlayerName'] ?? 'Unknown',
      wordFragment: map['wordFragment'] ?? '',
      responseDeadline:
          (map['responseDeadline'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      otherPlayerIds: List<String>.from(map['otherPlayerIds'] ?? []),
      otherPlayerVotes: votes,
    );
  }

  /// Time remaining to respond in seconds
  int get secondsRemaining {
    final remaining = responseDeadline.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Check if deadline has passed
  bool get hasExpired => DateTime.now().isAfter(responseDeadline);

  /// Check if a player can vote (is an other player and hasn't voted yet)
  bool canVote(String playerId) {
    return otherPlayerIds.contains(playerId) && !otherPlayerVotes.containsKey(playerId);
  }

  /// Check if a player has already voted
  bool hasVoted(String playerId) {
    return otherPlayerVotes.containsKey(playerId);
  }
}

/// Vote by a player on a word call
class WordCallVote {
  final String type; // "continue", "challenge", "accept"
  final String? continuationWord;
  final String playerName;

  const WordCallVote({required this.type, this.continuationWord, required this.playerName});

  factory WordCallVote.fromMap(Map<String, dynamic> map) {
    return WordCallVote(
      type: map['type'] ?? 'accept',
      continuationWord: map['continuationWord'],
      playerName: map['playerName'] ?? 'Unknown',
    );
  }
}

/// Pending word call data
class PendingWordCall {
  final String callerId;
  final String callerName;
  final String responderId;
  final String responderName;
  final String wordFragment;
  final String calledWord;
  final DateTime responseDeadline;
  final DateTime createdAt;
  // Multi-player fields
  final List<String> allResponderIds;
  final Map<String, WordCallVote> responderVotes;

  const PendingWordCall({
    required this.callerId,
    required this.callerName,
    required this.responderId,
    required this.responderName,
    required this.wordFragment,
    required this.calledWord,
    required this.responseDeadline,
    required this.createdAt,
    this.allResponderIds = const [],
    this.responderVotes = const {},
  });

  factory PendingWordCall.fromMap(Map<String, dynamic> map) {
    // Parse responder votes
    final votesData = map['responderVotes'] as Map<String, dynamic>? ?? {};
    final votes = <String, WordCallVote>{};
    votesData.forEach((id, voteData) {
      votes[id] = WordCallVote.fromMap(voteData as Map<String, dynamic>);
    });

    return PendingWordCall(
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? 'Unknown',
      responderId: map['responderId'] ?? '',
      responderName: map['responderName'] ?? 'Unknown',
      wordFragment: map['wordFragment'] ?? '',
      calledWord: map['calledWord'] ?? '',
      responseDeadline:
          (map['responseDeadline'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      allResponderIds: List<String>.from(map['allResponderIds'] ?? []),
      responderVotes: votes,
    );
  }

  /// Time remaining to respond in seconds
  int get secondsRemaining {
    final remaining = responseDeadline.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  /// Check if deadline has passed
  bool get hasExpired => DateTime.now().isAfter(responseDeadline);

  /// Whether this is a multi-player word call
  bool get isMultiPlayer => allResponderIds.length > 1;

  /// Check if a specific player can respond (hasn't voted yet)
  bool canRespond(String playerId) {
    return allResponderIds.contains(playerId) && !responderVotes.containsKey(playerId);
  }

  /// Check if a player has already voted
  bool hasVoted(String playerId) {
    return responderVotes.containsKey(playerId);
  }

  /// Number of votes collected vs total needed
  int get votesCollected => responderVotes.length;
  int get votesNeeded => allResponderIds.length;
}

/// Word call history entry
class WordCallHistoryEntry {
  final String wordFragment;
  final String calledWord;
  final String responseType; // continue, challenge, accept, timeout
  final String? continuationWord;
  final bool wasCalledWordValid;
  final bool? wasContinuationValid;
  final String? winnerId;
  final String? winnerName;
  final int pointsAwarded;
  final DateTime timestamp;
  final String? callerName;
  final String? responderName;

  const WordCallHistoryEntry({
    required this.wordFragment,
    required this.calledWord,
    required this.responseType,
    this.continuationWord,
    required this.wasCalledWordValid,
    this.wasContinuationValid,
    this.winnerId,
    this.winnerName,
    required this.pointsAwarded,
    required this.timestamp,
    this.callerName,
    this.responderName,
  });

  factory WordCallHistoryEntry.fromMap(Map<String, dynamic> map) {
    return WordCallHistoryEntry(
      wordFragment: map['wordFragment'] ?? '',
      calledWord: map['calledWord'] ?? '',
      responseType: map['responseType'] ?? '',
      continuationWord: map['continuationWord'],
      wasCalledWordValid: map['wasCalledWordValid'] ?? false,
      wasContinuationValid: map['wasContinuationValid'],
      winnerId: map['winnerId'],
      winnerName: map['winnerName'],
      pointsAwarded: map['pointsAwarded'] ?? 0,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      callerName: map['callerName'],
      responderName: map['responderName'],
    );
  }
}

/// Last action in the game (for UI display)
class LastAction {
  final String playerId;
  final String playerName;
  final String type;
  final String? letter;
  final String previousWord;
  final String resultingWord;
  final Map<String, dynamic>? scoringDetails;
  final DateTime timestamp;

  const LastAction({
    required this.playerId,
    required this.playerName,
    required this.type,
    this.letter,
    required this.previousWord,
    required this.resultingWord,
    this.scoringDetails,
    required this.timestamp,
  });

  factory LastAction.fromMap(Map<String, dynamic> map) {
    return LastAction(
      playerId: map['playerId'] ?? '',
      playerName: map['playerName'] ?? 'Unknown',
      type: map['type'] ?? '',
      letter: map['letter'],
      previousWord: map['previousWord'] ?? '',
      resultingWord: map['resultingWord'] ?? '',
      scoringDetails: map['scoringDetails'],
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Check if this was an add letter action
  bool get isAddLetter => type == 'add_letter';

  /// Check if this was a challenge action
  bool get isChallenge =>
      type == 'challenge_initiated' ||
      type == 'challenge_resolved' ||
      type == 'challenge_timeout';
}

/// Challenge history entry for tracking past challenges
class ChallengeHistoryEntry {
  final String wordFragment;
  final String? claimedWord;
  final bool wasWordValid;
  final String winnerId;
  final String winnerName;
  final int pointsAwarded;
  final DateTime timestamp;
  final String? challengerName;
  final String? challengedPlayerName;

  const ChallengeHistoryEntry({
    required this.wordFragment,
    this.claimedWord,
    required this.wasWordValid,
    required this.winnerId,
    required this.winnerName,
    required this.pointsAwarded,
    required this.timestamp,
    this.challengerName,
    this.challengedPlayerName,
  });

  factory ChallengeHistoryEntry.fromMap(Map<String, dynamic> map) {
    return ChallengeHistoryEntry(
      wordFragment: map['wordFragment'] ?? '',
      claimedWord: map['claimedWord'],
      wasWordValid: map['wasWordValid'] ?? false,
      winnerId: map['winnerId'] ?? '',
      winnerName: map['winnerName'] ?? 'Unknown',
      pointsAwarded: map['pointsAwarded'] ?? 0,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      challengerName: map['challengerName'],
      challengedPlayerName: map['challengedPlayerName'],
    );
  }
}

/// Game settings
class GameSettings {
  final String dictionary;
  final int startingLives;
  final int? turnTimeoutSeconds;
  final int challengeResponseSeconds;
  final int minWordLength;
  final int targetScore;

  const GameSettings({
    this.dictionary = 'english',
    this.startingLives = 3,
    this.turnTimeoutSeconds,
    this.challengeResponseSeconds = 30,
    this.minWordLength = 4,
    this.targetScore = 50,
  });

  factory GameSettings.fromMap(Map<String, dynamic> map) {
    return GameSettings(
      dictionary: map['dictionary'] ?? 'english',
      startingLives: map['startingLives'] ?? 3,
      turnTimeoutSeconds: map['turnTimeoutSeconds'],
      challengeResponseSeconds: map['challengeResponseSeconds'] ?? 30,
      minWordLength: map['minWordLength'] ?? 4,
      targetScore: map['targetScore'] ?? 50,
    );
  }
}

/// Game model stored in Firestore /games/{gameId}
class Game {
  final String id;
  final String lobbyId;
  final List<String> playerIds;
  final Map<String, Player> players;
  final String currentWord;
  final int wordPot;
  final int currentPlayerIndex;
  final int turnNumber;
  final int wordTurnNumber;
  final DateTime? turnDeadline;
  final GameStatus status;
  final PendingChallenge? pendingChallenge;
  final PendingWordCall? pendingWordCall;
  final LastAction? lastAction;
  final List<ChallengeHistoryEntry> challengeHistory;
  final List<WordCallHistoryEntry> wordCallHistory;
  final String? winnerId;
  final String? winnerName;
  final String? endReason;
  final String? abandonedBy;
  final DateTime? rejoinDeadline;
  final GameSettings settings;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Game({
    required this.id,
    required this.lobbyId,
    required this.playerIds,
    required this.players,
    this.currentWord = '',
    this.wordPot = 0,
    this.currentPlayerIndex = 0,
    this.turnNumber = 0,
    this.wordTurnNumber = 1,
    this.turnDeadline,
    this.status = GameStatus.inProgress,
    this.pendingChallenge,
    this.pendingWordCall,
    this.lastAction,
    this.challengeHistory = const [],
    this.wordCallHistory = const [],
    this.winnerId,
    this.winnerName,
    this.endReason,
    this.abandonedBy,
    this.rejoinDeadline,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Game.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // Parse players map
    final playersData = data['players'] as Map<String, dynamic>? ?? {};
    final players = <String, Player>{};
    playersData.forEach((id, playerData) {
      players[id] = Player.fromMap(id, playerData as Map<String, dynamic>);
    });

    // Parse challenge history
    final historyData = data['challengeHistory'] as List<dynamic>? ?? [];
    final challengeHistory = historyData
        .map((entry) => ChallengeHistoryEntry.fromMap(entry as Map<String, dynamic>))
        .toList();

    // Parse word call history
    final wordCallHistoryData = data['wordCallHistory'] as List<dynamic>? ?? [];
    final wordCallHistory = wordCallHistoryData
        .map((entry) => WordCallHistoryEntry.fromMap(entry as Map<String, dynamic>))
        .toList();

    return Game(
      id: doc.id,
      lobbyId: data['lobbyId'] ?? '',
      playerIds: List<String>.from(data['playerIds'] ?? []),
      players: players,
      currentWord: data['currentWord'] ?? '',
      wordPot: data['wordPot'] ?? 0,
      currentPlayerIndex: data['currentPlayerIndex'] ?? 0,
      turnNumber: data['turnNumber'] ?? 0,
      wordTurnNumber: data['wordTurnNumber'] ?? 1,
      turnDeadline: (data['turnDeadline'] as Timestamp?)?.toDate(),
      status: GameStatus.fromString(data['status'] ?? 'in_progress'),
      pendingChallenge: data['pendingChallenge'] != null
          ? PendingChallenge.fromMap(data['pendingChallenge'])
          : null,
      pendingWordCall: data['pendingWordCall'] != null
          ? PendingWordCall.fromMap(data['pendingWordCall'])
          : null,
      lastAction: data['lastAction'] != null
          ? LastAction.fromMap(data['lastAction'])
          : null,
      challengeHistory: challengeHistory,
      wordCallHistory: wordCallHistory,
      winnerId: data['winnerId'],
      winnerName: data['winnerName'],
      endReason: data['endReason'],
      abandonedBy: data['abandonedBy'],
      rejoinDeadline: (data['rejoinDeadline'] as Timestamp?)?.toDate(),
      settings: GameSettings.fromMap(data['settings'] ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // COMPUTED PROPERTIES
  // ═══════════════════════════════════════════════════════════════

  /// Get current player ID
  String get currentPlayerId => playerIds[currentPlayerIndex];

  /// Get current player
  Player? get currentPlayer => players[currentPlayerId];

  /// Check if it's a specific player's turn
  bool isPlayerTurn(String playerId) => currentPlayerId == playerId;

  /// Check if game is in progress
  bool get isInProgress => status == GameStatus.inProgress;

  /// Check if there's a pending challenge
  bool get isChallengePending => status == GameStatus.challengePending;

  /// Check if game is over
  bool get isGameOver =>
      status == GameStatus.completed || status == GameStatus.abandoned;

  /// Check if game is in the "opponent left, waiting to rejoin" state
  bool get isWaitingForRejoin => status == GameStatus.waitingForRejoin;

  /// Get a player by ID
  Player? getPlayer(String playerId) => players[playerId];

  /// Get opponent for a player (2-player game)
  Player? getOpponent(String myId) {
    final opponentId = playerIds.firstWhere(
      (id) => id != myId,
      orElse: () => '',
    );
    return opponentId.isNotEmpty ? players[opponentId] : null;
  }

  /// Get all other players except the given one (for multiplayer display)
  List<MapEntry<String, Player>> getOtherPlayers(String myId) {
    return players.entries.where((e) => e.key != myId).toList();
  }

  /// Check if a player is the challenged player in pending challenge
  bool isChallengedPlayer(String playerId) {
    return pendingChallenge?.challengedPlayerId == playerId;
  }

  /// Check if a player is the challenger in pending challenge
  bool isChallenger(String playerId) {
    return pendingChallenge?.challengerId == playerId;
  }

  /// Check if word is long enough to challenge
  bool get canChallenge => currentWord.length >= 2;

  /// Check if a specific player won
  bool didPlayerWin(String playerId) => winnerId == playerId;

  // ═══════════════════════════════════════════════════════════════
  // WORD CALL HELPERS
  // ═══════════════════════════════════════════════════════════════

  /// Check if there's a pending word call
  bool get isWordCallPending => status == GameStatus.wordCallPending;

  /// Check if a player is a responder for the pending word call (multi-player aware)
  bool isWordCallResponder(String playerId) {
    if (pendingWordCall == null) return false;
    // Multi-player: check allResponderIds and whether they haven't voted yet
    if (pendingWordCall!.isMultiPlayer) {
      return pendingWordCall!.canRespond(playerId);
    }
    // Legacy 2-player
    return pendingWordCall!.responderId == playerId;
  }

  /// Check if a player has already voted on the word call
  bool hasVotedOnWordCall(String playerId) {
    return pendingWordCall?.hasVoted(playerId) ?? false;
  }

  /// Check if a player is involved in the word call (responder or already voted)
  bool isWordCallParticipant(String playerId) {
    if (pendingWordCall == null) return false;
    if (pendingWordCall!.isMultiPlayer) {
      return pendingWordCall!.allResponderIds.contains(playerId);
    }
    return pendingWordCall!.responderId == playerId;
  }

  /// Check if a player is the caller for the pending word call
  bool isWordCaller(String playerId) {
    return pendingWordCall?.callerId == playerId;
  }

  /// Check if word is long enough to call (minimum 4 letters)
  bool get canCallWord => currentWord.length >= 4;
}
