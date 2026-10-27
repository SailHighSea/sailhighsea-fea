import 'package:flutter/material.dart';

/// A ready-made profile picture: an icon on a colour. Chosen by [id], which is what is stored.
class AvatarPreset {
  const AvatarPreset(this.id, this.name, this.icon, this.color);

  final String id;
  final String name;
  final IconData icon;
  final Color color;
}

const kAvatarPresets = <AvatarPreset>[
  AvatarPreset('fox', 'Fox', Icons.pets, Color(0xFFE07B39)),
  AvatarPreset('sailor', 'Sailor', Icons.sailing, Color(0xFF2F7FC1)),
  AvatarPreset('rocket', 'Rocket', Icons.rocket_launch, Color(0xFF7A5BC7)),
  AvatarPreset('bloom', 'Bloom', Icons.local_florist, Color(0xFFD65A8D)),
  AvatarPreset('leaf', 'Leaf', Icons.eco, Color(0xFF2E9D6B)),
  AvatarPreset('star', 'Star', Icons.star, Color(0xFFD9A21B)),
  AvatarPreset('music', 'Music', Icons.headphones, Color(0xFF3E4A9E)),
  AvatarPreset('coffee', 'Coffee', Icons.coffee, Color(0xFF8A5A3C)),
  AvatarPreset('bolt', 'Bolt', Icons.bolt, Color(0xFFC7503F)),
  AvatarPreset('moon', 'Moon', Icons.nightlight_round, Color(0xFF4A5B73)),
];

AvatarPreset? avatarPresetById(String? id) {
  for (final p in kAvatarPresets) {
    if (p.id == id) return p;
  }
  return null;
}
