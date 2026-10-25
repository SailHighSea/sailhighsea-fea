import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/time.dart';
import '../../../core/widgets/surface_card.dart';

/// "Today, 23 Oct", "Yesterday, 22 Oct" or "Fri, 16 Oct".
String formatExpenseDate(DateTime date, DateTime now) {
  final day = date.dateOnly;
  final diff = now.dateOnly.difference(day).inDays;
  final dayMonth = DateFormat('d MMM', 'en_US').format(day);
  if (diff == 0) return 'Today, $dayMonth';
  if (diff == 1) return 'Yesterday, $dayMonth';
  return '${DateFormat('EEE', 'en_US').format(day)}, $dayMonth';
}

/// Note and date rows.
class DetailsCard extends StatelessWidget {
  const DetailsCard({
    super.key,
    required this.note,
    required this.onNoteChanged,
    required this.date,
    required this.now,
    required this.onPickDate,
    this.noteController,
  });

  final String note;
  final ValueChanged<String> onNoteChanged;
  final DateTime date;
  final DateTime now;
  final VoidCallback onPickDate;
  final TextEditingController? noteController;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Text('Note', style: TextStyle(fontSize: 15, color: t.muted)),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    key: const Key('note-field'),
                    controller: noteController,
                    onChanged: onNoteChanged,
                    textAlign: TextAlign.right,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    maxLength: 120,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.text,
                    ),
                    cursorColor: t.primary,
                    decoration: InputDecoration(
                      isDense: true,
                      constraints: const BoxConstraints(minHeight: 44),
                      counterText: '',
                      border: InputBorder.none,
                      hintText: 'Add a note',
                      hintStyle: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: t.muted,
                      ),
                      semanticCounterText: null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),
          InkWell(
            key: const Key('date-row'),
            onTap: onPickDate,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Row(
                children: [
                  Text('Date', style: TextStyle(fontSize: 15, color: t.muted)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      formatExpenseDate(date, now),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
