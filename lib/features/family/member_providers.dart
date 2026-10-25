import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in person's display name. There are no accounts until Phase 3, so everything
/// added on this device belongs to "You".
final currentUserNameProvider = Provider<String>((ref) => 'You');

/// Initials for the sidebar footer (real household members arrive with Phase 3).
final memberInitialsProvider = Provider<List<String>>(
  (ref) => const ['Y', 'M', 'S'],
);
