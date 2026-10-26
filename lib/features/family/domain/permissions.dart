import 'role.dart';
import 'visibility.dart';

/// What a role may do. This mirrors the Row Level Security policies in
/// `supabase/migrations` and exists only to hide buttons the server would reject anyway
/// (rule 6: the server is the authority). If a rule changes, change the SQL first.
class Permissions {
  const Permissions(this.role, {this.localData = false});

  final Role role;

  /// Google Sheets mode: everyone keeps their own data on their own device, so everyone may add
  /// categories for it.
  final bool localData;

  /// Used before sign-in and when Supabase is not configured: one person, everything allowed.
  static const local = Permissions(Role.owner);

  bool get _isManager => role == Role.owner || role == Role.admin;

  /// Add, edit and delete expenses.
  bool get canWriteExpenses => _isManager || role == Role.editor;

  /// Categories, budgets, goals and bills (PLAN.md open decision 2).
  bool get canManageCategories => _isManager || localData;
  bool get canManageBudgets => _isManager;
  bool get canManageGoals => _isManager;
  bool get canManageBills => _isManager;

  /// Create and revoke invite codes, change roles, remove members.
  bool get canInvite => _isManager;
  bool get canManageMembers => _isManager;

  /// Google Sheet: only the owner connects, changes or disconnects it. Owner and admins can
  /// open it and press Sync now. Everyone else sees the state.
  bool get canConnectSheet => role == Role.owner;
  bool get canSyncSheet => _isManager;

  /// Choose whether an editor or viewer sees everyone's spending or only their own. Never for
  /// yourself, and owner and admin always see everything so there is nothing to choose.
  bool canSetVisibility(Role target, {required bool isSelf}) =>
      _isManager && !isSelf && (target == Role.editor || target == Role.viewer);

  /// The "Everyone" overview and the member filter: owner and admin always; others only when
  /// they were left on household visibility.
  bool canSeeEveryone(MemberVisibility visibility) =>
      _isManager || visibility == MemberVisibility.household;

  /// Set a person's monthly allowance.
  bool get canSetAllowances => _isManager;

  bool get canTransferOwnership => role == Role.owner;
  bool get canDeleteHousehold => role == Role.owner;

  /// Whether this role may change [target]'s role. Nobody changes their own role or the
  /// owner's; owner and admin can set any other member to admin, editor or view only.
  bool canChangeRoleOf(Role target, {required bool isSelf}) =>
      _isManager && !isSelf && target != Role.owner;

  bool canRemove(Role target, {required bool isSelf}) =>
      _isManager && !isSelf && target != Role.owner;

  /// Anyone but the owner can leave (the owner transfers ownership first).
  bool canLeave({required bool isSelf}) => isSelf && role != Role.owner;
}
