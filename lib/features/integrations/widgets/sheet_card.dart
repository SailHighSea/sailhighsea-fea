import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/surface_card.dart';
import '../../family/member_providers.dart';
import '../data/sheets_remote.dart';
import '../sheets_providers.dart';

/// "Google Sheet": mirrors every expense into a Sheet owned by the household owner. One
/// implementation for every size. Only the owner connects or disconnects; owner and admins
/// can open the Sheet and press Sync now; everyone else just sees the state.
class SheetCard extends ConsumerStatefulWidget {
  const SheetCard({super.key});

  @override
  ConsumerState<SheetCard> createState() => _SheetCardState();
}

class _SheetCardState extends ConsumerState<SheetCard> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on SheetsFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('sheet-privacy'),
        title: const Text('Send expenses to Google?'),
        content: const Text(
          'Connecting copies the details of every expense in this household to a Google '
          'Sheet: date, amount, category, note and who added it, for all members. The app '
          'creates the Sheet in your Google Drive and can only touch that Sheet, not the rest '
          'of your Drive.\n\n'
          'The copy goes one way. Changes typed into the Sheet are not read back and are '
          'overwritten. You can disconnect at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('sheet-privacy-agree'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Agree and continue'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    await _run(ref.read(sheetActionsProvider).connect);
  }

  Future<void> _disconnect() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect Google Sheet?'),
        content: const Text(
          'New expenses will stop going to the Sheet and Google access is removed. The '
          'Sheet stays in your Drive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('sheet-disconnect-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    await _run(ref.read(sheetActionsProvider).disconnect);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final permissions = ref.watch(permissionsProvider);
    final status = ref.watch(sheetStatusProvider).value ?? const SheetStatus();
    final connecting = ref.watch(sheetConnectingProvider);
    final actions = ref.read(sheetActionsProvider);

    final (String headline, String detail) = switch (status.state) {
      SheetState.notConnected when connecting => (
        'Waiting for Google',
        'Finish in the browser window. This page updates by itself.',
      ),
      SheetState.notConnected => (
        'Not connected',
        permissions.canConnectSheet
            ? 'Copy every expense into a Google Sheet automatically.'
            : 'Only the owner can connect a Google Sheet.',
      ),
      SheetState.copying => (
        'Copying your expenses',
        status.backfillTotal > 0
            ? '${status.copied} of ${status.backfillTotal} done'
            : 'Starting',
      ),
      SheetState.active => (
        'Connected',
        status.lastSyncedAt == null
            ? 'Waiting for the first expense'
            : 'Last synced ${DateFormat('MMM d, HH:mm', 'en_US').format(status.lastSyncedAt!)}',
      ),
      SheetState.error => (
        'Sync problem',
        permissions.canSyncSheet && status.lastError != null
            ? '${status.lastError}. We will try again.'
            : 'We will try again. New expenses are kept.',
      ),
      SheetState.revoked => (
        'Google access was removed',
        permissions.canConnectSheet
            ? 'Reconnect to keep the Sheet up to date. Nothing is lost.'
            : 'Ask the owner to reconnect Google.',
      ),
    };
    final problem =
        status.state == SheetState.revoked || status.state == SheetState.error;

    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        key: const ValueKey('sheet-card'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Google Sheet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: switch (status.state) {
                    SheetState.active => t.primary,
                    SheetState.copying => t.muted,
                    SheetState.error || SheetState.revoked => t.amberText,
                    SheetState.notConnected => t.grey,
                  },
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  key: const ValueKey('sheet-headline'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: problem ? t.amberText : t.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            key: const ValueKey('sheet-detail'),
            style: TextStyle(fontSize: 14, height: 1.35, color: t.muted),
          ),
          if (status.progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                key: const ValueKey('sheet-progress'),
                value: status.progress,
                minHeight: 8,
                color: t.primary,
                backgroundColor: t.border,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('sheet-error'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
            ),
          ],
          ..._buttons(
            status,
            connecting,
            permissions.canConnectSheet,
            permissions.canSyncSheet,
            actions,
          ),
        ],
      ),
    );
  }

  List<Widget> _buttons(
    SheetStatus status,
    bool connecting,
    bool canConnect,
    bool canSync,
    SheetActions actions,
  ) {
    final buttons = <Widget>[];
    void add(Widget w) {
      buttons
        ..add(const SizedBox(height: 10))
        ..add(w);
    }

    switch (status.state) {
      case SheetState.notConnected:
        if (!canConnect) break;
        if (connecting) {
          add(
            PillButton(
              key: const ValueKey('sheet-cancel'),
              label: 'Cancel',
              style: PillStyle.text,
              onTap: ref.read(sheetConnectingProvider.notifier).cancel,
            ),
          );
        } else {
          add(
            PillButton(
              key: const ValueKey('sheet-connect'),
              label: 'Connect Google Sheet',
              busy: _busy,
              onTap: _connect,
            ),
          );
        }
      case SheetState.copying:
        break;
      case SheetState.active:
      case SheetState.error:
        if (canSync) {
          add(
            PillButton(
              key: const ValueKey('sheet-sync-now'),
              label: 'Sync now',
              style: PillStyle.outlined,
              busy: _busy,
              onTap: () => _run(actions.syncNow),
            ),
          );
          final url = status.spreadsheetUrl;
          if (url != null) {
            add(
              PillButton(
                key: const ValueKey('sheet-open'),
                label: 'Open sheet',
                style: PillStyle.text,
                onTap: () => _run(() => actions.open(url)),
              ),
            );
          }
        }
        if (canConnect) {
          add(
            PillButton(
              key: const ValueKey('sheet-disconnect'),
              label: 'Disconnect',
              style: PillStyle.danger,
              onTap: _disconnect,
            ),
          );
        }
      case SheetState.revoked:
        if (canConnect) {
          add(
            PillButton(
              key: const ValueKey('sheet-reconnect'),
              label: 'Reconnect',
              busy: _busy,
              onTap: _connect,
            ),
          );
          add(
            PillButton(
              key: const ValueKey('sheet-disconnect'),
              label: 'Disconnect',
              style: PillStyle.danger,
              onTap: _disconnect,
            ),
          );
        }
    }
    return buttons;
  }
}
