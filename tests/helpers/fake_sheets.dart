import 'package:family_expenses/features/integrations/data/sheets_remote.dart';

/// Stands in for the server side of the Google Sheet connection.
class FakeSheetsRemote implements SheetsRemote {
  FakeSheetsRemote({this.status = const SheetStatus.none()});

  SheetStatus status;
  final List<String> calls = [];

  /// Make the next call fail.
  SheetsError? failNextWith;

  void _maybeFail() {
    final e = failNextWith;
    if (e != null) {
      failNextWith = null;
      throw SheetsFailure(e);
    }
  }

  @override
  Future<SheetStatus> fetchStatus(String householdId) async {
    calls.add('status:$householdId');
    _maybeFail();
    return status;
  }

  @override
  Future<Uri> startConnect(String householdId) async {
    calls.add('start:$householdId');
    _maybeFail();
    return Uri.parse('https://accounts.google.com/o/oauth2/v2/auth?state=s1');
  }

  @override
  Future<void> syncNow(String householdId) async {
    calls.add('sync:$householdId');
    _maybeFail();
  }

  @override
  Future<void> disconnect(String householdId) async {
    calls.add('disconnect:$householdId');
    _maybeFail();
    status = const SheetStatus.none();
  }
}
