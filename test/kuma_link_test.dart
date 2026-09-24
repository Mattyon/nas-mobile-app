import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/main.dart';

/// The menu's Uptime Kuma link.
///
/// Kuma listens on port 3001 inside the Docker network and is not reachable from
/// outside it, so the link has to be a Cloudflare Tunnel hostname rather than an
/// address. A LAN IP would fail from a phone on mobile data, and the home AP's
/// client isolation makes it unreliable even on wifi — which is exactly why the
/// other two URLs the app ships with are tunnel hostnames too.
///
/// openExternalUrl exists so the menu can tell the user when a tap went nowhere.
/// The help sheet's _LinkRow swallows that case; for a menu item, silently doing
/// nothing is indistinguishable from a broken build.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('plugins.flutter.io/url_launcher');

  /// Stand in for the platform. [canLaunch] drives what the device claims it can
  /// open; every call is recorded so the test can assert nothing was launched.
  List<MethodCall> mockLauncher({required bool canLaunch, bool launchOk = true}) {
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      if (call.method == 'canLaunch') return canLaunch;
      if (call.method == 'launch') return launchOk;
      return null;
    });
    return calls;
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('the Kuma URL', () {
    test('it is the Cloudflare Tunnel hostname', () {
      expect(Api.I.kumaUrl, 'https://kuma.mattyzem.com');
    });

    test('it is HTTPS, not a bare LAN address', () {
      // The whole point of routing it through the tunnel: :3001 on an IP is not
      // reachable from a phone off the home network.
      final Uri u = Uri.parse(Api.I.kumaUrl);
      expect(u.scheme, 'https');
      expect(u.host, 'kuma.mattyzem.com');
      expect(u.hasPort, isFalse);
    });

    test('it has no trailing slash', () {
      expect(Api.I.kumaUrl.endsWith('/'), isFalse);
    });

    test('it is its own host, not the gateway or Jellyfin', () {
      expect(Api.I.kumaUrl, isNot(equals(Api.I.baseUrl)));
      expect(Api.I.kumaUrl, isNot(equals(Api.I.jellyfinUrl)));
    });
  });

  group('openExternalUrl', () {
    test('it launches when the device can handle the URL', () async {
      final List<MethodCall> calls = mockLauncher(canLaunch: true);
      expect(await openExternalUrl(Api.I.kumaUrl), isTrue);
      expect(calls.map((MethodCall c) => c.method), contains('launch'));
      expect(calls.last.arguments['url'], Api.I.kumaUrl);
    });

    test('it reports failure and launches nothing when it cannot', () async {
      // The caller shows a message on false — so returning true here would turn a
      // dead link into a tap that appears to work.
      final List<MethodCall> calls = mockLauncher(canLaunch: false);
      expect(await openExternalUrl(Api.I.kumaUrl), isFalse);
      expect(calls.map((MethodCall c) => c.method), isNot(contains('launch')));
    });

    test('it reports failure when the launch itself is refused', () async {
      final List<MethodCall> calls = mockLauncher(canLaunch: true, launchOk: false);
      expect(await openExternalUrl(Api.I.kumaUrl), isFalse);
      expect(calls.map((MethodCall c) => c.method), contains('launch'));
    });

    test('it opens externally rather than in an in-app webview', () async {
      // Kuma is a full dashboard with its own login; an in-app webview would lose
      // the session every time the menu item is tapped.
      // LaunchMode.externalApplication maps to useWebView:false on Android.
      final List<MethodCall> calls = mockLauncher(canLaunch: true);
      await openExternalUrl(Api.I.kumaUrl);
      final MethodCall launch =
          calls.firstWhere((MethodCall c) => c.method == 'launch');
      expect(launch.arguments['useWebView'], isFalse);
    });
  });

  group('i18n', () {
    for (final String code in <String>['en', 'cs']) {
      test('$code has the failure message', () {
        lang.value = code;
        expect(tr('kumaOpenFailed'), isNotEmpty);
        expect(tr('kumaOpenFailed'), isNot(equals('kumaOpenFailed')));
      });
    }

    test('the two locales actually differ', () {
      lang.value = 'en';
      final String en = tr('kumaOpenFailed');
      lang.value = 'cs';
      expect(tr('kumaOpenFailed'), isNot(equals(en)));
    });

    test('both name the product so the message is actionable', () {
      for (final String code in <String>['en', 'cs']) {
        lang.value = code;
        expect(tr('kumaOpenFailed'), contains('Kuma'));
      }
    });
  });

  /// The manifest half of the feature, and the reason the first build of this link
  /// did nothing at all when tapped.
  ///
  /// Android 11 (API 30) hides every other installed app from a package unless it
  /// declares what it needs to see. Without a VIEW/https <intent> in <queries>,
  /// url_launcher's canLaunchUrl returns false even with Chrome installed, so every
  /// external link fails closed and silently — the menu item simply does nothing.
  /// The app shipped that way: the help sheet's links were already dead.
  ///
  /// This is untestable through the widget layer (the mock launcher answers whatever
  /// it is told), so it is asserted against the manifest itself.
  group('AndroidManifest package visibility', () {
    final String manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    test('it declares a <queries> block at all', () {
      expect(manifest.contains('<queries>'), isTrue);
    });

    test('it can see apps that handle https, or every link dies silently', () {
      final RegExp intent = RegExp(
          r'<intent>(?:(?!</intent>).)*android\.intent\.action\.VIEW'
          r'(?:(?!</intent>).)*android:scheme="https"(?:(?!</intent>).)*</intent>',
          dotAll: true);
      expect(intent.hasMatch(manifest), isTrue,
          reason: 'canLaunchUrl returns false on Android 11+ without this');
    });

    test('http is covered too', () {
      // A self-hosted service on a LAN address is plain http.
      final RegExp intent = RegExp(
          r'<intent>(?:(?!</intent>).)*android\.intent\.action\.VIEW'
          r'(?:(?!</intent>).)*android:scheme="http"(?:(?!</intent>).)*</intent>',
          dotAll: true);
      expect(intent.hasMatch(manifest), isTrue);
    });

    test('the existing PROCESS_TEXT query is still there', () {
      // It is what the Flutter engine's ProcessTextPlugin needs; the fix added to
      // the block rather than replacing it.
      expect(manifest.contains('android.intent.action.PROCESS_TEXT'), isTrue);
    });
  });
}
