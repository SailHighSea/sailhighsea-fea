import 'package:flutter/material.dart';

import '../layout/adaptive_sheet.dart';
import '../money/currency.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Choose any currency: a sheet (dialog on wide windows) with a search box and a list that scrolls
/// on every platform. Search matches the code, the name or the symbol ("yen", "chf", "€").
/// Returns the code, or null when closed.
Future<String?> showCurrencyPicker(BuildContext context, {String? selected}) =>
    showAdaptiveSheet<String>(
      context,
      builder: (_) => CurrencyPickerSheet(selected: selected),
    );

class CurrencyPickerSheet extends StatefulWidget {
  const CurrencyPickerSheet({
    super.key,
    this.selected,
    this.onPicked,
    this.height,
  });
  final String? selected;

  /// Called with the code instead of closing a route (for use inline on a page).
  final ValueChanged<String>? onPicked;

  /// Fixed height; by default a sheet-sized one from the screen.
  final double? height;

  @override
  State<CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<CurrencyPickerSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<CurrencyInfo> get _matches {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return supportedCurrencies;
    return [
      for (final c in supportedCurrencies)
        if (c.code.toLowerCase().contains(q) ||
            c.name.toLowerCase().contains(q) ||
            c.symbol.toLowerCase().contains(q))
          c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    final matches = _matches;
    // A fixed height gives the list room to scroll inside a bottom sheet or a dialog.
    final height =
        widget.height ??
        (media.size.height * 0.7).clamp(320.0, 560.0) -
            media.viewInsets.bottom.clamp(0.0, 200.0);
    return SizedBox(
      key: const ValueKey('currency-sheet'),
      height: height < 240 ? 240 : height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Semantics(
              header: true,
              child: Text(
                'Choose a currency',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.text,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              key: const ValueKey('currency-search'),
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by name, code or symbol',
                prefixIcon: const Icon(Icons.search),
                constraints: const BoxConstraints(minHeight: kMinTapTarget),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.smallCard),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(
                      'No currency matches',
                      style: TextStyle(color: t.muted),
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('currency-list'),
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final c = matches[i];
                      final on = c.code == widget.selected;
                      return InkWell(
                        key: ValueKey('currency-${c.code}'),
                        onTap: () => widget.onPicked != null
                            ? widget.onPicked!(c.code)
                            : Navigator.of(context).pop(c.code),
                        child: Semantics(
                          button: true,
                          selected: on,
                          label: '${c.name}, ${c.code}',
                          excludeSemantics: true,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 52),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 6,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 56,
                                    child: Text(
                                      c.code,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: t.text,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      c.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: t.text,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    c.symbol,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: t.muted,
                                    ),
                                  ),
                                  if (on)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Icon(
                                        Icons.check,
                                        color: t.primary,
                                        size: 20,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
