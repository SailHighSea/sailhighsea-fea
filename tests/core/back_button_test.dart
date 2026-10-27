import 'package:flutter_test/flutter_test.dart';

import 'package:family_expenses/core/routing/app_router.dart';

void main() {
  test('back from a Settings page goes to Settings, from a tab to Home', () {
    expect(backTarget('/home'), isNull);
    expect(backTarget('/settings'), '/home');
    expect(backTarget('/appearance'), '/settings');
    expect(backTarget('/data'), '/settings');
    expect(backTarget('/about'), '/settings');
    expect(backTarget('/personalise'), '/appearance');
    expect(backTarget('/data/restore'), '/data');
    expect(backTarget('/goals'), '/home');
  });
}
