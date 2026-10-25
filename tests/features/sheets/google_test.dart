import 'dart:convert';
import 'dart:io';

import 'package:family_expenses/core/google/google_api.dart';
import 'package:family_expenses/core/google/google_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _idToken(Map<String, Object?> claims) {
  String b(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${b({'alg': 'none'})}.${b(claims)}.sig';
}

void main() {
  group('PKCE and sign-in', () {
    test('the challenge matches the RFC 7636 example', () {
      expect(
        pkceChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('verifiers are long, from the allowed alphabet and never repeat', () {
      final a = randomUrlSafe(64), b = randomUrlSafe(64);
      expect(a.length, 64);
      expect(a, isNot(b));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(a), isTrue);
    });

    test(
      'the sign-in address asks for the scopes, offline access and S256',
      () {
        final u = buildAuthUri(
          clientId: 'cid',
          redirectUri: 'http://127.0.0.1:1234',
          challenge: 'ch',
          state: 'st',
        );
        expect(u.host, 'accounts.google.com');
        expect(u.queryParameters['code_challenge_method'], 'S256');
        expect(u.queryParameters['access_type'], 'offline');
        expect(u.queryParameters['scope'], contains('auth/spreadsheets'));
        expect(u.queryParameters['scope'], contains('auth/drive.file'));
        expect(
          u.queryParameters['scope'],
          isNot(contains('auth/drive ')),
          reason: 'not the whole Drive',
        );
        expect(
          u.queryParameters['redirect_uri'],
          startsWith('http://127.0.0.1:'),
        );
      },
    );

    test('email and name are read from the id token', () {
      expect(
        accountFromIdToken(
          _idToken({'email': 'Dad@Family.Test', 'name': 'Dad'}),
        ),
        const GoogleAccount(email: 'dad@family.test', name: 'Dad'),
      );
      expect(accountFromIdToken('nonsense'), isNull);
      expect(accountFromIdToken(null), isNull);
    });

    test('not configured: a plain message, nothing opened', () async {
      var opened = false;
      final auth = LoopbackGoogleAuth(
        config: const GoogleOAuthConfig(clientId: ''),
        store: MemoryTokenStore(),
        opener: (_) async => opened = true,
      );
      await expectLater(auth.signIn(), throwsA(isA<GoogleAuthFailure>()));
      expect(opened, isFalse);
    });

    test('full browser flow: loopback redirect, code exchange, tokens kept only in the store', () async {
      final store = MemoryTokenStore();
      late Map<String, String> tokenRequest;
      final client = MockClient((req) async {
        tokenRequest = req.bodyFields;
        return http.Response(
          jsonEncode({
            'access_token': 'ACCESS-1',
            'refresh_token': 'REFRESH-1',
            'expires_in': 3600,
            'id_token': _idToken({'email': 'maya@family.test', 'name': 'Maya'}),
          }),
          200,
        );
      });
      final auth = LoopbackGoogleAuth(
        config: const GoogleOAuthConfig(clientId: 'cid', clientSecret: 'sec'),
        store: store,
        client: client,
        opener: (uri) async {
          // The "browser": Google redirects back to the loopback address with a code.
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          final state = uri.queryParameters['state']!;
          final c = HttpClient();
          final req = await c.getUrl(
            redirect.replace(
              queryParameters: {'code': 'the-code', 'state': state},
            ),
          );
          final res = await req.close();
          await res.drain<void>();
          c.close();
          return true;
        },
      );
      await auth.signIn();
      expect(
        auth.account,
        const GoogleAccount(email: 'maya@family.test', name: 'Maya'),
      );
      expect(tokenRequest['grant_type'], 'authorization_code');
      expect(tokenRequest['code'], 'the-code');
      expect(tokenRequest['code_verifier'], hasLength(64));
      expect(await auth.accessToken(), 'ACCESS-1');
      // The refresh token is in the secure store, and nowhere else.
      expect(await store.read(), contains('REFRESH-1'));
    });

    test(
      'a redirect with the wrong state is ignored (no code is accepted)',
      () async {
        final auth = LoopbackGoogleAuth(
          config: const GoogleOAuthConfig(clientId: 'cid'),
          store: MemoryTokenStore(),
          client: MockClient((_) async => http.Response('{}', 500)),
          signInTimeout: const Duration(milliseconds: 400),
          opener: (uri) async {
            final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
            final c = HttpClient();
            final req = await c.getUrl(
              redirect.replace(
                queryParameters: {'code': 'evil', 'state': 'WRONG'},
              ),
            );
            final res = await req.close();
            await res.drain<void>();
            c.close();
            return true;
          },
        );
        await expectLater(auth.signIn(), throwsA(isA<GoogleAuthFailure>()));
        expect(auth.account, isNull);
      },
    );

    test('cancelling in the browser gives a clear message', () async {
      final auth = LoopbackGoogleAuth(
        config: const GoogleOAuthConfig(clientId: 'cid'),
        store: MemoryTokenStore(),
        opener: (uri) async {
          final redirect = Uri.parse(uri.queryParameters['redirect_uri']!);
          final c = HttpClient();
          final req = await c.getUrl(
            redirect.replace(
              queryParameters: {
                'error': 'access_denied',
                'state': uri.queryParameters['state']!,
              },
            ),
          );
          await (await req.close()).drain<void>();
          c.close();
          return true;
        },
      );
      await expectLater(
        auth.signIn(),
        throwsA(
          isA<GoogleAuthFailure>().having(
            (e) => e.message,
            'm',
            contains('cancelled'),
          ),
        ),
      );
    });

    test(
      'the token is refreshed when it expires; a revoked grant means Reconnect',
      () async {
        var now = DateTime(2026, 10, 23, 12);
        var refreshes = 0;
        var revoke = false;
        final store = MemoryTokenStore()
          ..value = jsonEncode({'email': 'maya@family.test', 'refresh': 'R'});
        final auth = LoopbackGoogleAuth(
          config: const GoogleOAuthConfig(clientId: 'cid'),
          store: store,
          clock: () => now,
          client: MockClient((req) async {
            refreshes++;
            if (revoke) {
              return http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
            }
            return http.Response(
              jsonEncode({'access_token': 'A$refreshes', 'expires_in': 3600}),
              200,
            );
          }),
        );
        expect(await auth.accessToken(), 'A1');
        expect(await auth.accessToken(), 'A1', reason: 'still valid');
        now = now.add(const Duration(minutes: 59, seconds: 30));
        expect(await auth.accessToken(), 'A2');
        expect(refreshes, 2);

        now = now.add(const Duration(hours: 2));
        revoke = true;
        final seen = <GoogleAccount?>[];
        final sub = auth.changes.listen(seen.add);
        await expectLater(
          auth.accessToken(),
          throwsA(isA<GoogleAuthRevoked>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(auth.account, isNull);
        expect(await store.read(), isNull, reason: 'tokens are removed');
        await sub.cancel();
      },
    );

    test('signing out removes the stored tokens', () async {
      final store = MemoryTokenStore()
        ..value = '{"email":"a@b.test","refresh":"R"}';
      final auth = LoopbackGoogleAuth(
        config: const GoogleOAuthConfig(clientId: 'c'),
        store: store,
      );
      await auth.signOut();
      expect(await store.read(), isNull);
    });
  });

  group('Sheets and Drive over HTTP', () {
    _FakeAuth auth() => _FakeAuth();

    test(
      '429 and 5xx are retried with growing waits, then it succeeds',
      () async {
        final waits = <Duration>[];
        var calls = 0;
        final api = HttpGoogleApi(
          auth(),
          backoff: Backoff(sleep: (d) async => waits.add(d)),
          client: MockClient((req) async {
            calls++;
            if (calls <= 3) {
              return http.Response('slow down', calls == 1 ? 429 : 503);
            }
            return http.Response(
              jsonEncode({
                'values': [
                  ['a', 'b'],
                  ['c'],
                ],
              }),
              200,
            );
          }),
        );
        final rows = await api.read('sheet', 'Expenses!A2:K');
        expect(rows, [
          ['a', 'b'],
          ['c'],
        ]);
        expect(calls, 4);
        expect(waits.map((d) => d.inSeconds), [1, 2, 4]);
      },
    );

    test('it gives up after the retries and says so', () async {
      var calls = 0;
      final api = HttpGoogleApi(
        auth(),
        backoff: Backoff(maxRetries: 2, sleep: (_) async {}),
        client: MockClient((req) async {
          calls++;
          return http.Response('x' * 500, 500);
        }),
      );
      await expectLater(
        api.read('s', 'A1'),
        throwsA(
          isA<GoogleApiError>().having(
            (e) => e.message.length,
            'trimmed',
            lessThanOrEqualTo(200),
          ),
        ),
      );
      expect(calls, 3);
    });

    test(
      '403 and 404 mean the sheet is not available; 401 means reconnect',
      () async {
        HttpGoogleApi api(int code) => HttpGoogleApi(
          auth(),
          client: MockClient((_) async => http.Response('', code)),
        );
        await expectLater(
          api(404).read('s', 'A1'),
          throwsA(isA<SheetAccessError>()),
        );
        await expectLater(
          api(403).read('s', 'A1'),
          throwsA(isA<SheetAccessError>()),
        );
        await expectLater(
          api(401).read('s', 'A1'),
          throwsA(isA<GoogleAuthRevoked>()),
        );
      },
    );

    test('requests carry the bearer token and the right bodies', () async {
      final seen = <http.Request>[];
      final api = HttpGoogleApi(
        auth(),
        client: MockClient((req) async {
          seen.add(req);
          if (req.url.path.endsWith('/spreadsheets')) {
            return http.Response(jsonEncode({'spreadsheetId': 'NEW'}), 200);
          }
          if (req.url.path.endsWith('/permissions') && req.method == 'GET') {
            return http.Response(
              jsonEncode({
                'permissions': [
                  {
                    'id': 'p1',
                    'emailAddress': 'dad@family.test',
                    'role': 'reader',
                  },
                  {
                    'id': 'p2',
                    'emailAddress': 'maya@family.test',
                    'role': 'owner',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      expect(await api.createSpreadsheet('T', ['Expenses', 'Meta']), 'NEW');
      await api.writeRanges('NEW', {
        'Expenses!A1:B1': [
          ['a', 'b'],
        ],
      });
      await api.appendRows('NEW', 'Expenses', [
        ['x'],
      ]);
      await api.shareReadOnly('NEW', 'dad@family.test');
      await api.unshare('NEW', 'Dad@Family.test');
      expect(
        seen.every((r) => r.headers['Authorization'] == 'Bearer fake'),
        isTrue,
      );
      final create = jsonDecode(seen[0].body) as Map<String, dynamic>;
      expect((create['sheets'] as List).length, 2);
      final write = jsonDecode(seen[1].body) as Map<String, dynamic>;
      expect(write['valueInputOption'], 'RAW');
      final share = jsonDecode(seen[3].body) as Map<String, dynamic>;
      expect(share, {
        'type': 'user',
        'role': 'reader',
        'emailAddress': 'dad@family.test',
      });
      expect(seen[3].url.queryParameters['sendNotificationEmail'], 'false');
      // Only the reader is removed, never the owner.
      final deletes = seen.where((r) => r.method == 'DELETE').toList();
      expect(deletes.map((r) => r.url.pathSegments.last), ['p1']);
    });
  });
}

class _FakeAuth implements GoogleAuthService {
  @override
  Future<String> accessToken() async => 'fake';
  @override
  GoogleAccount? get account => null;
  @override
  Stream<GoogleAccount?> get changes => const Stream.empty();
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
}
