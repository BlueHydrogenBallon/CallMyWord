import 'package:cloud_firestore/cloud_firestore.dart';

/// Challenge status
enum ChallengeStatus {
  pending,   // Challenge sent, waiting for response
  accepted,  // Challenge accepted, game starting
  declined,  // Challenge declined
  expired,   // Challenge expired (60 seconds timeout)
  cancelled, // Challenger cancelled
}

/// Represents a friend challenge stored in /friendChallenges/{challengeId}
class FriendChallenge {
  final String id;
  final String challengerId;
  final String challengerName;
  final String challengedId;
  final String challengedName;
  final ChallengeStatus status;
  final String? gameId;
  final String? lobbyId;
  final bool isParty;
  final DateTime createdAt;
  final DateTime expiresAt;

  const FriendChallenge({
    required this.id,
    required this.challengerId,
    required this.challengerName,
    required this.challengedId,
    required this.challengedName,
    required this.status,
    this.gameId,
    this.lobbyId,
    this.isParty = false,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Check if the challenge has expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Remaining time in seconds (0 if expired)
  int get remainingSeconds {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  factory FriendChallenge.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FriendChallenge(
      id: doc.id,
      challengerId: data['challengerId'] ?? '',
      challengerName: data['challengerName'] ?? 'Unknown',
      challengedId: data['challengedId'] ?? '',
      challengedName: data['challengedName'] ?? 'Unknown',
      status: ChallengeStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => ChallengeStatus.pending,
      ),
      gameId: data['gameId'],
      lobbyId: data['lobbyId'],
      isParty: data['isParty'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ??
          DateTime.now().add(const Duration(seconds: 60)),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'challengerId': challengerId,
      'challengerName': challengerName,
      'challengedId': challengedId,
      'challengedName': challengedName,
      'status': status.name,
      'gameId': gameId,
      'lobbyId': lobbyId,
      'isParty': isParty,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
    };
  }

  FriendChallenge copyWith({
    ChallengeStatus? status,
    String? gameId,
    String? lobbyId,
  }) {
    return FriendChallenge(
      id: id,
      challengerId: challengerId,
      challengerName: challengerName,
      challengedId: challengedId,
      challengedName: challengedName,
      status: status ?? this.status,
      gameId: gameId ?? this.gameId,
      lobbyId: lobbyId ?? this.lobbyId,
      isParty: isParty,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }
}
