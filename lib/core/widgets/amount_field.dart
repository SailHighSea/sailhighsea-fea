import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_text_field.dart';

/// A text field for a money amount: digits and the decimal marks only, number keyboard.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.label,
    required this.controller,
    this.autofocus = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => AppTextField(
    label: label,
    controller: controller,
    autofocus: autofocus,
    onSubmitted: onSubmitted,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
  );
}
