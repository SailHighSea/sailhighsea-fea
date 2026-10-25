import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// A labelled text field in the app's card style (sign-in, household name, invite code).
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.inputFormatters,
    this.onSubmitted,
    this.onChanged,
    this.big = false,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// Large bold letter-spaced text, for the invite code.
  final bool big;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      constraints: const BoxConstraints(minHeight: kMinTapTarget + 20),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadii.smallCard),
        border: Border.all(color: t.chipBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: t.muted)),
          Semantics(
            label: label,
            child: TextField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              textInputAction: textInputAction,
              autofillHints: autofillHints,
              inputFormatters: inputFormatters,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              autofocus: autofocus,
              textCapitalization: textCapitalization,
              cursorColor: t.primary,
              style: big
                  ? TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 3,
                      color: t.text,
                    )
                  : TextStyle(fontSize: 17, color: t.text),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
