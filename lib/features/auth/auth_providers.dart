import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_config.dart';
import 'auth_service.dart';

final supabaseConfigProvider = Provider<SupabaseConfig>(
  (ref) => const SupabaseConfig.fromEnvironment(),
);

/// `null` while Supabase is not configured: the app then runs local-only, as in Phase 2.
/// `main()` overrides this with the Supabase implementation; tests override it with a fake.
final authServiceProvider = Provider<AuthService?>((ref) => null);

/// The signed-in person, or `null`.
final authUserProvider = StreamProvider<AuthUser?>((ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth == null) return Stream.value(null);
  return auth.changes;
});

/// Id of the signed-in person; `null` when signed out or local-only.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authUserProvider).value?.id,
);
