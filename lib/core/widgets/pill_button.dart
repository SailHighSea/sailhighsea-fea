import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

enum PillStyle { filled, outlined, text, danger }

/// A pill-shaped button used by the account and family screens: filled (primary action),
/// outlined (secondary) or plain text (tertiary). At least 44px tall (rule 8).
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.style = PillStyle.filled,
    this.busy = false,
    this.height = 52,
    this.icon,
    this.semanticLabel,
  });

  final String label;

  /// `null` disables the button.
  final VoidCallback? onTap;
  final PillStyle style;
  final bool busy;
  final double height;
  final IconData? icon;

  /// Spoken name when the visible label alone is not enough ("Revoke Can edit code").
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final enabled = onTap != null && !busy;
    final (Color? fill, Color fg, Color? line) = switch (style) {
      PillStyle.filled => (t.primary, t.onPrimary, null),
      PillStyle.outlined => (null, t.primary, t.primary),
      PillStyle.text => (null, t.muted, null),
      PillStyle.danger => (null, t.rose, null),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: fill ?? Colors.transparent,
          shape: StadiumBorder(
            side: line == null
                ? BorderSide.none
                : BorderSide(color: line, width: 1.5),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: enabled ? onTap : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: height < kMinTapTarget ? kMinTapTarget : height,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Center(
                  widthFactor: 1,
                  child: busy
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: fg,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null) ...[
                              Icon(icon, size: 20, color: fg),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: style == PillStyle.text ? 14 : 16,
                                  fontWeight: FontWeight.w700,
                                  color: fg,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
