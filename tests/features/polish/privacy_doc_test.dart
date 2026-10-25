import 'dart:io';

import 'package:family_expenses/features/privacy/privacy_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('docs/PRIVACY.md has the same text as the in-app privacy policy', () {
    final doc = File('docs/PRIVACY.md').readAsStringSync();
    for (final (title, body) in privacyPolicySections) {
      expect(doc, contains('## $title'));
      expect(doc, contains(body));
    }
  });
}
