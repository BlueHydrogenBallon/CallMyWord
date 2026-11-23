/// Player state within a game
class Player {
  final String id;
  final String displayName;
  final int score;
  final int lives;
  final bool isEliminated;
  final int joinOrder;

  const Player({
    required this.id,
    required this.displayName,
    this.score = 0,
    this.lives = 3,
    this.isEliminated = false,
    this.joinOrder = 0,
  });

  factory Player.fromMap(String id, Map<String, dynamic> map) {
    return Player(
      id: id,
      displayName: map['displayName'] ?? 'Unknown',
      score: map['score'] ?? 0,
      lives: map['lives'] ?? 3,
      isEliminated: map['isEliminated'] ?? false,
      joinOrder: map['joinOrder'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'score': score,
      'lives': lives,
      'isEliminated': isEliminated,
      'joinOrder': joinOrder,
    };
  }

  Player copyWith({
    String? displayName,
    int? score,
    int? lives,
    bool? isEliminated,
  }) {
    return Player(
      id: id,
      displayName: displayName ?? this.displayName,
      score: score ?? this.score,
      lives: lives ?? this.lives,
      isEliminated: isEliminated ?? this.isEliminated,
      joinOrder: joinOrder,
    );
  }
}
