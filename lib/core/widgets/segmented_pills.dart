import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// A two or three way switch in a pill-shaped track (the Can edit / View only toggle).
class SegmentedPills extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.border,
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: labels[i],
                excludeSemantics: true,
                child: Material(
                  color: i == selected ? t.surface : Colors.transparent,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => onChanged(i),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: kMinTapTarget + 4,
                      ),
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: i == selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: t.text,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
