// Seasons and episodes on the show detail. These used to come only from Sonarr,
// so a show that was not in the library showed no seasons at all. They now come
// from TMDb for every show, with Sonarr's file status laid over them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/season.dart';

Map<String, dynamic> tmdbSeason(int n, int count, {String? air}) =>
    <String, dynamic>{
      'season_number': n,
      'name': n == 0 ? 'Specials' : 'Season $n',
      'episode_count': count,
      'air_date': air,
    };

Map<String, dynamic> tmdbEp(int n,
        {String? name, String? overview, String? air = '2019-01-01'}) =>
    <String, dynamic>{
      'episode_number': n,
      'name': name ?? 'Title $n',
      'overview': overview ?? '',
      'air_date': air,
      'runtime': 42,
      'vote_average': 8.14,
      'vote_count': 10,
    };

Map<String, dynamic> sonarrEp(int n, {bool file = true, int res = 1080}) =>
    <String, dynamic>{
      'n': n,
      'title': 'Sonarr $n',
      'air_date': '2019-01-01',
      'has_file': file,
      'quality': file ? 'WEBDL-${res}p' : null,
      'resolution': file ? res : null,
    };

void main() {
  setUp(() => lang.value = 'en');

  group('mergeSeasons', () {
    test('a show outside the library still gets its seasons, from TMDb', () {
      final List<Map<String, dynamic>> s = mergeSeasons(<dynamic>[
        tmdbSeason(1, 10, air: '2019-05-03'),
        tmdbSeason(2, 8),
      ], <dynamic>[]);
      expect(s.map((Map<String, dynamic> x) => x['season']), <int>[1, 2]);
      expect(s.first['episode_count'], 10);
      expect(s.first['have'], isNull, reason: 'no library badge for a show not in Sonarr');
    });

    test('specials go last, empty announced seasons are dropped', () {
      final List<Map<String, dynamic>> s = mergeSeasons(<dynamic>[
        tmdbSeason(0, 3),
        tmdbSeason(1, 10),
        tmdbSeason(2, 0),
      ], <dynamic>[]);
      expect(s.map((Map<String, dynamic> x) => x['season']), <int>[1, 0]);
    });

    test('library shows carry downloaded/total from Sonarr', () {
      final List<Map<String, dynamic>> s = mergeSeasons(<dynamic>[
        tmdbSeason(1, 3),
      ], <dynamic>[
        <String, dynamic>{
          'season': 1,
          'episodes': <dynamic>[sonarrEp(1), sonarrEp(2), sonarrEp(3, file: false)],
        },
      ]);
      expect(s.single['have'], 2);
      expect(s.single['total'], 3);
      expect((s.single['episodes'] as List<dynamic>).length, 3);
    });

    test('a season only Sonarr knows is still listed', () {
      final List<Map<String, dynamic>> s = mergeSeasons(<dynamic>[], <dynamic>[
        <String, dynamic>{'season': 4, 'episodes': <dynamic>[sonarrEp(1)]},
      ]);
      expect(s.single['season'], 4);
      expect(s.single['episode_count'], 1);
    });
  });

  group('mergeEpisodes', () {
    test('file status comes from Sonarr, everything else from TMDb', () {
      final List<Map<String, dynamic>> e = mergeEpisodes(
          <dynamic>[tmdbEp(1, overview: 'Pilot.'), tmdbEp(2)],
          <dynamic>[],
          <dynamic>[sonarrEp(1, res: 720), sonarrEp(2, file: false)]);
      expect(e[0]['title'], 'Title 1');
      expect(e[0]['overview'], 'Pilot.');
      expect(e[0]['has_file'], isTrue);
      expect(e[0]['quality'], 'WEBDL-720p');
      expect(e[0]['rating'], closeTo(8.14, 0.001));
      expect(e[1]['has_file'], isFalse);
      expect(e[1]['overview'], isNull, reason: 'empty overview is no overview');
    });

    test('Czech placeholder names fall back to English, then Sonarr', () {
      final List<Map<String, dynamic>> e = mergeEpisodes(
        <dynamic>[
          tmdbEp(1, name: 'Epizoda 1'),
          tmdbEp(2, name: 'Epizoda 2'),
          tmdbEp(3, name: 'Útěk'),
        ],
        <dynamic>[
          tmdbEp(1, name: 'Pilot', overview: 'English overview'),
          tmdbEp(2, name: 'Episode 2'),
          tmdbEp(3, name: 'Escape'),
        ],
        <dynamic>[sonarrEp(2)],
      );
      expect(e[0]['title'], 'Pilot');
      expect(e[0]['overview'], 'English overview');
      expect(e[1]['title'], 'Sonarr 2');
      expect(e[2]['title'], 'Útěk', reason: 'a real translation wins');
    });

    test('no title anywhere gives "Episode n"', () {
      final List<Map<String, dynamic>> e =
          mergeEpisodes(<dynamic>[tmdbEp(5, name: '')], <dynamic>[], null);
      expect(e.single['title'], 'Episode 5');
    });

    test('outside the library nothing claims to be on disk', () {
      final List<Map<String, dynamic>> e =
          mergeEpisodes(<dynamic>[tmdbEp(1)], <dynamic>[], null);
      expect(e.single['in_library'], isFalse);
      expect(e.single['has_file'], isFalse);
    });

    test('episodes only Sonarr lists are kept, in order', () {
      final List<Map<String, dynamic>> e = mergeEpisodes(
          <dynamic>[tmdbEp(2)], <dynamic>[], <dynamic>[sonarrEp(1), sonarrEp(2)]);
      expect(e.map((Map<String, dynamic> x) => x['n']), <int>[1, 2]);
      expect(e[0]['title'], 'Sonarr 1');
    });

    test('no votes means no rating', () {
      final Map<String, dynamic> t = tmdbEp(1)..['vote_count'] = 0;
      expect(mergeEpisodes(<dynamic>[t], <dynamic>[], null).single['rating'],
          isNull);
    });
  });

  group('dates and counts', () {
    test('upcoming', () {
      final DateTime now = DateTime(2026, 10, 4, 15);
      expect(isUpcoming('2026-10-04', now: now), isFalse, reason: 'airs today');
      expect(isUpcoming('2026-10-05', now: now), isTrue);
      expect(isUpcoming('2019-01-01', now: now), isFalse);
      expect(isUpcoming(null, now: now), isTrue, reason: 'announced, no date');
    });

    test('air date per language', () {
      expect(formatAirDate('2019-05-03'), '3 May 2019');
      lang.value = 'cs';
      expect(formatAirDate('2019-05-03'), '3. 5. 2019');
      expect(formatAirDate('soon'), 'soon');
    });

    test('Czech plural forms', () {
      lang.value = 'cs';
      expect(trCount('episodes', 1), '1 díl');
      expect(trCount('episodes', 3), '3 díly');
      expect(trCount('episodes', 5), '5 dílů');
      expect(trCount('seasons', 2), '2 sezóny');
      expect(trCount('seasons', 7), '7 sezón');
      lang.value = 'en';
      expect(trCount('episodes', 1), '1 episode');
      expect(trCount('episodes', 3), '3 episodes');
    });

    test('season labels', () {
      expect(seasonLabel(<String, dynamic>{'season': 3}), 'Season 3');
      expect(seasonLabel(<String, dynamic>{'season': 0}), 'Specials');
      lang.value = 'cs';
      expect(seasonLabel(<String, dynamic>{'season': 3}), '3. sezóna');
    });

    test('meta line', () {
      expect(episodeMeta(<String, dynamic>{
        'air_date': '2019-05-03', 'runtime': 42, 'rating': 8.14,
      }), '3 May 2019 · 42m · ★ 8.1');
      expect(episodeMeta(<String, dynamic>{'air_date': '2999-01-02'}),
          'Airs 2 Jan 2999');
    });
  });

  group('every new key exists in both languages', () {
    const List<String> keys = <String>[
      'seasonN', 'specials', 'episodeN', 'episodesOne', 'episodesFew',
      'episodesMany', 'seasonsOne', 'seasonsFew', 'seasonsMany', 'airsOn',
      'notYetAired', 'onDiskQuality', 'notOnDisk', 'noOverview',
      'seasonLoadFailed', 'retry',
    ];
    for (final String l in <String>['en', 'cs']) {
      for (final String k in keys) {
        test('$l $k', () {
          lang.value = l;
          expect(tr(k), isNot(k));
        });
      }
    }
  });

  group('season screen', () {
    Widget app(Widget child) => MaterialApp(home: child);

    final Map<String, dynamic> librarySeason = <String, dynamic>{
      'season': 1,
      'episode_count': 2,
      'episodes': <dynamic>[sonarrEp(1), sonarrEp(2, file: false)],
      'have': 1,
      'total': 2,
    };

    testWidgets('lists episodes and opens one', (WidgetTester t) async {
      final List<String> asked = <String>[];
      await t.pumpWidget(app(SeasonScreen(
        showTitle: 'Show',
        tmdbId: 7,
        season: librarySeason,
        loader: (int s, String l) async {
          asked.add('$s/$l');
          return <String, dynamic>{
            'overview': 'Season overview.',
            'episodes': <dynamic>[
              tmdbEp(1, overview: 'The beginning.'),
              tmdbEp(2, name: 'Second'),
            ],
          };
        },
      )));
      await t.pumpAndSettle();
      expect(asked, <String>['1/en-US']);
      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season overview.'), findsOneWidget);
      expect(find.text('1. Title 1'), findsOneWidget);
      expect(find.text('2. Second'), findsOneWidget);
      expect(find.text('1 of 2 episodes downloaded'), findsOneWidget);

      await t.tap(find.text('1. Title 1'));
      await t.pumpAndSettle();
      expect(find.text('S01 · E01'), findsOneWidget);
      expect(find.text('On disk · WEBDL-1080p'), findsOneWidget);
      expect(find.text('The beginning.'), findsWidgets);

      await t.tapAt(const Offset(10, 10)); // dismiss the sheet
      await t.pumpAndSettle();
      await t.tap(find.text('2. Second'));
      await t.pumpAndSettle();
      expect(find.text('Not on disk'), findsOneWidget);
      expect(find.text('No description yet.'), findsOneWidget);
    });

    testWidgets('Czech asks for Czech and English', (WidgetTester t) async {
      lang.value = 'cs';
      final List<String> asked = <String>[];
      await t.pumpWidget(app(SeasonScreen(
        showTitle: 'Show',
        tmdbId: 7,
        season: librarySeason,
        loader: (int s, String l) async {
          asked.add(l);
          return <String, dynamic>{
            'episodes': <dynamic>[
              tmdbEp(1, name: l == 'cs-CZ' ? 'Epizoda 1' : 'Pilot'),
            ],
          };
        },
      )));
      await t.pumpAndSettle();
      expect(asked..sort(), <String>['cs-CZ', 'en-US']);
      expect(find.text('1. Pilot'), findsOneWidget);
      expect(find.text('1. sezóna'), findsOneWidget);
    });

    testWidgets('TMDb down: Sonarr episodes and a retry', (WidgetTester t) async {
      int calls = 0;
      await t.pumpWidget(app(SeasonScreen(
        showTitle: 'Show',
        tmdbId: 7,
        season: librarySeason,
        loader: (int s, String l) async {
          calls++;
          if (calls == 1) throw Exception('offline');
          return <String, dynamic>{'episodes': <dynamic>[tmdbEp(1)]};
        },
      )));
      await t.pumpAndSettle();
      expect(find.text("Couldn't load the episodes."), findsOneWidget);
      expect(find.text('1. Sonarr 1'), findsOneWidget);
      await t.tap(find.text('Retry'));
      await t.pumpAndSettle();
      expect(find.text("Couldn't load the episodes."), findsNothing);
      expect(find.text('1. Title 1'), findsOneWidget);
    });

    testWidgets('no TMDb id: Sonarr only, no network', (WidgetTester t) async {
      await t.pumpWidget(app(SeasonScreen(
        showTitle: 'Show',
        tmdbId: 0,
        season: librarySeason,
        loader: (int s, String l) async => throw StateError('must not load'),
      )));
      await t.pumpAndSettle();
      expect(find.text('1. Sonarr 1'), findsOneWidget);
      expect(find.text('2. Sonarr 2'), findsOneWidget);
    });

    testWidgets('season tile shows count and library badge', (WidgetTester t) async {
      bool tapped = false;
      await t.pumpWidget(app(Scaffold(
        body: SeasonTile(
          season: <String, dynamic>{
            'season': 2, 'air_date': '2021-03-01', 'episode_count': 10,
            'have': 3, 'total': 10,
          },
          onTap: () => tapped = true,
        ),
      )));
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('2021 · 10 episodes'), findsOneWidget);
      expect(find.text('3/10'), findsOneWidget);
      await t.tap(find.text('Season 2'));
      expect(tapped, isTrue);
    });
  });
}
