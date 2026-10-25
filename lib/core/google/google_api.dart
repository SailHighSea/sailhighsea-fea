import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'google_auth.dart';

/// The sheet is gone, or it is no longer shared with this account.
class SheetAccessError implements Exception {
  const SheetAccessError(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'The sheet is not available ($statusCode).';
}

/// Google answered with something the app cannot recover from (after the retries).
class GoogleApiError implements Exception {
  const GoogleApiError(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'Google Sheets error $statusCode: $message';
}

/// Google Sheets, reduced to what the app needs. All cell values are text.
abstract interface class SheetsApi {
  /// Creates a spreadsheet with these tabs and returns its id.
  Future<String> createSpreadsheet(String title, List<String> tabs);

  /// Adds a tab to an existing spreadsheet (for sheets made by an older version).
  Future<void> addTab(String sheetId, String tab);

  /// Writes several ranges (`Expenses!A5:J5`) in one request.
  Future<void> writeRanges(
    String sheetId,
    Map<String, List<List<String>>> data,
  );

  /// Appends rows after the last row of the tab.
  Future<void> appendRows(String sheetId, String tab, List<List<String>> rows);

  Future<void> clear(String sheetId, String range);

  /// Rows of a range. Empty trailing cells and rows are not returned.
  Future<List<List<String>>> read(String sheetId, String range);
}

/// Sharing a file this app created with another Google account.
abstract interface class DriveApi {
  Future<void> shareReadOnly(String fileId, String email);

  /// Removes that person's access. Fine if they had none.
  Future<void> unshare(String fileId, String email);
}

/// Retry policy for 429 and 5xx: waits 1, 2, 4, 8 seconds (plus a little jitter), then gives up.
class Backoff {
  Backoff({
    this.maxRetries = 4,
    Future<void> Function(Duration)? sleep,
    Random? random,
  }) : sleep = sleep ?? Future.delayed,
       _random = random ?? Random();

  final int maxRetries;
  final Future<void> Function(Duration) sleep;
  final Random _random;

  Duration delayFor(int attempt) =>
      Duration(milliseconds: (1000 << attempt) + _random.nextInt(250));
}

class HttpGoogleApi implements SheetsApi, DriveApi {
  HttpGoogleApi(this._auth, {http.Client? client, Backoff? backoff})
    : _http = client ?? http.Client(),
      _backoff = backoff ?? Backoff();

  final GoogleAuthService _auth;
  final http.Client _http;
  final Backoff _backoff;

  static const _sheets = 'https://sheets.googleapis.com/v4/spreadsheets';
  static const _drive = 'https://www.googleapis.com/drive/v3/files';

  Future<http.Response> _send(String method, String url, {Object? body}) async {
    for (var attempt = 0; ; attempt++) {
      final token = await _auth.accessToken();
      final req = http.Request(method, Uri.parse(url))
        ..headers['Authorization'] = 'Bearer $token'
        ..headers['Content-Type'] = 'application/json';
      if (body != null) req.body = jsonEncode(body);
      final res = await http.Response.fromStream(await _http.send(req));
      final retryable = res.statusCode == 429 || res.statusCode >= 500;
      if (retryable && attempt < _backoff.maxRetries) {
        await _backoff.sleep(_backoff.delayFor(attempt));
        continue;
      }
      if (res.statusCode == 401) throw const GoogleAuthRevoked();
      if (res.statusCode == 403 || res.statusCode == 404) {
        throw SheetAccessError(res.statusCode);
      }
      if (res.statusCode >= 300) {
        throw GoogleApiError(res.statusCode, _short(res.body));
      }
      return res;
    }
  }

  String _short(String body) =>
      body.length > 200 ? body.substring(0, 200) : body;

  String _enc(String range) => Uri.encodeComponent(range);

  @override
  Future<String> createSpreadsheet(String title, List<String> tabs) async {
    final res = await _send(
      'POST',
      _sheets,
      body: {
        'properties': {'title': title},
        'sheets': [
          for (final t in tabs)
            {
              'properties': {'title': t},
            },
        ],
      },
    );
    return (jsonDecode(res.body) as Map<String, dynamic>)['spreadsheetId']
        as String;
  }

  @override
  Future<void> addTab(String sheetId, String tab) async {
    await _send(
      'POST',
      '$_sheets/$sheetId:batchUpdate',
      body: {
        'requests': [
          {
            'addSheet': {
              'properties': {'title': tab},
            },
          },
        ],
      },
    );
  }

  @override
  Future<void> writeRanges(
    String sheetId,
    Map<String, List<List<String>>> data,
  ) async {
    if (data.isEmpty) return;
    await _send(
      'POST',
      '$_sheets/$sheetId/values:batchUpdate',
      body: {
        'valueInputOption': 'RAW',
        'data': [
          for (final e in data.entries) {'range': e.key, 'values': e.value},
        ],
      },
    );
  }

  @override
  Future<void> appendRows(
    String sheetId,
    String tab,
    List<List<String>> rows,
  ) async {
    if (rows.isEmpty) return;
    await _send(
      'POST',
      '$_sheets/$sheetId/values/${_enc(tab)}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS',
      body: {'values': rows},
    );
  }

  @override
  Future<void> clear(String sheetId, String range) async {
    await _send(
      'POST',
      '$_sheets/$sheetId/values/${_enc(range)}:clear',
      body: const {},
    );
  }

  @override
  Future<List<List<String>>> read(String sheetId, String range) async {
    final res = await _send(
      'GET',
      '$_sheets/$sheetId/values/${_enc(range)}?valueRenderOption=FORMATTED_VALUE&majorDimension=ROWS',
    );
    final values =
        (jsonDecode(res.body) as Map<String, dynamic>)['values'] as List?;
    return [
      for (final row in values ?? const [])
        [for (final c in row as List) c.toString()],
    ];
  }

  @override
  Future<void> shareReadOnly(String fileId, String email) async {
    await _send(
      'POST',
      '$_drive/$fileId/permissions?sendNotificationEmail=false',
      body: {'type': 'user', 'role': 'reader', 'emailAddress': email},
    );
  }

  @override
  Future<void> unshare(String fileId, String email) async {
    final res = await _send(
      'GET',
      '$_drive/$fileId/permissions?fields=${Uri.encodeComponent('permissions(id,emailAddress,role)')}',
    );
    final list =
        (jsonDecode(res.body) as Map<String, dynamic>)['permissions']
            as List? ??
        const [];
    for (final p in list) {
      final m = p as Map<String, dynamic>;
      if ((m['emailAddress'] as String?)?.toLowerCase() ==
              email.toLowerCase() &&
          m['role'] != 'owner') {
        await _send('DELETE', '$_drive/$fileId/permissions/${m['id']}');
      }
    }
  }
}

final sheetsApiProvider = Provider<SheetsApi?>((ref) {
  final auth = ref.watch(googleAuthProvider);
  return auth == null ? null : HttpGoogleApi(auth);
});

final driveApiProvider = Provider<DriveApi?>((ref) {
  final auth = ref.watch(googleAuthProvider);
  return auth == null ? null : HttpGoogleApi(auth);
});
