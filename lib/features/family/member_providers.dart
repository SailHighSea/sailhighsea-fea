import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/db/tables.dart';
import '../../core/time.dart';
import '../auth/auth_providers.dart';
import 'data/household_remote.dart';
import 'data/household_repository.dart';
import 'domain/permissions.dart';
import 'domain/role.dart';
import 'household_controller.dart';

/// `null` while Supabase is not configured. `main()` and tests override it.
final householdRemoteProvider = Provider<HouseholdRemote?>((ref) => null);

final householdRepositoryProvider = Provider<HouseholdRepository>(
  (ref) => HouseholdRepository(
    ref.watch(databaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

final householdControllerProvider = Provider<HouseholdController>(
  HouseholdController.new,
);

/// The signed-in person's membership (role and name), from the local copy.
final myMemberProvider = StreamProvider<MemberRow?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return ref.watch(householdRepositoryProvider).watchMember(userId);
});

/// The household the person belongs to; `null` until they create or join one.
final activeHouseholdProvider = StreamProvider<HouseholdRow?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return Stream.value(null);
  return ref.watch(householdRepositoryProvider).watchMine(userId);
});

/// Household id that expenses and categories are read from and written to.
final activeHouseholdIdProvider = Provider<String>((ref) {
  if (ref.watch(authServiceProvider) == null) return localHouseholdId;
  return ref.watch(activeHouseholdProvider).value?.id ?? localHouseholdId;
});

final membersProvider = StreamProvider<List<MemberRow>>((ref) {
  final household = ref.watch(activeHouseholdProvider).value;
  if (household == null) return Stream.value(const []);
  return ref.watch(householdRepositoryProvider).watchMembers(household.id);
});

/// My role. Local-only (no Supabase configured) means one person who can do everything;
/// signed in without a membership yet is treated as view only.
final currentRoleProvider = Provider<Role>((ref) {
  if (ref.watch(authServiceProvider) == null) return Role.owner;
  final mine = ref.watch(myMemberProvider).value;
  return mine == null ? Role.viewer : Role.fromDb(mine.role);
});

/// What the UI may offer. The server enforces the same rules with Row Level Security.
final permissionsProvider = Provider<Permissions>(
  (ref) => Permissions(ref.watch(currentRoleProvider)),
);

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Turns an expense's `created_by` into the name shown as "who added": "You" for my own
/// entries, the member's name for others.
final addedByLabelProvider = Provider<String Function(String?)>((ref) {
  final me = ref.watch(currentUserIdProvider);
  final names = {
    for (final m in ref.watch(membersProvider).value ?? const <MemberRow>[])
      m.userId: m.displayName,
  };
  return (createdBy) {
    if (createdBy == null || createdBy == 'You' || createdBy == me) {
      return 'You';
    }
    final name = names[createdBy];
    if (name != null) return name;
    // A plain name from before accounts is shown as it is; an id we know nothing about is not.
    return _uuidPattern.hasMatch(createdBy) ? 'Someone' : createdBy;
  };
});

/// Initials for the sidebar footer, one per member.
final memberInitialsProvider = Provider<List<String>>((ref) {
  final members = ref.watch(membersProvider).value;
  if (members == null || members.isEmpty) return const ['Y'];
  return [
    for (final m in members)
      m.displayName.trim().isEmpty
          ? '?'
          : String.fromCharCode(m.displayName.trim().runes.first).toUpperCase(),
  ];
});
