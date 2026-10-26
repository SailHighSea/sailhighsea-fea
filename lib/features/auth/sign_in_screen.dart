import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/window_class.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/segmented_pills.dart';
import 'auth_providers.dart';
import 'auth_service.dart';

/// Which "Continue with ..." buttons this platform offers. Apple is for Apple platforms;
/// Google works wherever the browser can return to the app. Everyone can use email.
final oauthProvidersProvider = Provider<List<OAuthProviderKind>>((ref) {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => const [
      OAuthProviderKind.google,
      OAuthProviderKind.apple,
    ],
    TargetPlatform.android => const [OAuthProviderKind.google],
    _ => const [],
  };
});

enum _Step { password, code }

/// Sign in or create an account with email and password, an emailed one-time code, or
/// Google / Apple where the platform allows. Centred and capped in width, so it reads the
/// same on a phone, a tablet and a desktop window.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _creating = false;
  _Step _step = _Step.password;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  AuthService get _auth => ref.read(authServiceProvider)!;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _emailOk => _email.text.contains('@') && _email.text.length > 3;

  Future<void> _submitPassword() => _run(() async {
    if (!_emailOk) throw const AuthFailure('Enter your email address.');
    if (_password.text.isEmpty) {
      throw const AuthFailure('Enter your password.');
    }
    if (_creating) {
      if (_password.text.length < 8) {
        throw const AuthFailure('Use at least 8 characters for the password.');
      }
      final signedIn = await _auth.signUpWithPassword(
        _email.text,
        _password.text,
      );
      if (!signedIn && mounted) {
        setState(
          () =>
              _info = 'Check your email to confirm your account, then sign in.',
        );
        _creating = false;
      }
    } else {
      await _auth.signInWithPassword(_email.text, _password.text);
    }
  });

  Future<void> _sendCode() => _run(() async {
    if (!_emailOk) throw const AuthFailure('Enter your email address.');
    await _auth.sendEmailCode(_email.text);
    if (mounted) {
      setState(() {
        _step = _Step.code;
        _code.clear();
        _info = 'We emailed a code to ${_email.text.trim()}.';
      });
    }
  });

  Future<void> _verifyCode() => _run(() async {
    if (_code.text.trim().length < 6) {
      throw const AuthFailure('Enter the code from the email.');
    }
    await _auth.verifyEmailCode(_email.text, _code.text);
  });

  Future<void> _oauth(OAuthProviderKind kind) =>
      _run(() => _auth.signInWithOAuth(kind));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final metrics = context.layout;
    final providers = ref.watch(oauthProvidersProvider);
    final codeStep = _step == _Step.code;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: metrics.pagePadding,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      kAppName,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    codeStep
                        ? 'Enter the code'
                        : 'Track your household spending together.',
                    style: TextStyle(fontSize: 15, color: t.muted),
                  ),
                  const SizedBox(height: 24),
                  if (codeStep)
                    ..._codeStep(t)
                  else
                    ..._passwordStep(t, providers),
                  if (_info != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _info!,
                      key: const ValueKey('auth-info'),
                      style: TextStyle(fontSize: 14, color: t.muted),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        key: const ValueKey('auth-error'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.rose,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _passwordStep(AppTokens t, List<OAuthProviderKind> providers) {
    return [
      SegmentedPills(
        labels: const ['Sign in', 'Create account'],
        selected: _creating ? 1 : 0,
        onChanged: (i) => setState(() {
          _creating = i == 1;
          _error = null;
          _info = null;
        }),
      ),
      const SizedBox(height: 16),
      AppTextField(
        key: const ValueKey('auth-email'),
        label: 'Email',
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.email],
      ),
      const SizedBox(height: 12),
      AppTextField(
        key: const ValueKey('auth-password'),
        label: 'Password',
        controller: _password,
        obscure: true,
        textInputAction: TextInputAction.done,
        autofillHints: [
          _creating ? AutofillHints.newPassword : AutofillHints.password,
        ],
        onSubmitted: (_) => _submitPassword(),
      ),
      const SizedBox(height: 16),
      PillButton(
        key: const ValueKey('auth-submit'),
        label: _creating ? 'Create account' : 'Sign in',
        busy: _busy,
        onTap: _submitPassword,
      ),
      const SizedBox(height: 4),
      PillButton(
        key: const ValueKey('auth-email-code'),
        label: 'Email me a code instead',
        style: PillStyle.text,
        onTap: _busy ? null : _sendCode,
      ),
      if (providers.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Divider(color: t.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(color: t.muted)),
            ),
            Expanded(child: Divider(color: t.border)),
          ],
        ),
        const SizedBox(height: 8),
        for (final kind in providers) ...[
          PillButton(
            key: ValueKey('auth-${kind.name}'),
            label: switch (kind) {
              OAuthProviderKind.google => 'Continue with Google',
              OAuthProviderKind.apple => 'Continue with Apple',
            },
            style: PillStyle.outlined,
            onTap: _busy ? null : () => _oauth(kind),
          ),
          const SizedBox(height: 10),
        ],
      ],
    ];
  }

  List<Widget> _codeStep(AppTokens t) {
    return [
      AppTextField(
        key: const ValueKey('auth-code'),
        label: 'Code from the email',
        controller: _code,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        autofillHints: const [AutofillHints.oneTimeCode],
        autofocus: true,
        onSubmitted: (_) => _verifyCode(),
      ),
      const SizedBox(height: 16),
      PillButton(
        key: const ValueKey('auth-verify'),
        label: 'Verify and sign in',
        busy: _busy,
        onTap: _verifyCode,
      ),
      const SizedBox(height: 4),
      PillButton(
        key: const ValueKey('auth-code-back'),
        label: 'Use a password instead',
        style: PillStyle.text,
        onTap: () => setState(() {
          _step = _Step.password;
          _error = null;
          _info = null;
        }),
      ),
    ];
  }
}
