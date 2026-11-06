import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/i18n.dart';
import 'package:nas_app/reminders_screen.dart';

/// "Download when out": titles not released yet are waited for, not downloaded.
void main() {
  setUp(() => lang.value = 'en');

  test('a title is upcoming only when the gateway says so', () {
    expect(notOutYet(<String, dynamic>{'upcoming': true}), isTrue);
    expect(notOutYet(<String, dynamic>{'upcoming': false}), isFalse);
    expect(notOutYet(<String, dynamic>{}), isFalse); // an older gateway: Download as before
  });

  test('the button says whether it is already waited for', () {
    expect(reminderLabel(<String, dynamic>{}), 'When out');
    expect(reminderIcon(<String, dynamic>{}), Icons.alarm_add);
    expect(reminderLabel(<String, dynamic>{'reminder': true}), 'Waiting');
    expect(reminderIcon(<String, dynamic>{'reminder': true}), Icons.alarm_on);
  });

  test('release dates in both languages', () {
    expect(releaseDateText('2026-12-16'), '16 Dec 2026');
    lang.value = 'cs';
    expect(releaseDateText('2026-12-16'), '16. 12. 2026');
    expect(releaseDateText(null), isNull);
    expect(releaseDateText('soon'), isNull);
  });

  test('every string in both languages', () {
    for (final String l in <String>['en', 'cs']) {
      lang.value = l;
      for (final String k in <String>['whenOut', 'whenOutWaiting', 'remindersTitle', 'reminderSet',
          'reminderCancelled', 'reminderChange', 'reminderCancel', 'premiereOn', 'reminderWaiting',
          'reminderStarted', 'reminderDone', 'remindersEmpty']) {
        expect(tr(k), isNot(equals(k)), reason: '$l $k');
      }
      expect(tr('premiereOn'), contains('{date}'));
    }
  });

  testWidgets('the list shows each state and cancels a waiting one', (WidgetTester tester) async {
    final List<String> deleted = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: RemindersScreen(
        load: () async => <dynamic>[
          <String, dynamic>{'id': 'a', 'title': 'Dune: Part Three', 'year': 2026, 'status': 'waiting',
            'release_date': '2026-12-16', 'tier': 'best', 'language': 'cs'},
          <String, dynamic>{'id': 'b', 'title': 'Avatar 4', 'year': 2029, 'status': 'started',
            'tier': 'fast', 'language': 'en'},
        ],
        delete: (String id) async => deleted.add(id),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Dune: Part Three (2026)'), findsOneWidget);
    expect(find.textContaining('Waiting for release · Premiere 16 Dec 2026'), findsOneWidget);
    expect(find.textContaining('you will hear at noon'), findsOneWidget);
    expect(find.byIcon(Icons.alarm_off), findsOneWidget); // only the waiting one
    await tester.tap(find.byIcon(Icons.alarm_off));
    await tester.pumpAndSettle();
    expect(deleted, <String>['a']);
    expect(find.text('Dune: Part Three (2026)'), findsNothing);
  });

  testWidgets('nothing to wait for says how to start', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: RemindersScreen(load: () async => <dynamic>[])));
    await tester.pumpAndSettle();
    expect(find.textContaining('When out'), findsOneWidget);
  });
}
