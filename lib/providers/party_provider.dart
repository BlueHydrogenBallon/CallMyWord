import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/lobby.dart';

/// Watch a specific lobby for real-time updates (player joins, status changes)
final partyLobbyProvider =
    StreamProvider.family<Lobby, String>((ref, lobbyId) {
  return FirebaseFirestore.instance
      .collection('lobbies')
      .doc(lobbyId)
      .snapshots()
      .map((doc) {
    if (!doc.exists) {
      throw Exception('Lobby not found');
    }
    return Lobby.fromFirestore(doc);
  });
});
