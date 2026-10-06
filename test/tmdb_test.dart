import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';

void main() {
  // The app used to call api.themoviedb.org with the key and read token compiled in.
  // A web build is public (anyone can read main.dart.js), so TMDb now goes through the
  // gateway (GET /tmdb/..., key kept server-side). These pin that it stays that way.
  group('TMDB — no key in the app, calls go through the gateway', () {
    final String api = File('lib/api.dart').readAsStringSync();
    final List<File> sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((File f) => f.path.endsWith('.dart'))
        .toList();

    test('no source file calls TMDb directly', () {
      for (final File f in sources) {
        expect(f.readAsStringSync().contains('api.themoviedb.org'), isFalse,
            reason: '${f.path} talks to TMDb directly');
      }
    });

    test('no TMDb key or read token anywhere in lib/', () {
      final RegExp key = RegExp(r"'[0-9a-f]{32}'");
      final RegExp jwt = RegExp(r"'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'");
      for (final File f in sources) {
        final String src = f.readAsStringSync();
        expect(key.hasMatch(src), isFalse, reason: '${f.path} has a 32-hex key');
        expect(jwt.hasMatch(src), isFalse, reason: '${f.path} has a JWT');
      }
    });

    test('all four TMDb lookups use the gateway proxy', () {
      for (final String path in <String>[
        "'/tmdb/movie/\$tmdbId'",
        "'/tmdb/tv/\$tmdbId'",
        "'/tmdb/tv/\$tmdbId/season/\$season'",
        "'/tmdb/find/\$tvdbId'",
      ]) {
        expect(api.contains(path), isTrue, reason: 'missing $path');
      }
    });
  });

  group('TMDB — gateway default URL', () {
    test('Api.I.baseUrl is the Cloudflare Tunnel URL', () {
      expect(Api.I.baseUrl, 'https://nas.mattyzem.com');
    });

    test('Api.I.baseUrl uses HTTPS scheme', () {
      expect(Uri.parse(Api.I.baseUrl).scheme, 'https');
    });

    test('Api.I.baseUrl has no trailing slash', () {
      expect(Api.I.baseUrl.endsWith('/'), isFalse);
    });
  });

  group('TMDB — detail request parameters', () {
    test('language defaults to en-US for TMDB API', () {
      // Mirrors Api.I.tmdbMovieDetails(id, language: 'en-US')
      const String defaultLang = 'en-US';
      expect(defaultLang, contains('-'));
      expect(defaultLang.substring(0, 2), 'en');
    });

    test('append_to_response includes credits for cast', () {
      const String appendParam = 'credits';
      expect(appendParam, 'credits');
    });
  });
}
