import 'package:cloud_firestore/cloud_firestore.dart';

/// Friend relationship status
enum FriendStatus {
  pending,   // Invite sent, awaiting acceptance
  accepted,  // Mutual friendship established
  blocked,   // User blocked this friend
}

/// Represents a friend relationship stored in /users/{userId}/friends/{friendId}
class Friend {
  final String odId;
  final String displayName;
  final String? avatarUrl;
  final FriendStatus status;
  final bool isOnline;
  final DateTime? lastActiveAt;
  final DateTime createdAt;
  final String addedBy;

  const Friend({
    required this.odId,
    required this.displayName,
    this.avatarUrl,
    required this.status,
    this.isOnline = false,
    this.lastActiveAt,
    required this.createdAt,
    required this.addedBy,
  });

  factory Friend.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Friend(
      odId: doc.id,
      displayName: data['displayName'] ?? 'Unknown',
      avatarUrl: data['avatarUrl'],
      status: FriendStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => FriendStatus.pending,
      ),
      isOnline: data['isOnline'] ?? false,
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      addedBy: data['addedBy'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'avatarUrl': avatarUrl,
      'status': status.name,
      'isOnline': isOnline,
      'lastActiveAt':
          lastActiveAt != null ? Timestamp.fromDate(lastActiveAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'addedBy': addedBy,
    };
  }

  Friend copyWith({
    String? displayName,
    String? avatarUrl,
    FriendStatus? status,
    bool? isOnline,
    DateTime? lastActiveAt,
  }) {
    return Friend(
      odId: odId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      status: status ?? this.status,
      isOnline: isOnline ?? this.isOnline,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      createdAt: createdAt,
      addedBy: addedBy,
    );
  }
}
