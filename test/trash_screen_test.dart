import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/trash_screen.dart';

// The Trash screen (admin): titles deleted in the app, restorable until the NAS empties
// its recycle bin.

Map<String, dynamic> _bin({int left = 12}) => <String, dynamic>{
      'days': 14,
      'items': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a1', 'kind': 'movie', 'title': 'Dune', 'year': 2021,
          'size': 8.5e9, 'deleted_at': 1792461600, 'days_left': left},
      ],
    };

Widget _app(TrashScreen s) => MaterialApp(home: s);

void main() {
  setUp(() => lang.value = 'en');

  group('wording, never "(s)"', () {
    test('english days', () {
      expect(daysText(1), '1 day');
      expect(daysText(14), '14 days');
    });
    test('czech days', () {
      lang.value = 'cs';
      expect(daysText(1), '1 den');
      expect(daysText(3), '3 dny');
      expect(daysText(14), '14 dní');
    });
    test('after a delete it says trash, and for how long', () {
      expect(movedToTrashText(14), 'Moved to the trash. Deleted for good in 14 days.');
      lang.value = 'cs';
      expect(movedToTrashText(14), 'Přesunuto do koše. Natrvalo se smaže za 14 dní.');
    });
    test('no "(s)" in any trash text', () {
      for (final String l in <String>['en', 'cs']) {
        lang.value = l;
        for (final String k in <String>['deleteConfirm', 'movedToTrash', 'trash', 'trashEmpty', 'trashError',
          'trashRestore', 'trashRestoreConfirm', 'trashRestored', 'trashRestoreFailed', 'trashDeletedOn',
          'trashLeft', 'trashToday']) {
          expect(tr(k), isNot(equals(k)), reason: '$l $k missing');
          expect(tr(k).contains('(s)'), isFalse, reason: '$l $k');
        }
      }
    });
  });

  testWidgets('lists what is in the trash with days left', (WidgetTester t) async {
    await t.pumpWidget(_app(TrashScreen(load: () async => _bin(), restore: (_) async => <String, dynamic>{})));
    await t.pumpAndSettle();
    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.textContaining('8.5 GB'), findsOneWidget);
    expect(find.textContaining('deleted for good in 12 days'), findsOneWidget);
  });

  testWidgets('restore asks, restores, reloads', (WidgetTester t) async {
    final List<String> restored = <String>[];
    int loads = 0;
    await t.pumpWidget(_app(TrashScreen(
        load: () async { loads++; return loads == 1 ? _bin() : <String, dynamic>{'days': 14, 'items': <dynamic>[]}; },
        restore: (String id) async { restored.add(id); return <String, dynamic>{'ok': true}; })));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('trash-restore-a1')));
    await t.pumpAndSettle();
    expect(find.text('Bring "Dune (2021)" back to the library?'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey<String>('trash-restore-confirm')));
    await t.pumpAndSettle();
    expect(restored, <String>['a1']);
    expect(find.text('"Dune (2021)" is back in the library.'), findsOneWidget);
    expect(find.text(tr('trashEmpty')), findsOneWidget);
  });

  testWidgets('a failed restore is shown', (WidgetTester t) async {
    await t.pumpWidget(_app(TrashScreen(load: () async => _bin(), restore: (_) async => throw Exception('409'))));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('trash-restore-a1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey<String>('trash-restore-confirm')));
    await t.pumpAndSettle();
    expect(find.textContaining('Could not restore it'), findsOneWidget);
  });

  testWidgets('last day says today', (WidgetTester t) async {
    await t.pumpWidget(_app(TrashScreen(load: () async => _bin(left: 0), restore: (_) async => <String, dynamic>{})));
    await t.pumpAndSettle();
    expect(find.textContaining(tr('trashToday')), findsOneWidget);
  });

  testWidgets('empty and error states', (WidgetTester t) async {
    await t.pumpWidget(_app(TrashScreen(load: () async => <String, dynamic>{'items': <dynamic>[]}, restore: (_) async => <String, dynamic>{})));
    await t.pumpAndSettle();
    expect(find.text(tr('trashEmpty')), findsOneWidget);
    await t.pumpWidget(_app(TrashScreen(key: const ValueKey<String>('e'), load: () async => throw Exception('x'), restore: (_) async => <String, dynamic>{})));
    await t.pumpAndSettle();
    expect(find.text(tr('trashError')), findsOneWidget);
  });
}
