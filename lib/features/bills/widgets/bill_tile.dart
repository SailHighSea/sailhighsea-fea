import 'package:flutter/material.dart';

import '../../../core/money/money_format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../domain/bill_calculations.dart';

/// One bill: a date chip (amber when due soon), name and "Due in 5 days", the amount and, when
/// the role may, a Mark paid button.
class BillTile extends StatelessWidget {
  const BillTile({
    super.key,
    required this.bill,
    required this.money,
    this.onMarkPaid,
    this.onTap,
  });

  final BillView bill;
  final MoneyFormatter money;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final soon = bill.isSoon();
    final chipBackground = soon
        ? t.amber.withValues(alpha: 0.35)
        : t.navActiveBackground;
    final chipText = soon ? t.amberText : t.navActiveText;
    return Semantics(
      container: true,
      label:
          '${bill.bill.name}, ${money.format(bill.amountCents)}, ${bill.dueLabel}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.smallCard),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget + 16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: chipBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${bill.dueOn.day}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: chipText,
                          ),
                        ),
                        Text(
                          shortMonth(bill.dueOn),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: chipText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bill.bill.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                        Text(
                          bill.dueLabel,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: soon
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: soon ? t.amberText : t.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Text(
                        money.format(bill.amountCents),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: t.text,
                        ),
                      ),
                    ),
                    if (onMarkPaid != null)
                      TextButton(
                        key: ValueKey('mark-paid-${bill.bill.id}'),
                        onPressed: onMarkPaid,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          foregroundColor: t.primary,
                        ),
                        child: Semantics(
                          label: 'Mark ${bill.bill.name} paid',
                          excludeSemantics: true,
                          child: const Text(
                            'Mark paid',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
