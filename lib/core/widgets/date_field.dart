import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// A field that shows a date and opens the date picker when tapped. [value] may be null
/// ("no date"); [onClear] adds a clear button when given.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.onClear,
    this.emptyText = 'Not set',
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onClear;
  final DateTime firstDate;
  final DateTime lastDate;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = value == null
        ? emptyText
        : DateFormat('EEE, d MMM yyyy', 'en_US').format(value!);
    return Semantics(
      button: true,
      label: '$label, $text',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.smallCard),
        onTap: () async {
          final initial = value ?? DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: initial.isBefore(firstDate)
                ? firstDate
                : (initial.isAfter(lastDate) ? lastDate : initial),
            firstDate: firstDate,
            lastDate: lastDate,
          );
          if (picked != null) onChanged(picked);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTapTarget + 20),
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(AppRadii.smallCard),
            border: Border.all(color: t.chipBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 13, color: t.muted)),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: 17,
                        color: value == null ? t.muted : t.text,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null && value != null)
                IconButton(
                  tooltip: 'Clear $label',
                  onPressed: onClear,
                  icon: Icon(Icons.close_rounded, color: t.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
