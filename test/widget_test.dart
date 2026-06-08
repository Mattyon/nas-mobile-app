import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── Language switching ─────────────────────────────────────────────────────

  group('i18n — language switching', () {
    test('switches EN → CS', () {
      lang.value = 'en';
      expect(tr('login'), 'Log in');
      lang.value = 'cs';
      expect(tr('login'), 'Přihlásit se');
    });

    test('switches CS → EN', () {
      lang.value = 'cs';
      expect(tr('search'), 'Hledat');
      lang.value = 'en';
      expect(tr('search'), 'Search');
    });

    test('falls back to key for unknown string', () {
      lang.value = 'en';
      expect(tr('nonexistent_key'), 'nonexistent_key');
    });

    test('unknown language falls back to key', () {
      lang.value = 'xx';
      expect(tr('login'), 'login');
    });

    test('toggleLang flips EN to CS', () {
      lang.value = 'en';
      toggleLang();
      expect(lang.value, 'cs');
    });

    test('toggleLang flips CS to EN', () {
      lang.value = 'cs';
      toggleLang();
      expect(lang.value, 'en');
    });

    test('toggleLang is idempotent on round-trip', () {
      lang.value = 'en';
      toggleLang();
      toggleLang();
      expect(lang.value, 'en');
    });
  });

  // ── Baseline translation keys are present and non-empty ───────────────────

  group('i18n — baseline keys non-empty', () {
    const baselineKeys = <String>[
      'app', 'login', 'logout', 'username', 'password', 'serverUrl',
      'search', 'searchHint', 'movie', 'tv',
      'downloads', 'library',
      'fast', 'balanced', 'best', 'pickQuality', 'download',
      'delete', 'deleteConfirm', 'cancel',
      'added', 'deleted', 'noResults', 'onDisk',
      'language', 'loginFailed', 'adminOnly',
    ];

    for (final key in baselineKeys) {
      test('EN "$key" is non-empty and translated', () {
        lang.value = 'en';
        final v = tr(key);
        expect(v, isNotEmpty, reason: 'EN key "$key" must not be empty');
        expect(v, isNot(equals(key)),
            reason: 'EN key "$key" must be translated (not fall back to key)');
      });

      test('CS "$key" is non-empty and translated', () {
        lang.value = 'cs';
        final v = tr(key);
        expect(v, isNotEmpty, reason: 'CS key "$key" must not be empty');
        expect(v, isNot(equals(key)),
            reason: 'CS key "$key" must be translated (not fall back to key)');
      });
    }
  });
}
