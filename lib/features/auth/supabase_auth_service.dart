import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../core/supabase/supabase_config.dart';
import 'auth_service.dart';

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._auth);

  final sb.GoTrueClient _auth;

  static AuthUser? _map(sb.User? user) => user == null
      ? null
      : AuthUser(
          id: user.id,
          email: user.email,
          displayName:
              (user.userMetadata?['full_name'] ?? user.userMetadata?['name'])
                  as String?,
        );

  @override
  AuthUser? get currentUser => _map(_auth.currentUser);

  @override
  Stream<AuthUser?> get changes async* {
    yield currentUser;
    // Token refreshes and similar events repeat the same user; only changes matter.
    AuthUser? last = currentUser;
    await for (final event in _auth.onAuthStateChange) {
      final next = _map(event.session?.user);
      if (next != last) {
        last = next;
        yield next;
      }
    }
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on sb.AuthException catch (e) {
      throw AuthFailure(_friendly(e));
    } catch (_) {
      throw const AuthFailure(
        'Could not reach the server. Check your connection and try again.',
      );
    }
  }

  String _friendly(sb.AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('invalid login')) {
      return 'That email and password do not match.';
    }
    if (message.contains('already registered')) {
      return 'An account with that email already exists. Try signing in.';
    }
    if (message.contains('token') && message.contains('expired') ||
        message.contains('invalid') && message.contains('otp')) {
      return 'That code is wrong or has expired.';
    }
    if (message.contains('rate limit')) {
      return 'Too many tries. Wait a minute and try again.';
    }
    if (message.contains('password')) return e.message;
    return 'Could not sign in. Please try again.';
  }

  @override
  Future<void> signInWithPassword(String email, String password) => _guard(
    () => _auth.signInWithPassword(email: email.trim(), password: password),
  );

  @override
  Future<bool> signUpWithPassword(String email, String password) =>
      _guard(() async {
        final response = await _auth.signUp(
          email: email.trim(),
          password: password,
          emailRedirectTo: authRedirectUrl,
        );
        return response.session != null;
      });

  @override
  Future<void> sendEmailCode(String email) => _guard(
    () => _auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: authRedirectUrl,
    ),
  );

  @override
  Future<void> verifyEmailCode(String email, String code) => _guard(
    () => _auth.verifyOTP(
      email: email.trim(),
      token: code.trim(),
      type: sb.OtpType.email,
    ),
  );

  @override
  Future<void> signInWithOAuth(OAuthProviderKind provider) => _guard(
    () => _auth.signInWithOAuth(switch (provider) {
      OAuthProviderKind.google => sb.OAuthProvider.google,
      OAuthProviderKind.apple => sb.OAuthProvider.apple,
    }, redirectTo: authRedirectUrl),
  );

  @override
  Future<void> signOut() => _guard(_auth.signOut);
}
