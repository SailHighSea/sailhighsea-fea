import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Scopes the app asks for. `drive.file` lets the app share the sheet it created; `spreadsheets`
/// lets it read a sheet a family member shared with it.
const googleScopes = [
  'openid',
  'email',
  'profile',
  'https://www.googleapis.com/auth/drive.file',
  'https://www.googleapis.com/auth/spreadsheets',
];

@immutable
class GoogleAccount {
  const GoogleAccount({required this.email, this.name});
  final String email;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is GoogleAccount && other.email == email && other.name == name;
  @override
  int get hashCode => Object.hash(email, name);
}

/// The grant was revoked or has expired: the person has to sign in again ("Reconnect").
class GoogleAuthRevoked implements Exception {
  const GoogleAuthRevoked();
  @override
  String toString() =>
      'Google access was removed or expired. Reconnect to continue.';
}

class GoogleAuthFailure implements Exception {
  const GoogleAuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sign-in with a Google account. One implementation for every platform (a browser sign-in with
/// a loopback redirect and PKCE); the tests use a fake.
abstract interface class GoogleAuthService {
  GoogleAccount? get account;

  /// Emits the account when signed in and `null` when signed out or revoked.
  Stream<GoogleAccount?> get changes;

  Future<void> signIn();
  Future<void> signOut();

  /// A valid access token, refreshed when needed. Throws [GoogleAuthRevoked] when the grant is
  /// gone (and then [changes] emits `null`).
  Future<String> accessToken();
}

/// Where the tokens are kept: the platform's secure store, never Drift, never logs.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String json);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    // macOS: the login keychain, so an app without a provisioning profile (unsigned or ad-hoc
    // builds) can still store the token; the data-protection keychain needs an entitlement.
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _storage;
  static const _key = 'google.tokens';

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String json) => _storage.write(key: _key, value: json);
  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryTokenStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async => value = json;
  @override
  Future<void> clear() async => value = null;
}

/// OAuth client of type "Desktop app" from the Google Cloud console (docs/GOOGLE_SETUP.md).
/// Passed with `--dart-define`; the secret of an installed app is not confidential.
class GoogleOAuthConfig {
  const GoogleOAuthConfig({required this.clientId, this.clientSecret = ''});
  const GoogleOAuthConfig.fromEnvironment()
    : clientId = const String.fromEnvironment('GOOGLE_CLIENT_ID'),
      clientSecret = const String.fromEnvironment('GOOGLE_CLIENT_SECRET');

  final String clientId;
  final String clientSecret;
  bool get isConfigured => clientId.isNotEmpty;
}

// ---- PKCE helpers (pure, tested) -------------------------------------------------------------

String randomUrlSafe(int length, [Random? random]) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final r = random ?? Random.secure();
  return String.fromCharCodes(
    List.generate(length, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
  );
}

String pkceChallenge(String verifier) => base64Url
    .encode(sha256.convert(ascii.encode(verifier)).bytes)
    .replaceAll('=', '');

Uri buildAuthUri({
  required String clientId,
  required String redirectUri,
  required String challenge,
  required String state,
}) => Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
  'client_id': clientId,
  'redirect_uri': redirectUri,
  'response_type': 'code',
  'scope': googleScopes.join(' '),
  'code_challenge': challenge,
  'code_challenge_method': 'S256',
  'state': state,
  // offline + consent so a refresh token is always returned.
  'access_type': 'offline',
  'prompt': 'consent',
});

/// Reads email and name from an id token (a JWT we just received over TLS from Google).
GoogleAccount? accountFromIdToken(String? idToken) {
  if (idToken == null) return null;
  final parts = idToken.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    ) as Map<String, dynamic>;
    final email = payload['email'] as String?;
    if (email == null) return null;
    return GoogleAccount(
      email: email.toLowerCase(),
      name: payload['name'] as String?,
    );
  } catch (_) {
    return null;
  }
}

typedef UrlOpener = Future<bool> Function(Uri url);

class LoopbackGoogleAuth implements GoogleAuthService {
  LoopbackGoogleAuth({
    required this.config,
    required this.store,
    http.Client? client,
    UrlOpener? opener,
    DateTime Function()? clock,
    this.signInTimeout = const Duration(minutes: 5),
  }) : _http = client ?? http.Client(),
       _open =
           opener ??
           ((u) => launchUrl(u, mode: LaunchMode.externalApplication)),
       _clock = clock ?? DateTime.now;

  final GoogleOAuthConfig config;
  final TokenStore store;
  final http.Client _http;
  final UrlOpener _open;
  final DateTime Function() _clock;
  final Duration signInTimeout;

  final _changes = StreamController<GoogleAccount?>.broadcast();
  GoogleAccount? _account;
  String? _access;
  DateTime? _expires;
  bool _loaded = false;

  static final _tokenUri = Uri.https('oauth2.googleapis.com', '/token');

  @override
  GoogleAccount? get account => _account;

