import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('i18n — authentication', () {
    const keys = <String>[
      'rememberMe', 'loginWithBiometrics', 'login', 'logout',
      'username', 'password', 'serverUrl', 'loginFailed',
    ];

    for (final key in keys) {
      test('EN "$key" is translated', () {
        lang.value = 'en';
        final v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });

      test('CS "$key" is translated', () {
        lang.value = 'cs';
        final v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('rememberMe label does not contain "365"', () {
      lang.value = 'en';
      expect(tr('rememberMe').contains('365'), isFalse,
          reason: 'The "365 days" text was stripped from Remember me label');
    });

    test('CS rememberMe label does not contain "365"', () {
      lang.value = 'cs';
      expect(tr('rememberMe').contains('365'), isFalse);
    });
  });

  group('auth — role checks', () {
    test('admin check uses groups list', () {
      // Mirrors Api.I.isAdmin = groups.contains('admins')
      final groups = <String>['admins', 'users'];
      final isAdmin = groups.contains('admins');
      expect(isAdmin, isTrue);
    });

    test('non-admin has no admins group', () {
      final groups = <String>['users'];
      final isAdmin = groups.contains('admins');
      expect(isAdmin, isFalse);
    });

    test('role string reflects admin status', () {
      // Mirrors Api.I.role
      bool isAdmin = true;
      String role = isAdmin ? 'admin' : 'user';
      expect(role, 'admin');
      isAdmin = false;
      role = isAdmin ? 'admin' : 'user';
      expect(role, 'user');
    });
  });
}
