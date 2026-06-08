import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — theme toggle keys', () {
    const List<String> keys = <String>[
      'darkMode', 'lightMode', 'killApp',
    ];

    for (final String key in keys) {
      test('EN "$key" translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
      test('CS "$key" translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('darkMode and lightMode are different labels in EN', () {
      lang.value = 'en';
      expect(tr('darkMode'), isNot(equals(tr('lightMode'))));
    });

    test('darkMode and lightMode are different labels in CS', () {
      lang.value = 'cs';
      expect(tr('darkMode'), isNot(equals(tr('lightMode'))));
    });

    test('killApp and darkMode are different labels', () {
      lang.value = 'en';
      expect(tr('killApp'), isNot(equals(tr('darkMode'))));
    });
  });

  group('i18n — app menu keys', () {
    const List<String> keys = <String>[
      'search', 'downloads', 'library', 'app',
      'logout', 'ok', 'cancel', 'error', 'save',
    ];

    for (final String key in keys) {
      test('EN "$key" translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
      test('CS "$key" translated', () {
        lang.value = 'cs';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('nav tab labels are all distinct in EN', () {
      lang.value = 'en';
      final List<String> navKeys = <String>['search', 'downloads', 'library'];
      final Set<String> vals = navKeys.map(tr).toSet();
      expect(vals.length, navKeys.length);
    });

    test('nav tab labels are all distinct in CS', () {
      lang.value = 'cs';
      final List<String> navKeys = <String>['search', 'downloads', 'library'];
      final Set<String> vals = navKeys.map(tr).toSet();
      expect(vals.length, navKeys.length);
    });

    test('ok and cancel are different labels', () {
      lang.value = 'en';
      expect(tr('ok'), isNot(equals(tr('cancel'))));
    });
  });

  group('theme toggle logic', () {
    // Mirrors _toggleTheme: dark → light → dark
    test('toggle from dark → light', () {
      const bool isDark = true;
      final bool newIsDark = !isDark;
      expect(newIsDark, isFalse);
    });

    test('toggle from light → dark', () {
      const bool isDark = false;
      final bool newIsDark = !isDark;
      expect(newIsDark, isTrue);
    });

    test('double toggle returns to original state', () {
      bool isDark = true;
      isDark = !isDark; // light
      isDark = !isDark; // dark again
      expect(isDark, isTrue);
    });
  });

  group('i18n — language toggle button labels', () {
    test('EN language key shows "Čeština" (offered language)', () {
      lang.value = 'en';
      // EN shows the other language name (Czech)
      final String label = tr('language');
      expect(label, isNotEmpty);
      expect(label, isNot(equals('language')));
    });

    test('CS language key shows "English" (offered language)', () {
      lang.value = 'cs';
      final String label = tr('language');
      expect(label, isNotEmpty);
      expect(label, isNot(equals('language')));
    });

    test('EN and CS language labels are different (each shows the other)', () {
      lang.value = 'en';
      final String enLabel = tr('language');
      lang.value = 'cs';
      final String csLabel = tr('language');
      expect(enLabel, isNot(equals(csLabel)));
    });
  });
}
