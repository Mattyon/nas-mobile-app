import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';
import 'package:nas_app/i18n.dart';

void main() {
  group('default gateway URL — Cloudflare Tunnel', () {
    test('Api.I.baseUrl is the Cloudflare NAS gateway', () {
      expect(Api.I.baseUrl, 'https://nas.mattyzem.com');
    });

    test('Api.I.baseUrl uses HTTPS', () {
      expect(Uri.parse(Api.I.baseUrl).scheme, 'https');
    });

    test('Api.I.baseUrl has no trailing slash', () {
      expect(Api.I.baseUrl.endsWith('/'), isFalse);
    });

    test('Api.I.baseUrl host is nas.mattyzem.com', () {
      expect(Uri.parse(Api.I.baseUrl).host, 'nas.mattyzem.com');
    });
  });

  group('i18n — help screen contains Cloudflare addresses', () {
    test('remote TV step 4 references jellyfin.mattyzem.com', () {
      lang.value = 'en';
      expect(tr('helpTvStep4remote').contains('jellyfin.mattyzem.com'), isTrue);
    });

    test('remote mobile step 2 references jellyfin.mattyzem.com', () {
      lang.value = 'en';
      expect(tr('helpMobileStep2remote').contains('jellyfin.mattyzem.com'), isTrue);
    });

    test('remote browser step 2 references jellyfin.mattyzem.com', () {
      lang.value = 'en';
      expect(tr('helpBrowserStep2remote').contains('jellyfin.mattyzem.com'), isTrue);
    });

    test('NAS app URL hint references nas.mattyzem.com', () {
      lang.value = 'en';
      expect(tr('helpNasAppUrl').contains('nas.mattyzem.com'), isTrue);
    });
  });

  group('i18n — help screen contains local IP addresses', () {
    test('local TV step 4 references 192.168.50.141:8096', () {
      lang.value = 'en';
      expect(tr('helpTvStep4local').contains('192.168.50.141'), isTrue);
    });

    test('local browser step 2 references 192.168.50.141:8096', () {
      lang.value = 'en';
      expect(tr('helpBrowserStep2local').contains('192.168.50.141'), isTrue);
    });
  });
}
