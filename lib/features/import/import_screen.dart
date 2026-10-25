import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/db_providers.dart';
import '../../core/google/google_api.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import 'import_parser.dart';
import 'import_service.dart';

/// Import expenses from a CSV file or a Google Sheet with the columns Date, Description,
/// Currency and Amount. Shows what would happen first; nothing is saved until "Import".
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _link = TextEditingController();
  ImportPreview? _preview;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  ImportService _service() => ImportService(
    ref.read(databaseProvider),
    currency: ref.read(moneyFormatterProvider).currency,
    today: ref.read(clockProvider)(),
    clock: ref.read(clockProvider),
  );

  Future<void> _run(Future<ImportPreview?> Function() read) async {
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
    });
    try {
      final p = await read();
      if (mounted) setState(() => _preview = p);
    } on SheetAccessError {
      if (mounted) {
        setState(
          () => _error = 'That sheet is not available to your Google account. Check the link and that it is shared with you.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read that. Check the file or your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFile() => _run(() async {
    final text = await ref.read(importFilePickerProvider)();
    return text == null ? null : _service().previewCsv(text);
  });

  Future<void> _readSheet() => _run(() async {
    final sheets = ref.read(sheetsApiProvider);
    final id = sheetIdFromInput(_link.text);
    if (id == null) {
      setState(() => _error = 'Paste the link of the Google Sheet, or its ID.');
      return null;
    }
    return _service().previewSheet(sheets!, id);
  });

  Future<void> _import() async {
    final p = _preview;
    if (p == null || p.ready.isEmpty || _busy) return;
    setState(() => _busy = true);
    final n = await _service().import(p);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text('Imported $n expenses')));
    context.go('/expenses');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final money = ref.watch(moneyFormatterProvider);
    final canReadSheet = ref.watch(sheetsApiProvider) != null;
    final p = _preview;

    return AdaptivePage(
      header: PageHeader(
        title: 'Import expenses',
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/appearance'),
      ),
      children: [
        SurfaceCard(
          child: Text(
            'Use a sheet with the columns Date, Description, Currency and Amount (the first row can be a header; without one they are read in that order). Everything is added to "Other" and you can change the category afterwards. Rows already in the app are skipped, so importing twice is safe. Amounts are not converted: rows in another currency are skipped.',
            style: TextStyle(fontSize: 14, color: t.muted),
          ),
        ),
        const SizedBox(height: 12),
        PillButton(
          key: const ValueKey('import-file'),
          label: 'Choose a CSV file',
          icon: Icons.upload_file,
          busy: _busy,
          onTap: _chooseFile,
        ),
        if (canReadSheet) ...[
          const SizedBox(height: 16),
          AppTextField(
            label: 'Google Sheet link or ID',
            controller: _link,
            onSubmitted: (_) => _readSheet(),
          ),
          const SizedBox(height: 8),
          PillButton(
            key: const ValueKey('import-sheet'),
            label: 'Read the sheet',
            style: PillStyle.outlined,
            busy: _busy,
            onTap: _readSheet,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: const ValueKey('import-error'),
            style: TextStyle(fontSize: 13, color: t.rose),
          ),
        ],
        if (p != null) ...[
          const SizedBox(height: 16),
          SurfaceCard(
            key: const ValueKey('import-preview'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.ready.isEmpty
                      ? 'Nothing new to import'
                      : '${p.ready.length} new expenses, ${money.format(p.totalCents)} in total',
                  key: const ValueKey('import-summary'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                if (p.duplicates.isNotEmpty)
                  Text(
                    '${p.duplicates.length} already in the app (skipped)',
                    style: TextStyle(fontSize: 13, color: t.muted),
                  ),
                if (p.problems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${p.problems.length} rows skipped',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.rose,
                    ),
                  ),
                  for (final x in p.problems.take(8))
                    Text(
                      'Line ${x.line}: ${x.message}',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                  if (p.problems.length > 8)
                    Text(
                      'and ${p.problems.length - 8} more',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                ],
                if (p.ready.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final r in p.ready.take(5))
                    Text(
                      '${r.date}  ${r.description.isEmpty ? '(no description)' : r.description}  ${money.format(r.cents)}',
                      style: TextStyle(fontSize: 12, color: t.text),
                    ),
                  if (p.ready.length > 5)
                    Text(
                      'and ${p.ready.length - 5} more',
                      style: TextStyle(fontSize: 12, color: t.muted),
                    ),
                ],
              ],
            ),
          ),
          if (p.ready.isNotEmpty) ...[
            const SizedBox(height: 12),
            PillButton(
              key: const ValueKey('import-confirm'),
              label: 'Import ${p.ready.length} expenses',
              busy: _busy,
              onTap: () => unawaited(_import()),
            ),
          ],
        ],
      ],
    );
  }
}
