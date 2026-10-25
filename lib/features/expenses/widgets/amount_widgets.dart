import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/surface_card.dart';

/// The big "S$ 48.20" amount card.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    super.key,
    required this.symbol,
    required this.text,
    required this.isEmpty,
    this.error,
    this.compact = false,
  });

  final String symbol;

  /// The typed amount, for example `48.20`.
  final String text;

  /// Nothing typed yet: the amount is drawn in the muted colour.
  final bool isEmpty;
  final String? error;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bigSize = compact ? 40.0 : 48.0;
    final display = SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              symbol,
              style: TextStyle(
                fontSize: compact ? 22 : 28,
                fontWeight: FontWeight.w600,
                color: t.muted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              key: const Key('amount-text'),
              style: TextStyle(
                fontSize: bigSize,
                height: 1.1,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
                color: isEmpty ? t.muted : t.text,
              ),
            ),
          ],
        ),
      ),
    );
    if (compact) {
      return Semantics(
        label: 'Amount $symbol$text',
        child: ExcludeSemantics(child: display),
      );
    }
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      semanticLabel: 'Amount $symbol$text${error == null ? '' : '. $error'}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Amount', style: TextStyle(fontSize: 14, color: t.muted)),
            const SizedBox(height: 4),
            display,
            if (error != null) ...[
              const SizedBox(height: 4),
              Text(
                error!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: t.rose,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 0 to 9, decimal point and backspace.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
    required this.decimalSeparator,
    required this.allowDecimal,
    this.keyHeight = 52,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;
  final String decimalSeparator;
  final bool allowDecimal;
  final double keyHeight;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> keys) => Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: keys[i]),
        ],
      ],
    );
    Widget digit(String d) =>
        _Key(label: d, semantic: d, height: keyHeight, onTap: () => onDigit(d));

    return Column(
      children: [
        row([digit('1'), digit('2'), digit('3')]),
        const SizedBox(height: 8),
        row([digit('4'), digit('5'), digit('6')]),
        const SizedBox(height: 8),
        row([digit('7'), digit('8'), digit('9')]),
        const SizedBox(height: 8),
        row([
          allowDecimal
              ? _Key(
                  label: decimalSeparator,
                  semantic: 'Decimal point',
                  height: keyHeight,
                  onTap: onDecimal,
                )
              : SizedBox(height: keyHeight),
          digit('0'),
          _Key(
            icon: Icons.backspace_outlined,
            semantic: 'Delete',
            height: keyHeight,
            onTap: onBackspace,
          ),
        ]),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    required this.semantic,
    required this.height,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final String semantic;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: t.chipBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: height < kMinTapTarget ? kMinTapTarget : height,
            child: Center(
              child: icon != null
                  ? Icon(icon, size: 22, color: t.text)
                  : Text(
                      label!,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: t.text,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
