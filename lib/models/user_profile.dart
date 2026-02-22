import 'package:cloud_firestore/cloud_firestore.dart';

/// User profile stored in Firestore /users/{userId}
class UserProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final int gamesPlayed;
  final int gamesWon;
  final bool isAnonymous;
  final DateTime createdAt;
  final DateTime lastActiveAt;

  // Presence and friend system fields
  final bool isOnline;
  final String? inviteCode;
  final DateTime? lastHeartbeat;

  const UserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.isAnonymous = true,
    required this.createdAt,
    required this.lastActiveAt,
    this.isOnline = false,
    this.inviteCode,
    this.lastHeartbeat,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      id: doc.id,
      displayName: data['displayName'] ?? 'Unknown',
      avatarUrl: data['avatarUrl'],
      gamesPlayed: data['gamesPlayed'] ?? 0,
      gamesWon: data['gamesWon'] ?? 0,
      isAnonymous: data['isAnonymous'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActiveAt:
          (data['lastActiveAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: data['isOnline'] ?? false,
      inviteCode: data['inviteCode'],
      lastHeartbeat: (data['lastHeartbeat'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'gamesPlayed': gamesPlayed,
      'gamesWon': gamesWon,
      'isAnonymous': isAnonymous,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActiveAt': Timestamp.fromDate(lastActiveAt),
      'isOnline': isOnline,
      'inviteCode': inviteCode,
      'lastHeartbeat':
          lastHeartbeat != null ? Timestamp.fromDate(lastHeartbeat!) : null,
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    int? gamesPlayed,
    int? gamesWon,
    bool? isAnonymous,
    DateTime? lastActiveAt,
    bool? isOnline,
    String? inviteCode,
    DateTime? lastHeartbeat,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      gamesWon: gamesWon ?? this.gamesWon,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isOnline: isOnline ?? this.isOnline,
      inviteCode: inviteCode ?? this.inviteCode,
      lastHeartbeat: lastHeartbeat ?? this.lastHeartbeat,
    );
  }
}
