import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  test('i18n switches language and falls back gracefully', () {
    lang.value = 'en';
    expect(tr('login'), 'Log in');
    lang.value = 'cs';
    expect(tr('login'), 'Přihlásit se');
    expect(tr('nonexistent_key'), 'nonexistent_key');
  });
}
