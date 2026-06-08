import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── Language switching ─────────────────────────────────────────────────────

  group('i18n — language switching', () {
    test('switches between EN and CS', () {
      lang.value = 'en';
      expect(tr('login'), 'Log in');
      lang.value = 'cs';
      expect(tr('login'), 'Přihlásit se');
    });

    test('falls back to key for unknown string', () {
      lang.value = 'en';
      expect(tr('nonexistent_key'), 'nonexistent_key');
    });

    test('unknown language falls back to key', () {
      lang.value = 'xx';
      expect(tr('login'), 'login');
    });
  });

  // ── All translation keys are non-empty ─────────────────────────────────────

  group('i18n — no empty values', () {
    const keys = <String>[
      // auth
      'login', 'logout', 'username', 'password', 'serverUrl', 'rememberMe',
      'loginWithBiometrics',
      // nav / common
      'search', 'downloads', 'library', 'ok', 'cancel', 'error', 'app',
      // health check
      'healthCheck', 'healthCheckRunning', 'healthCheckNever', 'healthCheckOk',
      'healthCheckIssues', 'healthCheckWarnings', 'healthCheckLastRun',
      'healthCheckDuration', 'healthCheckStalled', 'healthCheckMissing',
      'healthCheckSmall', 'healthCheckNotImported', 'healthCheckQbtError',
      'healthCheckSonarr', 'healthCheckRadarr',
      'aiFix', 'aiFixing', 'aiFixResult', 'aiFixFailed',
      // media sessions
      'mediaSessions', 'noSessions',
      // help screen
      'helpConnect', 'helpHomeNetwork', 'helpAnywhere',
      'helpTvTitle', 'helpTvStep1', 'helpTvStep2', 'helpTvStep3',
      'helpTvStep4local', 'helpTvStep4remote', 'helpTvStep5',
      'helpMobileTitle', 'helpMobileStep1', 'helpMobileStep2local',
      'helpMobileStep2remote', 'helpMobileStep3',
      'helpBrowserTitle', 'helpBrowserStep1', 'helpBrowserStep2local',
      'helpBrowserStep2remote', 'helpBrowserStep3',
      'helpJellyfinDownload', 'helpJellyfinAndroid', 'helpJellyfinIos',
      // user management
      'userManagement', 'noUsers',
    ];

    for (final key in keys) {
      test('EN "$key" is non-empty', () {
        lang.value = 'en';
        final v = tr(key);
        expect(v, isNotEmpty, reason: 'EN key "$key" must not be empty');
        expect(v, isNot(equals(key)), reason: 'EN key "$key" must be translated (not fall back to key)');
      });

      test('CS "$key" is non-empty', () {
        lang.value = 'cs';
        final v = tr(key);
        expect(v, isNotEmpty, reason: 'CS key "$key" must not be empty');
        expect(v, isNot(equals(key)), reason: 'CS key "$key" must be translated (not fall back to key)');
      });
    }
  });

  // ── Category label mapping completeness ───────────────────────────────────
  // Mirrors the _categoryLabel() switch in main.dart so adding a new health
  // check category without a translation key fails fast in tests.

  group('i18n — health check category labels exist', () {
    const categoryToKey = <String, String>{
      'stalled':           'healthCheckStalled',
      'missing_file':      'healthCheckMissing',
      'small_file':        'healthCheckSmall',
      'not_imported':      'healthCheckNotImported',
      'torrent_error':     'healthCheckQbtError',
      'sonarr':            'healthCheckSonarr',
      'radarr':            'healthCheckRadarr',
    };

    for (final entry in categoryToKey.entries) {
      test('category "${entry.key}" → key "${entry.value}" exists in EN', () {
        lang.value = 'en';
        final v = tr(entry.value);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(entry.value)));
      });

      test('category "${entry.key}" → key "${entry.value}" exists in CS', () {
        lang.value = 'cs';
        final v = tr(entry.value);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(entry.value)));
      });
    }
  });
}
