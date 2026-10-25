/// What a member sees of other people's spending. The server stores the same two values in
/// the `member_visibility` enum and enforces them in the expenses select policy.
enum MemberVisibility {
  household('household', "Everyone's spending", 'Sees what every member spent'),
  own('own', 'Only their own', 'Sees only the expenses they added');

  const MemberVisibility(this.dbValue, this.label, this.description);

  final String dbValue;
  final String label;
  final String description;

  static MemberVisibility fromDb(String? value) => values.firstWhere(
    (v) => v.dbValue == value,
    orElse: () => MemberVisibility.household,
  );
}
