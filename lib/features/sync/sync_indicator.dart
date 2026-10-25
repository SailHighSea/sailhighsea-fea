import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/layout/adaptive_sheet.dart';
import '../../core/sync/sync_status.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/pill_button.dart';
import 'sync_providers.dart';

/// Synced, syncing or offline, in the shell on every size. Tap for details, the changes the
/// server refused, and "Sync now". Draws nothing when the app is local-only.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key, this.dense = false});

  /// One short word (for the 96px rail) instead of the full label.
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider).value;
    if (status == null) return const SizedBox.shrink();
    final t = context.tokens;
    final color = _colorFor(t, status);
    final text = dense ? _shortLabel(status) : _fullLabel(status);
    return Semantics(
      button: true,
      label: 'Sync status: ${_fullLabel(status)}. Tap for details.',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('sync-indicator'),
        borderRadius: BorderRadius.circular(22),
        onTap: () => showSyncSheet(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(status: status, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _fullLabel(SyncStatus s) =>
    s.issues > 0 && s.phase == SyncPhase.synced ? 'Not all saved' : s.label;

String _shortLabel(SyncStatus s) {
  if (s.issues > 0 && s.phase == SyncPhase.synced) return 'Check';
  return switch (s.phase) {
    SyncPhase.synced => 'Synced',
    SyncPhase.syncing => 'Syncing',
    SyncPhase.offline => 'Offline',
    SyncPhase.error => 'Problem',
  };
}

Color _colorFor(AppTokens t, SyncStatus s) {
  if (s.issues > 0 && s.phase == SyncPhase.synced) return t.amberText;
  return switch (s.phase) {
    SyncPhase.synced => t.primary,
    SyncPhase.syncing => t.muted,
    SyncPhase.offline => t.amberText,
    SyncPhase.error => t.rose,
  };
}

class _Dot extends StatelessWidget {
  const _Dot({required this.status, required this.color});

  final SyncStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (status.phase == SyncPhase.syncing) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

Future<void> showSyncSheet(BuildContext context) =>
    showAdaptiveSheet<void>(context, builder: (_) => const _SyncSheet());

class _SyncSheet extends ConsumerWidget {
  const _SyncSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.tokens;
    final status = ref.watch(syncStatusProvider).value;
    final issues = ref.watch(syncIssuesProvider).value ?? const [];
    final engine = ref.watch(syncEngineProvider);
    if (status == null || engine == null) return const SizedBox.shrink();
    final last = status.lastSyncedAt;
    return Column(
      key: const ValueKey('sync-sheet'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            _fullLabel(status),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: t.text,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(switch (status.phase) {
          SyncPhase.offline => 'No connection. Your changes are saved on this device and will be sent when you are back online.',
          SyncPhase.error => 'The server did not answer properly. Your changes are safe on this device and we will try again.',
          SyncPhase.syncing =>
            status.initial
                ? 'Downloading your household for the first time.'
                : 'Sending and receiving changes.',
          SyncPhase.synced => 'Everything on this device is on the server and the other way round.',
        }, style: TextStyle(fontSize: 14, color: t.muted, height: 1.4)),
        const SizedBox(height: 12),
        if (status.pending > 0)
          Text(
            status.pending == 1
                ? '1 change waiting to be sent.'
                : '${status.pending} changes waiting to be sent.',
            style: TextStyle(fontSize: 14, color: t.text),
          ),
        if (last != null)
          Text(
            'Last synced ${DateFormat('MMM d, HH:mm', 'en_US').format(last)}.',
            style: TextStyle(fontSize: 14, color: t.muted),
          ),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Not saved',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: t.amberText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your role changed while you were away, so the server did not accept these. '
            'Ask an owner or admin if you need edit access.',
            style: TextStyle(fontSize: 14, color: t.muted, height: 1.4),
          ),
          const SizedBox(height: 8),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                issue.summary,
                style: TextStyle(fontSize: 14, color: t.text),
              ),
            ),
        ],
        const SizedBox(height: 16),
        PillButton(
          label: 'Sync now',
          style: PillStyle.outlined,
          busy: status.phase == SyncPhase.syncing,
          onTap: engine.syncNow,
        ),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          PillButton(
            label: 'Dismiss',
            style: PillStyle.text,
            onTap: engine.dismissIssues,
          ),
        ],
      ],
    );
  }
}
