import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/window_class.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/appearance_provider.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/pill_button.dart';
import '../family/data/household_remote.dart';
import '../family/member_providers.dart';
import 'auth_providers.dart';

/// First sign-in: name the household and become its owner, or join one with a code.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  late final TextEditingController _household;
  late final TextEditingController _name;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authServiceProvider)?.currentUser;
    final first = user?.nameOrEmail ?? '';
    _name = TextEditingController(text: first);
    _household = TextEditingController(
      text: first.isEmpty ? 'Our household' : '$first\'s household',
    );
  }

  @override
  void dispose() {
    _household.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_busy) return;
    if (_household.text.trim().isEmpty || _name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a household name and your name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(householdControllerProvider)
          .createHousehold(
            name: _household.text,
            displayName: _name.text,
            currency: ref.read(appearanceProvider).currencyCode,
          );
    } on HouseholdFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final metrics = context.layout;
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
                      'Set up your household',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: t.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You will be the owner. Invite family afterwards and choose what each person can do.',
                    style: TextStyle(fontSize: 15, height: 1.4, color: t.muted),
                  ),
                  const SizedBox(height: 24),
                  AppTextField(
                    key: const ValueKey('welcome-household'),
                    label: 'Household name',
                    controller: _household,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    key: const ValueKey('welcome-name'),
                    label: 'Your name',
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.words,
                    onSubmitted: (_) => _create(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        key: const ValueKey('welcome-error'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: t.rose,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  PillButton(
                    key: const ValueKey('welcome-create'),
                    label: 'Create household',
                    busy: _busy,
                    onTap: _create,
                  ),
                  const SizedBox(height: 4),
                  PillButton(
                    key: const ValueKey('welcome-join'),
                    label: 'Have a code? Join a household',
                    style: PillStyle.outlined,
                    onTap: () => context.push('/join'),
                  ),
                  PillButton(
                    key: const ValueKey('welcome-sign-out'),
                    label: 'Sign out',
                    style: PillStyle.text,
                    onTap: () => ref.read(authServiceProvider)!.signOut(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
