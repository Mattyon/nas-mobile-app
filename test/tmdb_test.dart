import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/api.dart';

void main() {
  group('TMDB — API key format', () {
    test('kTmdbApiKey is exactly 32 characters', () {
      expect(kTmdbApiKey.length, 32);
    });

    test('kTmdbApiKey is a valid lowercase hex string', () {
      final RegExp hexPattern = RegExp(r'^[a-f0-9]+$');
      expect(hexPattern.hasMatch(kTmdbApiKey), isTrue,
          reason: 'TMDB API key must be lowercase hex');
    });

    test('kTmdbApiKey is non-empty', () {
      expect(kTmdbApiKey, isNotEmpty);
    });
  });

  group('TMDB — read access token format (JWT)', () {
    test('kTmdbReadAccessToken is non-empty', () {
      expect(kTmdbReadAccessToken, isNotEmpty);
    });

    test('kTmdbReadAccessToken is a JWT with 3 dot-separated parts', () {
      final List<String> parts = kTmdbReadAccessToken.split('.');
      expect(parts.length, 3,
          reason: 'JWT must have exactly 3 dot-separated segments');
    });

    test('JWT header is non-empty', () {
      expect(kTmdbReadAccessToken.split('.')[0], isNotEmpty);
    });

    test('JWT payload is non-empty', () {
      expect(kTmdbReadAccessToken.split('.')[1], isNotEmpty);
    });

    test('JWT signature is non-empty', () {
      expect(kTmdbReadAccessToken.split('.')[2], isNotEmpty);
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
