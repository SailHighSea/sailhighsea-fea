import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/layout/window_class.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/pill_button.dart';
import 'data/household_remote.dart';
import 'invite_code_input.dart';
import 'member_providers.dart';

/// "Join a household" (Join mockup). Same screen on every size: full width with the button
/// pinned at the bottom on the phone, a centred card on wider windows.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  bool get _complete => cleanInviteCode(_code.text).length == inviteCodeLength;

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _join() async {
    if (!_complete || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(householdControllerProvider)
          .join(cleanInviteCode(_code.text));
      if (mounted) context.go('/home');
    } on HouseholdFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final compact = context.layout.isCompact;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Join a household',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter the code shared by the household owner. You\'ll get the access they '
          'chose for you, either view only or edit.',
          style: TextStyle(fontSize: 15, height: 1.4, color: t.muted),
        ),
        const SizedBox(height: 20),
        AppTextField(
          key: const ValueKey('join-code'),
          label: 'Invite code',
          controller: _code,
          big: true,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: const [InviteCodeFormatter()],
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: t.navActiveBackground,
            borderRadius: BorderRadius.circular(AppRadii.smallCard),
          ),
          child: Text(
            'Codes work once and expire after 24 hours. Ask the owner for a new one if '
            'yours has expired.',
            style: TextStyle(fontSize: 14, height: 1.4, color: t.navActiveText),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              key: const ValueKey('join-error'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.rose,
              ),
            ),
          ),
        ],
      ],
    );
    final button = PillButton(
      key: const ValueKey('join-submit'),
      label: 'Join household',
      busy: _busy,
      onTap: _complete ? _join : null,
    );

    final metrics = context.layout;
    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                metrics.pagePadding.left,
                16,
                metrics.pagePadding.right,
                24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      button: true,
                      label: 'Back',
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: _back,
                        radius: 24,
                        child: SizedBox(
                          width: kMinTapTarget,
                          height: kMinTapTarget,
                          child: Icon(
                            Icons.chevron_left_rounded,
                            size: 30,
                            color: t.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: SingleChildScrollView(child: body)),
                  const SizedBox(height: 12),
                  button,
                  if (!compact) const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
