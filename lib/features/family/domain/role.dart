/// A member's role in the household (PLAN.md "Roles"). The server stores the same four
/// values in the `member_role` enum.
enum Role {
  owner('owner', 'Owner', 'Household owner'),
  admin(
    'admin',
    'Admin',
    'Full access, except removing the owner or deleting the household',
  ),
  editor('editor', 'Can edit', 'Add and change expenses'),
  viewer('viewer', 'View only', 'See everything, change nothing');

  const Role(this.dbValue, this.label, this.description);

  final String dbValue;
  final String label;
  final String description;

  static Role fromDb(String value) => Role.values.firstWhere(
    (r) => r.dbValue == value,
    // An unknown role from a newer server version gets the least access.
    orElse: () => Role.viewer,
  );

  /// Roles that can be handed out to other people. Owner is only reached by transfer.
  static const assignable = [Role.admin, Role.editor, Role.viewer];

  /// Roles an invite code can carry.
  static const invitable = [Role.editor, Role.viewer];
}
