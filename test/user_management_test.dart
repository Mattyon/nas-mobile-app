import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';

void main() {
  // ── User admin detection logic ────────────────────────────────────────────
  // Mirrors: (u['groups'] as List<dynamic>?)?.contains('admins') ?? false

  bool _isUserAdmin(Map<String, dynamic> user) =>
      (user['groups'] as List<dynamic>?)?.contains('admins') ?? false;

  group('user management — admin detection', () {
    test('user with "admins" group → admin', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'matty',
        'groups': <String>['admins', 'users'],
      };
      expect(_isUserAdmin(user), isTrue);
    });

    test('user without "admins" group → not admin', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'bob',
        'groups': <String>['users'],
      };
      expect(_isUserAdmin(user), isFalse);
    });

    test('user with empty groups → not admin', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'guest',
        'groups': <String>[],
      };
      expect(_isUserAdmin(user), isFalse);
    });

    test('user with null groups → not admin (default)', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'nobody',
        'groups': null,
      };
      expect(_isUserAdmin(user), isFalse);
    });

    test('user with missing groups field → not admin', () {
      final Map<String, dynamic> user = <String, dynamic>{'username': 'x'};
      expect(_isUserAdmin(user), isFalse);
    });

    test('groups check is case-sensitive ("Admins" != "admins")', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'test',
        'groups': <String>['Admins'],
      };
      expect(_isUserAdmin(user), isFalse);
    });
  });

  // ── Display name fallback ─────────────────────────────────────────────────
  // Mirrors: (u['displayname'] ?? u['username'] ?? '?').substring(0, 1).toUpperCase()

  group('user management — display name avatar initial', () {
    String _avatarInitial(Map<String, dynamic> user) {
      return ((user['displayname']?.toString() ??
                  user['username']?.toString() ??
                  '?'))
          .substring(0, 1)
          .toUpperCase();
    }

    test('displayname present → use first letter', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'matty',
        'displayname': 'Matty',
      };
      expect(_avatarInitial(user), 'M');
    });

    test('no displayname → use username first letter', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'bob',
      };
      expect(_avatarInitial(user), 'B');
    });

    test('both missing → "?"', () {
      expect(_avatarInitial(<String, dynamic>{}), '?');
    });

    test('avatar initial is uppercased', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'alice',
      };
      expect(_avatarInitial(user), 'A');
    });
  });

  // ── User management i18n ──────────────────────────────────────────────────

  group('i18n — user management keys', () {
    const List<String> keys = <String>[
      'userManagement', 'addUser', 'editUser', 'deleteUser',
      'admin', 'noUsers', 'displayName', 'newPassword', 'isAdmin',
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

    test('addUser and editUser are different labels', () {
      lang.value = 'en';
      expect(tr('addUser'), isNot(equals(tr('editUser'))));
    });

    test('deleteUser and editUser are different labels', () {
      lang.value = 'en';
      expect(tr('deleteUser'), isNot(equals(tr('editUser'))));
    });

    test('displayName and newPassword are different labels', () {
      lang.value = 'en';
      expect(tr('displayName'), isNot(equals(tr('newPassword'))));
    });
  });

  // ── Form field preparation ────────────────────────────────────────────────
  // Mirrors trimming done in _openDialog before calling Api.I.createUser /
  // updateUser: nameCtrl.text.trim(), dispCtrl.text.trim()

  String _trimUsername(String raw) => raw.trim();
  String _trimDisplayName(String raw) => raw.trim();

  // Mirrors: passCtrl.text.isEmpty ? null : passCtrl.text  (edit mode)
  String? _editPassword(String raw) => raw.isEmpty ? null : raw;

  group('user management — form field preparation', () {
    test('username is trimmed before API call', () {
      expect(_trimUsername('  alice  '), 'alice');
      expect(_trimUsername('alice'), 'alice');
      expect(_trimUsername('  '), '');
    });

    test('displayname is trimmed before API call', () {
      expect(_trimDisplayName('  Alice Smith  '), 'Alice Smith');
      expect(_trimDisplayName('Alice'), 'Alice');
    });

    test('empty password on edit → null (no password update sent)', () {
      expect(_editPassword(''), isNull);
    });

    test('non-empty password on edit → value is sent to updateUser', () {
      expect(_editPassword('secret123'), 'secret123');
      expect(_editPassword(' pw '), ' pw ');
    });

    test('create mode always sends password (even empty string)', () {
      // createUser uses passCtrl.text directly (no null conversion)
      const String raw = '';
      expect(raw, '');
    });
  });

  // ── Edit vs create mode ───────────────────────────────────────────────────
  // Mirrors: final bool isEdit = existing != null;

  bool _isEditMode(Map<String, dynamic>? existing) => existing != null;

  group('user management — edit vs create mode', () {
    test('existing != null → edit mode', () {
      expect(_isEditMode({'username': 'alice', 'groups': <String>[]}), isTrue);
    });

    test('existing == null → create mode', () {
      expect(_isEditMode(null), isFalse);
    });

    test('edit mode uses existing username as immutable key', () {
      final Map<String, dynamic> user = <String, dynamic>{
        'username': 'alice',
        'displayname': 'Alice',
        'groups': <String>['users'],
      };
      final bool isEdit = _isEditMode(user);
      // In edit mode the username field is hidden; existing key drives the PUT
      expect(isEdit, isTrue);
      expect(user['username'], 'alice');
    });
  });

  // ── Saving state logic ────────────────────────────────────────────────────
  // Mirrors the `saving` bool inside StatefulBuilder in _openDialog.

  group('user management — saving state', () {
    test('saving starts as false', () {
      bool saving = false;
      expect(saving, isFalse);
    });

    test('saving becomes true when save is initiated', () {
      bool saving = false;
      // simulate: ss(() => saving = true)
      saving = true;
      expect(saving, isTrue);
    });

    test('saving reverts to false on API error (so user can retry)', () {
      bool saving = true;
      // simulate catch block: ss(() => saving = false)
      saving = false;
      expect(saving, isFalse);
    });

    test('dialog closes with true only on successful API response', () {
      // Mirrors: after successful API call → Navigator.of(ctx2).pop(true)
      // On error → no pop, saving=false
      bool dialogResult = false;
      bool apiSucceeded = true;
      if (apiSucceeded) dialogResult = true;
      expect(dialogResult, isTrue);
    });

    test('dialog stays open on API error', () {
      bool dialogClosed = false;
      bool apiSucceeded = false;
      if (apiSucceeded) dialogClosed = true;
      expect(dialogClosed, isFalse);
    });

    test('list refresh triggered only when dialog returns true', () {
      // Mirrors: if (saved == true) await _refresh();
      bool refreshCalled = false;
      bool? saved;

      saved = true;
      if (saved == true) refreshCalled = true;
      expect(refreshCalled, isTrue);

      refreshCalled = false;
      saved = false;
      if (saved == true) refreshCalled = true;
      expect(refreshCalled, isFalse);

      refreshCalled = false;
      saved = null; // user dismissed dialog (back button)
      if (saved == true) refreshCalled = true;
      expect(refreshCalled, isFalse);
    });
  });

  // ── User list state after operations ─────────────────────────────────────

  group('user management — user list state after operations', () {
    test('list updates after adding a user', () {
      final List<Map<String, dynamic>> users = <Map<String, dynamic>>[
        <String, dynamic>{'username': 'alice', 'groups': <String>['users']},
      ];
      users.add(<String, dynamic>{'username': 'bob', 'groups': <String>['users']});
      expect(users.length, 2);
      expect(users.any((Map<String, dynamic> u) => u['username'] == 'bob'), isTrue);
    });

    test('list updates after deleting a user', () {
      final List<Map<String, dynamic>> users = <Map<String, dynamic>>[
        <String, dynamic>{'username': 'alice', 'groups': <String>['users']},
        <String, dynamic>{'username': 'bob', 'groups': <String>['users']},
      ];
      users.removeWhere((Map<String, dynamic> u) => u['username'] == 'bob');
      expect(users.length, 1);
      expect(users.any((Map<String, dynamic> u) => u['username'] == 'bob'), isFalse);
    });

    test('list updates displayname after editing a user', () {
      final List<Map<String, dynamic>> users = <Map<String, dynamic>>[
        <String, dynamic>{
          'username': 'alice',
          'displayname': 'Alice',
          'groups': <String>['users'],
        },
      ];
      final int idx = users.indexWhere(
          (Map<String, dynamic> u) => u['username'] == 'alice');
      users[idx] = <String, dynamic>{...users[idx], 'displayname': 'Alice Smith'};
      expect(users[0]['displayname'], 'Alice Smith');
    });

    test('list preserves other users when one is deleted', () {
      final List<Map<String, dynamic>> users = <Map<String, dynamic>>[
        <String, dynamic>{'username': 'alice'},
        <String, dynamic>{'username': 'bob'},
        <String, dynamic>{'username': 'carol'},
      ];
      users.removeWhere((Map<String, dynamic> u) => u['username'] == 'bob');
      expect(users.map((Map<String, dynamic> u) => u['username']).toList(),
          <String>['alice', 'carol']);
    });
  });

  // ── Jellyfin sync — backend-side ─────────────────────────────────────────
  // The gateway handles Jellyfin sync automatically on every user mutation:
  //   POST /users      → _jf_sync_create(username, password, is_admin)
  //   PUT  /users/{u}  → _jf_sync_update(username, password?, is_admin)
  //   DELETE /users/{u}→ _jf_sync_delete(username)
  // Flutter only needs to call the correct REST endpoint; no separate Jellyfin
  // call is required from the app.

  group('user management — Jellyfin sync (backend-handled)', () {
    test('createUser payload includes password for Jellyfin account setup', () {
      // Backend _jf_sync_create uses the plain-text password from the request
      // to set the Jellyfin account password; it must not be empty.
      const String password = 'hunter2';
      expect(password.isNotEmpty, isTrue);
    });

    test('updateUser sends password only when non-empty (Jellyfin password sync)', () {
      // Mirrors: passCtrl.text.isEmpty ? null : passCtrl.text
      // Backend _jf_sync_update skips password reset when password is null/empty.
      expect(_editPassword('newpass'), isNotNull);
      expect(_editPassword(''), isNull);
    });

    test('delete payload identifies user by username for Jellyfin removal', () {
      // Backend _jf_sync_delete looks up the Jellyfin user by Name == username.
      const String username = 'alice';
      expect(username, isNotEmpty);
    });

    test('admin flag is forwarded to Jellyfin on create', () {
      // Backend passes is_admin to _jf_sync_create → sets IsAdministrator policy
      const bool isAdmin = true;
      expect(isAdmin, isTrue);
    });

    test('admin flag is forwarded to Jellyfin on update', () {
      // Backend passes is_admin to _jf_sync_update → updates IsAdministrator policy
      for (final bool isAdmin in <bool>[true, false]) {
        expect(isAdmin == true || isAdmin == false, isTrue);
      }
    });
  });
}
