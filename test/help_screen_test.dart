import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/main.dart' show HelpScreen;

void main() {
  group('i18n — help screen top-level keys', () {
    const List<String> keys = <String>[
      'helpConnect', 'helpHomeNetwork', 'helpAnywhere', 'helpServerAddr',
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

    test('helpHomeNetwork and helpAnywhere are different', () {
      lang.value = 'en';
      expect(tr('helpHomeNetwork'), isNot(equals(tr('helpAnywhere'))));
    });
  });

  group('i18n — help screen TV steps', () {
    const List<String> keys = <String>[
      'helpTvTitle', 'helpTvStep1', 'helpTvStep2', 'helpTvStep3',
      'helpTvStep4local', 'helpTvStep4remote', 'helpTvStep5',
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

    test('local and remote TV step 4 are different (different addresses)', () {
      lang.value = 'en';
      expect(tr('helpTvStep4local'), isNot(equals(tr('helpTvStep4remote'))));
    });

    test('local TV step 4 contains local IP', () {
      lang.value = 'en';
      expect(tr('helpTvStep4local').contains('192.168'), isTrue);
    });

    test('remote TV step 4 contains Cloudflare domain', () {
      lang.value = 'en';
      expect(tr('helpTvStep4remote').contains('jellyfin.mattyzem.com'), isTrue);
    });
  });

  group('i18n — help screen Mobile steps', () {
    const List<String> keys = <String>[
      'helpMobileTitle', 'helpMobileStep1',
      'helpMobileStep2local', 'helpMobileStep2remote', 'helpMobileStep3',
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

    test('local and remote mobile step 2 are different', () {
      lang.value = 'en';
      expect(tr('helpMobileStep2local'), isNot(equals(tr('helpMobileStep2remote'))));
    });
  });

  group('i18n — help screen Browser steps', () {
    const List<String> keys = <String>[
      'helpBrowserTitle', 'helpBrowserStep1',
      'helpBrowserStep2local', 'helpBrowserStep2remote', 'helpBrowserStep3',
    ];

    for (final String key in keys) {
      test('EN "$key" translated', () {
        lang.value = 'en';
        final String v = tr(key);
        expect(v, isNotEmpty);
        expect(v, isNot(equals(key)));
      });
    }

    test('local and remote browser step 2 are different', () {
      lang.value = 'en';
      expect(tr('helpBrowserStep2local'), isNot(equals(tr('helpBrowserStep2remote'))));
    });
  });

  group('i18n — Jellyfin download link keys', () {
    const List<String> keys = <String>[
      'helpJellyfinDownload', 'helpJellyfinAndroid', 'helpJellyfinIos',
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

    test('Android and iOS download labels are different', () {
      lang.value = 'en';
      expect(tr('helpJellyfinAndroid'), isNot(equals(tr('helpJellyfinIos'))));
    });
  });

  group('help screen — copying the server address', () {
    String? copied;

    setUp(() {
      copied = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    testWidgets('the remote address is copied and confirmed', (WidgetTester tester) async {
      lang.value = 'en';
      await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
      await tester.tap(find.byIcon(Icons.copy).first);
      await tester.pump();
      expect(copied, 'https://jellyfin.mattyzem.com');
      expect(find.text('Address copied'), findsOneWidget);
    });

    testWidgets('the home network address is copied', (WidgetTester tester) async {
      lang.value = 'en';
      await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
      await tester.tap(find.text('Home network'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.copy).first);
      await tester.pump();
      expect(copied, 'http://192.168.50.141:8096');
    });

    test('copy labels translated', () {
      for (final String l in <String>['en', 'cs']) {
        lang.value = l;
        for (final String key in <String>['copy', 'copiedAddress']) {
          expect(tr(key), isNot(equals(key)));
        }
      }
    });
  });
}