  @override
  Stream<GoogleAccount?> get changes async* {
    await _load();
    yield _account;
    yield* _changes.stream;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    final raw = await store.read();
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _account = GoogleAccount(
        email: j['email'] as String,
        name: j['name'] as String?,
      );
    } catch (_) {
      await store.clear();
    }
  }

  void _set(GoogleAccount? a) {
    _account = a;
    _changes.add(a);
  }

  @override
  Future<void> signIn() async {
    if (!config.isConfigured) {
      throw const GoogleAuthFailure(
        'Google sign-in is not set up in this build (see docs/GOOGLE_SETUP.md).',
      );
    }
    final verifier = randomUrlSafe(64);
    final state = randomUrlSafe(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = 'http://127.0.0.1:${server.port}';
      final uri = buildAuthUri(
        clientId: config.clientId,
        redirectUri: redirect,
        challenge: pkceChallenge(verifier),
        state: state,
      );
      // Listen before the browser opens, so a fast redirect is never missed.
      final redirected = _waitForRedirect(server, state);
      redirected.ignore();
      if (!await _open(uri)) {
        throw const GoogleAuthFailure(
          'Could not open the browser for Google sign-in.',
        );
      }
      final params = await redirected;
      final code = params['code'];
      if (code == null) {
        throw GoogleAuthFailure(
          params['error'] == 'access_denied'
              ? 'Google sign-in was cancelled.'
              : 'Google sign-in did not finish.',
        );
      }
      final res = await _http.post(
        _tokenUri,
        body: {
          'client_id': config.clientId,
          if (config.clientSecret.isNotEmpty)
            'client_secret': config.clientSecret,
          'code': code,
          'code_verifier': verifier,
          'grant_type': 'authorization_code',
          'redirect_uri': redirect,
        },
      );
      if (res.statusCode != 200) {
        throw const GoogleAuthFailure(
          'Google did not accept the sign-in. Try again.',
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final account = accountFromIdToken(body['id_token'] as String?);
      final refresh = body['refresh_token'] as String?;
      if (account == null || refresh == null) {
        throw const GoogleAuthFailure(
          'Google did not return what the app needs. Try again.',
        );
      }
      _access = body['access_token'] as String;
      _expires = _clock().add(
        Duration(seconds: (body['expires_in'] as num?)?.toInt() ?? 3600),
      );
      await store.write(
        jsonEncode({
          'email': account.email,
          'name': account.name,
          'refresh': refresh,
        }),
      );
      _loaded = true;
      _set(account);
    } finally {
      await server.close(force: true);
    }
  }

  Future<Map<String, String>> _waitForRedirect(
    HttpServer server,
    String state,
  ) async {
    final done = Completer<Map<String, String>>();
    final sub = server.listen((req) async {
      final q = req.uri.queryParameters;
      final ok =
          q['state'] == state &&
          (q.containsKey('code') || q.containsKey('error'));
      req.response
        ..statusCode = ok ? 200 : 400
        ..headers.contentType = ContentType.html
        ..write(
          ok
              ? '<html><body style="font-family:sans-serif"><h3>Signed in</h3><p>You can close this tab and go back to FET Family Expenses Tracker.</p></body></html>'
              : '<html><body>Not expected.</body></html>',
        );
      await req.response.close();
      if (ok && !done.isCompleted) done.complete(q);
    });
    try {
      return await done.future.timeout(
        signInTimeout,
        onTimeout: () =>
            throw const GoogleAuthFailure('Google sign-in timed out.'),
      );
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<String> accessToken() async {
    await _load();
    final now = _clock();
    if (_access != null &&
        _expires != null &&
        now.isBefore(_expires!.subtract(const Duration(minutes: 1)))) {
      return _access!;
    }
    final raw = await store.read();
    if (raw == null) {
      _set(null);
      throw const GoogleAuthRevoked();
    }
    final refresh =
        (jsonDecode(raw) as Map<String, dynamic>)['refresh'] as String?;
    if (refresh == null) {
      await signOut();
      throw const GoogleAuthRevoked();
    }
    final http.Response res;
    try {
      res = await _http.post(
        _tokenUri,
        body: {
          'client_id': config.clientId,
          if (config.clientSecret.isNotEmpty)
            'client_secret': config.clientSecret,
          'refresh_token': refresh,
          'grant_type': 'refresh_token',
        },
      );
    } on SocketException {
      rethrow; // offline: not a revoked grant
    }
    if (res.statusCode == 400 || res.statusCode == 401) {
      // invalid_grant: revoked, password changed, or a Testing-mode token older than 7 days.
      await signOut();
      throw const GoogleAuthRevoked();
    }
    if (res.statusCode != 200) {
      throw GoogleAuthFailure('Google is not available (${res.statusCode}).');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    _access = body['access_token'] as String;
    _expires = now.add(
      Duration(seconds: (body['expires_in'] as num?)?.toInt() ?? 3600),
    );
    return _access!;
  }

  @override
  Future<void> signOut() async {
    _access = null;
    _expires = null;
    await store.clear();
    _set(null);
  }
}

/// `null` unless the build runs in Sheets mode (`BACKEND=sheets`); `main()` and tests override it.
final googleAuthProvider = Provider<GoogleAuthService?>((ref) => null);

final googleAccountProvider = StreamProvider<GoogleAccount?>((ref) {
  final auth = ref.watch(googleAuthProvider);
  if (auth == null) return Stream.value(null);
  return auth.changes;
});
