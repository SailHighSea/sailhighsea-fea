import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'window_class.dart';

/// A choice sheet: a bottom sheet on the phone, a centred dialog on wider windows, so a
/// screen asks the same question the same way on every size.
Future<T?> showAdaptiveSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  final t = context.tokens;
  if (context.layout.isCompact) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: t.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadii.card),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(child: builder(context)),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(child: builder(context)),
        ),
      ),
    ),
  );
}
