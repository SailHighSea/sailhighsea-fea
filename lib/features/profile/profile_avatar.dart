import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/avatar_presets.dart';
import 'profile_provider.dart';

/// The person's picture: their own upload, a ready-made avatar or the first letter of the name.
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({
    super.key,
    this.size = 44,
    this.ring,
    this.initialFill,
    this.initialColor,
  });

  final double size;

  /// Colour of the thin ring; the header passes white on its gradient.
  final Color? ring;
  final Color? initialFill;
  final Color? initialColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final name = ref.watch(displayNameProvider);
    final t = context.tokens;
    final initial = String.fromCharCode(name.runes.first).toUpperCase();
    final preset = avatarPresetById(profile.presetId);
    final file = profile.filePath;

    Widget letter() => Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.39,
          fontWeight: FontWeight.w700,
          color: initialColor ?? t.text,
        ),
      ),
    );

    final Widget face;
    Color? fill = initialFill ?? t.border;
    if (preset != null) {
      fill = preset.color;
      face = Icon(preset.icon, size: size * 0.52, color: Colors.white);
    } else if (file != null && File(file).existsSync()) {
      fill = null;
      face = Image.file(
        File(file),
        fit: BoxFit.cover,
        width: size,
        height: size,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => letter(),
        excludeFromSemantics: true,
      );
    } else {
      face = letter();
    }
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: ring == null ? null : Border.all(color: ring!, width: 2),
        ),
        child: face,
      ),
    );
  }
}
