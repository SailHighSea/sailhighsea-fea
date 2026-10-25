import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/app_database.dart';
import '../../core/db/db_providers.dart';
import '../../core/google/google_api.dart';
import '../../core/layout/page_layout.dart';
import '../../core/money/currency.dart';
import '../../core/money/money_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/time.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/pill_button.dart';
import '../../core/widgets/surface_card.dart';
import '../expenses/expense_providers.dart';
import 'import_parser.dart';
import 'import_service.dart';
import '../scan/receipt_services.dart';
import 'statement_readers.dart';

/// Import expenses from a CSV file, an Excel file (.xlsx), a PDF statement or a Google Sheet.
/// Date, description and amount are filled in automatically, categories are guessed, and
/// everything is shown as a table to check and fix before anything is saved.
class ImportScreen extends ConsumerStatefulWidget {
  const ImportScreen({super.key});

  @override
  ConsumerState<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends ConsumerState<ImportScreen> {
  final _link = TextEditingController();
  List<List<String>>? _rows;
  int _extraIncome = 0;
  CurrencyDetection _detect = const CurrencyDetection({});
  CurrencyInfo? _currency;
  bool _keepAsIs = false;
  ImportPreview? _preview;
  List<ImportDraft> _drafts = [];
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

  CurrencyInfo get _appCurrency => ref.read(moneyFormatterProvider).currency;

  void _reset() {
    _rows = null;
    _preview = null;
    _drafts = [];
    _currency = null;
    _keepAsIs = false;
    _extraIncome = 0;
    _error = null;
  }

  Future<void> _guard(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _reset();
    });
    try {
      await work();
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

  Future<void> _chooseFile() => _guard(() async {
    final picked = await ref.read(importFilePickerProvider)();
    if (picked == null) return;
    switch (picked.extension) {
      case 'xlsx':
        await _load(rowsFromXlsx(picked.bytes), 0);
      case 'pdf':
        final text = textFromPdf(picked.bytes);
        if (text.trim().isEmpty) {
          if (mounted) {
            setState(
              () => _error = 'This PDF has no readable text (it may be a scan). Export the statement as CSV or Excel from your bank instead.',
            );
          }
          return;
        }
        final s = rowsFromStatementText(
          text,
          defaultYear: ref.read(clockProvider)().year,
        );
        await _load(s.rows, s.moneyIn);
      case 'png' || 'jpg' || 'jpeg' || 'webp':
        await _readPicture(picked.path);
      case 'xls':
        if (mounted) {
          setState(
            () => _error = 'Old .xls files are not supported. Save the file as .xlsx or CSV and choose that.',
          );
        }
      default:
        await _load(
          parseCsv(utf8.decode(picked.bytes, allowMalformed: true)),
          0,
        );
    }
  });

  /// A photo or screenshot of a statement: read on the phone with on-device text recognition, put
  /// back together row by row, then treated like any statement.
  Future<void> _readPicture(String? path) async {
    final ocr = ref.read(receiptOcrProvider);
    if (!ocr.isAvailable) {
      if (mounted) {
        setState(
          () => _error = 'Reading a picture works in the phone app. On this device use a CSV, Excel or PDF statement, or send the picture to your phone.',
        );
      }
      return;
    }
    if (path == null) return;
    final lines = await ocr.recogniseLines(path);
    final s = rowsFromOcrLines(
      lines,
      defaultYear: ref.read(clockProvider)().year,
    );
    if (s.rows.length <= 1) {
      if (mounted) {
        setState(
          () => _error = lines.isEmpty
              ? 'No text was found in that picture. Try a sharper, straighter photo.'
              : 'No transactions were found in that picture. Each row needs a date and an amount. Try a sharper photo of the table.',
        );
      }
      return;
    }
    await _load(s.rows, s.moneyIn);
  }

  Future<void> _photo({required bool camera}) => _guard(() async {
    final ocr = ref.read(receiptOcrProvider);
    if (!ocr.isAvailable) {
      await _readPicture(null);
      return;
    }
    final source = ref.read(receiptImageSourceProvider);
    final path = camera ? await source.takePhoto() : await source.chooseFile();
    await _readPicture(path);
  });

  Future<void> _readSheet() => _guard(() async {
    final sheets = ref.read(sheetsApiProvider);
    final id = sheetIdFromInput(_link.text);
    if (id == null || sheets == null) {
      if (mounted) {
        setState(
          () => _error = 'Paste the link of the Google Sheet, or its ID.',
        );
      }
      return;
    }
    final tab = await sheets.firstTabTitle(id);
    await _load(
      await sheets.read(id, "'${tab.replaceAll("'", "''")}'!A1:Z5000"),
      0,
    );
  });

  /// New rows: work out the currency, and only ask when it is not clear.
  Future<void> _load(List<List<String>> rows, int income) async {
    final detect = detectCurrencies(rows);
    CurrencyInfo? chosen;
    if (detect.codes.length == 1) chosen = currencyByCode(detect.codes.first);
    if (mounted) {
      setState(() {
        _rows = rows;
        _extraIncome = income;
        _detect = detect;
        _currency = chosen;
      });
    }
    if (chosen != null) await _analyse();
  }

  bool get _needsKeepAsIs =>
      _currency != null && _currency!.code != _appCurrency.code;

  /// Reads the rows with the chosen currency, guesses categories and fills the table.
  Future<void> _analyse() async {
    final rows = _rows;
    final cur = _currency;
    if (rows == null || cur == null) return;
    if (_needsKeepAsIs &&
        (!_keepAsIs || cur.minorDigits != _appCurrency.minorDigits)) {
      setState(() {
        _preview = null;
        _drafts = [];
      });
      return;
    }
    final service = _service();
    final preview = await service.previewRows(
      rows,
      currency: cur,
      extraIncome: _extraIncome,
    );
    final guesser = await service.loadGuesser();
    final drafts = [
      for (final r in preview.ready)
        () {
          final g = guesser.guess(r.description);
          return ImportDraft(r, categoryId: g.categoryId, reason: g.reason);
        }(),
    ];
    if (mounted) {
      setState(() {
        _preview = preview;
        _drafts = drafts;
      });
    }
  }

  int get _missing =>
      _drafts.where((d) => d.include && d.categoryId == null).length;

  Future<void> _import() async {
    if (_missing > 0 || _busy) return;
    setState(() => _busy = true);
    final n = await _service().importDrafts(_drafts);
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
    final categories =
        ref.watch(categoriesProvider).value ?? const <CategoryRow>[];
    final p = _preview;
    final ask = _rows != null && _currency == null;

    return AdaptivePage(
      header: PageHeader(
        title: 'Import expenses',
        onBack: () => context.canPop() ? context.pop() : context.go('/home'),
      ),
      children: [
        SurfaceCard(
          child: Text(
            'Choose a CSV, Excel (.xlsx) or PDF statement, a photo or screenshot of one, or read a Google Sheet. The date, description and amount are filled in for you and each expense gets a category when it can be worked out. You check everything in a table before anything is saved. Rows already in the app are skipped, money received is left out, and amounts are never converted.',
            style: TextStyle(fontSize: 14, color: t.muted),
          ),
        ),
        const SizedBox(height: 12),
        PillButton(
          key: const ValueKey('import-file'),
          label: 'Choose a file (CSV, Excel, PDF)',
          icon: Icons.upload_file,
          busy: _busy,
          onTap: _chooseFile,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillButton(
              key: const ValueKey('import-photo'),
              label: 'Photo of a statement',
              style: PillStyle.outlined,
              icon: Icons.image_outlined,
              busy: _busy,
              onTap: () => _photo(camera: false),
            ),
            if (ref.watch(receiptImageSourceProvider).hasCamera)
              PillButton(
                key: const ValueKey('import-camera'),
                label: 'Take a photo',
                style: PillStyle.outlined,
                icon: Icons.photo_camera_outlined,
                busy: _busy,
                onTap: () => _photo(camera: true),
              ),
          ],
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
        if (_rows != null) ...[
          const SizedBox(height: 16),
          _CurrencyCard(
            detect: _detect,
            selected: _currency,
            appCurrency: _appCurrency,
            keepAsIs: _keepAsIs,
            onPick: (c) {
              setState(() => _currency = c);
              unawaited(_analyse());
            },
            onKeepAsIs: (v) {
              setState(() => _keepAsIs = v);
              unawaited(_analyse());
            },
          ),
        ],
        if (ask) const SizedBox.shrink(),
        if (p != null) ...[
          const SizedBox(height: 16),
          _Summary(preview: p, money: money, drafts: _drafts),
          if (_drafts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Table(
              drafts: _drafts,
              categories: categories,
              money: money,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_missing > 0) ...[
              Text(
                '$_missing ${_missing == 1 ? 'expense needs' : 'expenses need'} a category. Choose one in the table, or put them in Other.',
                key: const ValueKey('import-missing'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
              const SizedBox(height: 8),
              PillButton(
                key: const ValueKey('import-other'),
                label: 'Put the rest in Other',
                style: PillStyle.outlined,
                onTap: () => setState(() {
                  for (final d in _drafts) {
                    if (d.include && d.categoryId == null) {
                      d.categoryId = otherCategoryId;
                      d.reason = 'you';
                    }
                  }
                }),
              ),
              const SizedBox(height: 8),
            ],
            PillButton(
              key: const ValueKey('import-confirm'),
              label:
                  'Import ${_drafts.where((d) => d.include).length} expenses',
              busy: _busy,
              onTap: _missing > 0 || _drafts.every((d) => !d.include)
                  ? null
                  : () => unawaited(_import()),
            ),
          ],
        ],
      ],
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  const _CurrencyCard({
    required this.detect,
    required this.selected,
    required this.appCurrency,
    required this.keepAsIs,
    required this.onPick,
    required this.onKeepAsIs,
  });

  final CurrencyDetection detect;
  final CurrencyInfo? selected;
  final CurrencyInfo appCurrency;
  final bool keepAsIs;
  final ValueChanged<CurrencyInfo> onPick;
  final ValueChanged<bool> onKeepAsIs;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sentence = selected != null
        ? 'Currency: ${selected!.code}${detect.codes.length == 1 ? ' (found in the file)' : ''}'
        : detect.ambiguousDollar
        ? 'The amounts use a "\$" sign, which could be several currencies. Which currency are they in?'
        : detect.codes.length > 1
        ? 'This file mentions ${detect.codes.join(', ')}. Which currency should be imported? Rows in the others are skipped.'
        : 'We could not tell which currency these amounts are in. Which currency are they?';
    return SurfaceCard(
      key: const ValueKey('currency-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            sentence,
            key: const ValueKey('currency-sentence'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: selected == null ? FontWeight.w700 : FontWeight.w500,
              color: t.text,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: DropdownButton<String>(
              key: const ValueKey('currency-picker'),
              isExpanded: true,
              value: selected?.code,
              hint: const Text('Choose a currency'),
              items: [
                for (final c in supportedCurrencies)
                  DropdownMenuItem(
                    value: c.code,
                    child: Text('${c.code}  ${c.name}'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onPick(currencyByCode(v));
              },
            ),
          ),
          if (selected != null && selected!.code != appCurrency.code) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('keep-as-is'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: keepAsIs,
              onChanged: (v) => onKeepAsIs(v ?? false),
              title: Text(
                'The app uses ${appCurrency.code}. Import these ${selected!.code} amounts as they are, without converting.',
                style: TextStyle(fontSize: 13, color: t.text),
              ),
            ),
            if (selected!.minorDigits != appCurrency.minorDigits)
              Text(
                '${selected!.code} and ${appCurrency.code} use a different number of decimals, so these cannot be imported as they are.',
                key: const ValueKey('currency-digits'),
                style: TextStyle(fontSize: 13, color: t.rose),
              ),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.preview,
    required this.money,
    required this.drafts,
  });
  final ImportPreview preview;
  final dynamic money;
  final List<ImportDraft> drafts;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final p = preview;
    return SurfaceCard(
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
          if (p.incomeSkipped > 0)
            Text(
              '${p.incomeSkipped} money-in rows left out (not expenses)',
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
        ],
      ),
    );
  }
}

/// The import table: one row per expense with the date, description, amount and category, a
/// checkbox to leave a row out, and a category picker that is highlighted when it needs a choice.
class _Table extends StatelessWidget {
  const _Table({
    required this.drafts,
    required this.categories,
    required this.money,
    required this.onChanged,
  });

  final List<ImportDraft> drafts;
  final List<CategoryRow> categories;
  final dynamic money;
  final VoidCallback onChanged;

  static const _w = [56.0, 112.0, 230.0, 110.0, 190.0];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    Widget head(String s, double w, {TextAlign a = TextAlign.left}) => SizedBox(
      width: w,
      child: Text(
        s,
        textAlign: a,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: t.muted,
        ),
      ),
    );
    return SurfaceCard(
      key: const ValueKey('import-table'),
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _w.reduce((a, b) => a + b) + 16,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
                child: Row(
                  children: [
                    head('Use', _w[0]),
                    head('Date', _w[1]),
                    head('Description', _w[2]),
                    head('Amount', _w[3], a: TextAlign.right),
                    const SizedBox(width: 12),
                    head('Category', _w[4] - 12),
                  ],
                ),
              ),
              for (final d in drafts)
                _Row(
                  key: ValueKey('import-row-${d.row.line}'),
                  draft: d,
                  categories: categories,
                  money: money,
                  widths: _w,
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.draft,
    required this.categories,
    required this.money,
    required this.widths,
    required this.onChanged,
  });

  final ImportDraft draft;
  final List<CategoryRow> categories;
  final dynamic money;
  final List<double> widths;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final d = draft;
    final needs = d.include && d.categoryId == null;
    final style = TextStyle(fontSize: 14, color: d.include ? t.text : t.muted);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              SizedBox(
                width: widths[0],
                child: Semantics(
                  container: true,
                  excludeSemantics: true,
                  checked: d.include,
                  label:
                      'Import ${d.row.description.isEmpty ? d.row.date : d.row.description}',
                  onTap: () {
                    d.include = !d.include;
                    onChanged();
                  },
                  child: Checkbox(
                    key: ValueKey('use-${d.row.line}'),
                    value: d.include,
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onChanged: (v) {
                      d.include = v ?? true;
                      onChanged();
                    },
                  ),
                ),
              ),
              SizedBox(
                width: widths[1],
                child: Text(d.row.date, style: style),
              ),
              SizedBox(
                width: widths[2],
                child: Text(
                  d.row.description.isEmpty
                      ? '(no description)'
                      : d.row.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              SizedBox(
                width: widths[3],
                child: Text(
                  money.format(d.row.cents) as String,
                  textAlign: TextAlign.right,
                  style: style.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: widths[4] - 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: needs
                        ? Border.all(color: t.rose, width: 1.5)
                        : null,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: kMinTapTarget),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        key: ValueKey('category-${d.row.line}'),
                        isExpanded: true,
                        value: d.categoryId,
                        hint: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            'Choose…',
                            style: TextStyle(
                              color: t.rose,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        items: [
                          for (final c in categories)
                            DropdownMenuItem(
                              value: c.id,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(c.name),
                              ),
                            ),
                        ],
                        onChanged: d.include
                            ? (v) {
                                d.categoryId = v;
                                d.reason = 'you';
                                onChanged();
                              }
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
