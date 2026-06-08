import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('LangAware — accessible from i18n.dart', () {
    test('LangAware type is exported from i18n.dart (compile-time check)', () {
      // If this test compiles and runs, LangAware is accessible.
      expect(LangAware, isNotNull);
    });
  });

  group('lang ValueNotifier', () {
    test('starts with a known language code', () {
      expect(lang.value == 'en' || lang.value == 'cs', isTrue);
    });

    test('accepts "en" as a valid value', () {
      lang.value = 'en';
      expect(lang.value, 'en');
    });

    test('accepts "cs" as a valid value', () {
      lang.value = 'cs';
      expect(lang.value, 'cs');
    });

    test('changes are reflected immediately', () {
      lang.value = 'en';
      expect(tr('login'), 'Log in');
      lang.value = 'cs';
      expect(tr('login'), 'Přihlásit se');
    });
  });

  group('toggleLang()', () {
    test('toggles from en to cs', () {
      lang.value = 'en';
      toggleLang();
      expect(lang.value, 'cs');
    });

    test('toggles from cs to en', () {
      lang.value = 'cs';
      toggleLang();
      expect(lang.value, 'en');
    });

    test('double toggle returns to original language', () {
      lang.value = 'en';
      toggleLang();
      toggleLang();
      expect(lang.value, 'en');
    });

    test('toggle changes tr() output', () {
      lang.value = 'en';
      final String before = tr('login');
      toggleLang();
      final String after = tr('login');
      expect(before, isNot(equals(after)));
      lang.value = 'en'; // restore
    });
  });

  group('tr() function', () {
    test('unknown key returns the key itself', () {
      lang.value = 'en';
      expect(tr('totally_unknown_key_xyz'), 'totally_unknown_key_xyz');
    });

    test('unknown language returns the key', () {
      lang.value = 'xx';
      expect(tr('login'), 'login');
      lang.value = 'en'; // restore
    });

    test('EN login translation', () {
      lang.value = 'en';
      expect(tr('login'), 'Log in');
    });

    test('CS login translation', () {
      lang.value = 'cs';
      expect(tr('login'), 'Přihlásit se');
    });
  });
}
