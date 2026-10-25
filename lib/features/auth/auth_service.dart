/// The signed-in person.
class AuthUser {
  const AuthUser({required this.id, this.email, this.displayName});

  final String id;
  final String? email;
  final String? displayName;

  /// A name to show and to use as the household display name when none was typed.
  String get nameOrEmail {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final mail = email ?? '';
    final at = mail.indexOf('@');
    return at > 0 ? mail.substring(0, at) : 'Me';
  }

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.email == email &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(id, email, displayName);
}

enum OAuthProviderKind { google, apple }

/// A sign-in problem with a message that is safe to show.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sign-in operations. The Supabase implementation is in `supabase_auth_service.dart`;
/// tests use a fake.
abstract class AuthService {
  AuthUser? get currentUser;

  /// Emits the user on sign-in and `null` on sign-out. Emits the current state first.
  Stream<AuthUser?> get changes;

  Future<void> signInWithPassword(String email, String password);

  /// Creates the account. Returns `true` when the person is signed in straight away and
  /// `false` when the project asks them to confirm their email first.
  Future<bool> signUpWithPassword(String email, String password);

  /// Emails a one-time code (and link). Works on every platform without deep links.
  Future<void> sendEmailCode(String email);

  Future<void> verifyEmailCode(String email, String code);

  /// Opens the provider's sign-in in the browser; the session arrives through [changes].
  Future<void> signInWithOAuth(OAuthProviderKind provider);

  Future<void> signOut();
}
