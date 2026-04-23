import 'package:flutter/material.dart';

/// Predefined avatar options for user profiles.
/// Each avatar has a key (stored in Firestore), an icon, and a background color.
class AvatarOption {
  final String key;
  final IconData icon;
  final Color color;

  const AvatarOption({
    required this.key,
    required this.icon,
    required this.color,
  });
}

const kDefaultAvatarKey = 'avatar_person';

const List<AvatarOption> kAvatarOptions = [
  AvatarOption(key: 'avatar_person', icon: Icons.person, color: Color(0xFF6750A4)),
  AvatarOption(key: 'avatar_star', icon: Icons.star, color: Color(0xFFE6A817)),
  AvatarOption(key: 'avatar_pet', icon: Icons.pets, color: Color(0xFF8B5E3C)),
  AvatarOption(key: 'avatar_rocket', icon: Icons.rocket_launch, color: Color(0xFFE53935)),
  AvatarOption(key: 'avatar_music', icon: Icons.music_note, color: Color(0xFF1E88E5)),
  AvatarOption(key: 'avatar_bolt', icon: Icons.bolt, color: Color(0xFFFFA000)),
  AvatarOption(key: 'avatar_diamond', icon: Icons.diamond, color: Color(0xFF00ACC1)),
  AvatarOption(key: 'avatar_flower', icon: Icons.local_florist, color: Color(0xFFE91E63)),
  AvatarOption(key: 'avatar_fire', icon: Icons.local_fire_department, color: Color(0xFFFF5722)),
  AvatarOption(key: 'avatar_crown', icon: Icons.workspace_premium, color: Color(0xFFFFD600)),
  AvatarOption(key: 'avatar_ghost', icon: Icons.smart_toy, color: Color(0xFF7E57C2)),
  AvatarOption(key: 'avatar_globe', icon: Icons.public, color: Color(0xFF43A047)),
  AvatarOption(key: 'avatar_heart', icon: Icons.favorite, color: Color(0xFFF44336)),
  AvatarOption(key: 'avatar_shield', icon: Icons.shield, color: Color(0xFF546E7A)),
  AvatarOption(key: 'avatar_wizard', icon: Icons.auto_fix_high, color: Color(0xFF9C27B0)),
  AvatarOption(key: 'avatar_ninja', icon: Icons.visibility, color: Color(0xFF212121)),
];

/// Get the avatar option for a given key, falling back to default.
AvatarOption getAvatarOption(String? key) {
  if (key == null) {
    return kAvatarOptions.firstWhere((a) => a.key == kDefaultAvatarKey);
  }
  return kAvatarOptions.firstWhere(
    (a) => a.key == key,
    orElse: () => kAvatarOptions.firstWhere((a) => a.key == kDefaultAvatarKey),
  );
}
