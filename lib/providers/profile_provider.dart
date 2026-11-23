import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/user_service.dart';

/// Game history for the current user
final gameHistoryProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return [];

  final userService = ref.watch(userServiceProvider);
  return userService.getGameHistory(limit: 20);
});

