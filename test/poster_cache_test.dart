import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/main.dart';

/// Posters were drawn with `Image.network`, whose cache is memory-only: it is cleared
/// on every app start, so a cold launch re-downloaded every poster.
///
/// Two separate problems were fixed, and they are worth keeping separate. Caching
/// stops the repeated download. The decode cap stops something else entirely: the
/// gateway hands out full-size artwork — a TVDB poster is typically 680x1000 and
/// 100-200 KB — and the list draws it at 46x69, so without a cap each row decoded a
/// full-resolution bitmap to paint a thumbnail.
void main() {
  Future<void> pumpPoster(WidgetTester tester, String? url) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PosterImage(url))));
  }

  group('PosterImage', () {
    testWidgets('a poster URL is loaded through the cache, not straight off the network',
        (WidgetTester tester) async {
      await pumpPoster(tester, 'https://artworks.thetvdb.com/banners/posters/72449-4.jpg');
      expect(find.byType(CachedNetworkImage), findsOneWidget);
      final CachedNetworkImage img =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(img.imageUrl, 'https://artworks.thetvdb.com/banners/posters/72449-4.jpg');
    });

    testWidgets('the decoded copy is capped well below the source resolution',
        (WidgetTester tester) async {
      await pumpPoster(tester, 'https://example.test/poster.jpg');
      final CachedNetworkImage img =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(img.memCacheWidth, isNotNull,
          reason: 'without this the full 680px bitmap is held to draw a 46px thumbnail');
      expect(img.memCacheWidth!, lessThan(680));
      // maxWidthDiskCache is deliberately absent: it writes a resized file *beside*
      // the original rather than replacing it, which doubled the cache on-device.
      expect(img.maxWidthDiskCache, isNull);
    });

    testWidgets('the cap still leaves room for a high-density screen',
        (WidgetTester tester) async {
      // The other failure mode: capping at the logical size, which looks correct on a
      // 1x screen and blurry on every real phone. 46 logical px needs 184 at 4x.
      await pumpPoster(tester, 'https://example.test/poster.jpg');
      final CachedNetworkImage img =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(img.memCacheWidth!, greaterThanOrEqualTo(184));
    });

    testWidgets('the widget keeps its row-sized footprint', (WidgetTester tester) async {
      await pumpPoster(tester, 'https://example.test/poster.jpg');
      final CachedNetworkImage img =
          tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
      expect(img.width, 46);
      expect(img.height, 69);
      expect(img.fit, BoxFit.cover);
    });

    testWidgets('a null URL shows the placeholder and fetches nothing',
        (WidgetTester tester) async {
      await pumpPoster(tester, null);
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('an empty URL shows the placeholder and fetches nothing',
        (WidgetTester tester) async {
      // The gateway returns '' for a title with no artwork.
      await pumpPoster(tester, '');
      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
    });

    testWidgets('a missing image still occupies its row rather than collapsing it',
        (WidgetTester tester) async {
      await pumpPoster(tester, null);
      final Size size = tester.getSize(find.byIcon(Icons.movie_outlined).first);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });
}
