import 'package:cloud_firestore/cloud_firestore.dart';

/// User profile stored in Firestore /users/{userId}
class UserProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final int gamesPlayed;
  final int gamesWon;
  final int totalPointsScored;
  final bool isAnonymous;
  final DateTime createdAt;
  final DateTime lastActiveAt;

  // Presence and friend system fields
  final bool isOnline;
  final String? inviteCode;
  const UserProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.totalPointsScored = 0,
    this.isAnonymous = true,
    required this.createdAt,
    required this.lastActiveAt,
    this.isOnline = false,
    this.inviteCode,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile(
      id: doc.id,
      displayName: data['displayName'] ?? 'Unknown',
      avatarUrl: data['avatarUrl'],
      gamesPlayed: data['gamesPlayed'] ?? 0,
      gamesWon: data['gamesWon'] ?? 0,
      totalPointsScored: data['totalPointsScored'] ?? 0,
      isAnonymous: data['isAnonymous'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActiveAt:
          (data['lastActiveAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: data['isOnline'] ?? false,
      inviteCode: data['inviteCode'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'gamesPlayed': gamesPlayed,
      'gamesWon': gamesWon,
      'totalPointsScored': totalPointsScored,
      'isAnonymous': isAnonymous,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActiveAt': Timestamp.fromDate(lastActiveAt),
      'isOnline': isOnline,
      'inviteCode': inviteCode,
    };
  }

  double get winRate => gamesPlayed > 0 ? gamesWon / gamesPlayed : 0.0;

  UserProfile copyWith({
    String? displayName,
    String? avatarUrl,
    int? gamesPlayed,
    int? gamesWon,
    int? totalPointsScored,
    bool? isAnonymous,
    DateTime? lastActiveAt,
    bool? isOnline,
    String? inviteCode,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      gamesPlayed: gamesPlayed ?? this.gamesPlayed,
      gamesWon: gamesWon ?? this.gamesWon,
      totalPointsScored: totalPointsScored ?? this.totalPointsScored,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isOnline: isOnline ?? this.isOnline,
      inviteCode: inviteCode ?? this.inviteCode,
    );
  }
}
