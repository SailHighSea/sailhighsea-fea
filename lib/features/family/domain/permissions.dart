import 'role.dart';

/// What a role may do. This mirrors the Row Level Security policies in
/// `supabase/migrations` and exists only to hide buttons the server would reject anyway
/// (rule 6: the server is the authority). If a rule changes, change the SQL first.
class Permissions {
  const Permissions(this.role);

  final Role role;

  /// Used before sign-in and when Supabase is not configured: one person, everything allowed.
  static const local = Permissions(Role.owner);

  bool get _isManager => role == Role.owner || role == Role.admin;

  /// Add, edit and delete expenses.
  bool get canWriteExpenses => _isManager || role == Role.editor;

  /// Categories, budgets, goals and bills (PLAN.md open decision 2).
  bool get canManageCategories => _isManager;
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
