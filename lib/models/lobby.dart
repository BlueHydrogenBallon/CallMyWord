import 'package:cloud_firestore/cloud_firestore.dart';

/// Lobby status enum
enum LobbyStatus {
  waiting,
  starting,
  started,
  cancelled;

  static LobbyStatus fromString(String value) {
    return LobbyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => LobbyStatus.waiting,
    );
  }
}

/// Lobby model stored in Firestore /lobbies/{lobbyId}
class Lobby {
  final String id;
  final String hostId;
  final String hostDisplayName;
  final List<String> playerIds;
  final Map<String, String> playerNames;
  final int playerCount;
  final int minPlayers;
  final int maxPlayers;
  final LobbyStatus status;
  final String? gameId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Lobby({
    required this.id,
    required this.hostId,
    required this.hostDisplayName,
    required this.playerIds,
    required this.playerNames,
    required this.playerCount,
    this.minPlayers = 2,
    this.maxPlayers = 2,
    this.status = LobbyStatus.waiting,
    this.gameId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Lobby.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Lobby(
      id: doc.id,
      hostId: data['hostId'] ?? '',
      hostDisplayName: data['hostDisplayName'] ?? 'Unknown',
      playerIds: List<String>.from(data['playerIds'] ?? []),
      playerNames: Map<String, String>.from(data['playerNames'] ?? {}),
      playerCount: data['playerCount'] ?? 0,
      minPlayers: data['minPlayers'] ?? 2,
      maxPlayers: data['maxPlayers'] ?? 2,
      status: LobbyStatus.fromString(data['status'] ?? 'waiting'),
      gameId: data['gameId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Check if lobby is full
  bool get isFull => playerCount >= maxPlayers;

  /// Check if lobby can start
  bool get canStart => playerCount >= minPlayers;

  /// Check if lobby is waiting for players
  bool get isWaiting => status == LobbyStatus.waiting;

  /// Check if game has started
  bool get hasStarted => status == LobbyStatus.started && gameId != null;
}
