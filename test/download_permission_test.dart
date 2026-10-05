// The per-user Jellyfin download switch in the add/edit-user dialog. The gateway
// side (policy merge, can_download on /users) shipped on 2026-10-03; these pin
// what the app sends, above all that an edit never writes a value it could not
// read.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/user_permissions.dart';

void main() {
  setUp(() => lang.value = 'en');

  group('downloadToSend', () {
    test('a new user gets what the switch shows', () {
      expect(downloadToSend(isEdit: false, initial: true, current: true, touched: false), isTrue);
      expect(downloadToSend(isEdit: false, initial: true, current: false, touched: true), isFalse);
    });

    test('an untouched edit sends nothing', () {
      expect(downloadToSend(isEdit: true, initial: false, current: false, touched: false), isNull);
    });

    test('an unknown setting is never written back unless changed', () {
      expect(downloadToSend(isEdit: true, initial: null, current: true, touched: false), isNull);
      expect(downloadToSend(isEdit: true, initial: null, current: false, touched: true), isFalse);
    });

    test('a real change is sent', () {
      expect(downloadToSend(isEdit: true, initial: true, current: false, touched: true), isFalse);
      expect(downloadToSend(isEdit: true, initial: false, current: true, touched: true), isTrue);
    });

    test('flipped and flipped back sends nothing', () {
      expect(downloadToSend(isEdit: true, initial: true, current: true, touched: true), isNull);
    });
  });

  group('request bodies', () {
    test('create always carries can_download, default on', () {
      expect(Api.createUserBody(username: 'kid', password: 'pw')['can_download'], isTrue);
      expect(Api.createUserBody(username: 'kid', password: 'pw', canDownload: false)['can_download'],
          isFalse);
    });

    test('update omits can_download when unchanged (absent, not null)', () {
      final Map<String, dynamic> b = Api.updateUserBody(displayname: 'S');
      expect(b.containsKey('can_download'), isFalse);
      expect(b.containsKey('password'), isFalse);
    });

    test('update carries can_download when set', () {
      expect(Api.updateUserBody(canDownload: false)['can_download'], isFalse);
      expect(Api.updateUserBody(canDownload: true)['can_download'], isTrue);
    });
  });

  group('switch tile', () {
    Future<void> pump(WidgetTester t, {required bool value, required bool unknown,
        ValueChanged<bool>? onChanged}) =>
        t.pumpWidget(MaterialApp(
            home: Scaffold(
                body: DownloadPermissionTile(
                    value: value, unknown: unknown, onChanged: onChanged))));

    testWidgets('shows the hint and toggles', (WidgetTester t) async {
      bool? got;
      await pump(t, value: true, unknown: false, onChanged: (bool v) => got = v);
      expect(find.text('Can download in Jellyfin'), findsOneWidget);
      expect(find.textContaining('offline viewing'), findsOneWidget);
      await t.tap(find.byType(Switch));
      expect(got, isFalse);
    });

    testWidgets('says so when the setting could not be read', (WidgetTester t) async {
      await pump(t, value: true, unknown: true);
      expect(find.textContaining("Couldn't read the current setting"), findsOneWidget);
    });

    testWidgets('Czech', (WidgetTester t) async {
      lang.value = 'cs';
      await pump(t, value: false, unknown: false);
      expect(find.text('Může stahovat v Jellyfinu'), findsOneWidget);
    });
  });

  test('every new key exists in both languages', () {
    for (final String l in <String>['en', 'cs']) {
      lang.value = l;
      for (final String k in <String>[
        'canDownload', 'canDownloadHint', 'canDownloadUnknown', 'noDownloads',
      ]) {
        expect(tr(k), isNot(k), reason: '$l $k');
      }
    }
  });
}
