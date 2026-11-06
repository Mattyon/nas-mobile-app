import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/grab_progress.dart';
import 'package:nas_app/i18n.dart';

/// The download request's progress is a snackbar, not a dialog: the screen under it
/// stays usable, and more downloads can be started while one runs.
void main() {
  late int taps;

  Future<ScaffoldMessengerState> pumpApp(WidgetTester tester) async {
    lang.value = 'en';
    taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: ElevatedButton(onPressed: () => taps++, child: const Text('Other title')),
        ),
      ),
    ));
    return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
  }

  testWidgets('shows the stages at the bottom and leaves the screen usable',
      (WidgetTester tester) async {
    final ScaffoldMessengerState messenger = await pumpApp(tester);
    final VoidCallback done = GrabProgress.start(messenger);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Fetching torrents…'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.text('Other title'));
    expect(taps, 1);

    await tester.pump(GrabProgress.stepEvery);
    expect(find.text(tr('stageDatabases')), findsOneWidget);

    done();
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(GrabProgress.active, 0);
  });

  testWidgets('a second download joins the same bar; the first result replaces it',
      (WidgetTester tester) async {
    final ScaffoldMessengerState messenger = await pumpApp(tester);
    final VoidCallback first = GrabProgress.start(messenger);
    await tester.pump(const Duration(milliseconds: 500));
    final VoidCallback second = GrabProgress.start(messenger);
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Starting 2 downloads'), findsOneWidget);

    first();
    first(); // idempotent
    messenger.showSnackBar(const SnackBar(content: Text('Added to downloads')));
    await tester.pumpAndSettle();
    expect(find.text('Added to downloads'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(GrabProgress.active, 1);

    second();
    expect(GrabProgress.active, 0);
    messenger.clearSnackBars();
    await tester.pumpAndSettle();
  });

  testWidgets('a new download replaces an earlier result at once', (WidgetTester tester) async {
    final ScaffoldMessengerState messenger = await pumpApp(tester);
    messenger.showSnackBar(const SnackBar(content: Text('Added to downloads')));
    await tester.pumpAndSettle();
    final VoidCallback done = GrabProgress.start(messenger);
    await tester.pump();
    expect(find.text('Added to downloads'), findsNothing);
    expect(find.text('Fetching torrents…'), findsOneWidget);
    done();
    await tester.pumpAndSettle();
  });

  test('"Starting {n} downloads" in both languages', () {
    for (final String l in <String>['en', 'cs']) {
      lang.value = l;
      expect(tr('grabsStarting'), contains('{n}'));
    }
  });
}
