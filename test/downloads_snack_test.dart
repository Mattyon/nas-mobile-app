import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/downloads_snack.dart';

/// Owner, 2026-11-23: once the Downloads tab is opened, the bottom overlays with a
/// Downloads button disappear -- the one showing and the ones queued behind it.
void main() {
  Future<ScaffoldMessengerState> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    return tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger));
  }

  SnackBar snack(String m) => DownloadsSnack.build(m, label: 'Downloads', onOpen: () {});

  testWidgets('the overlay on screen goes when Downloads is opened', (WidgetTester tester) async {
    final ScaffoldMessengerState messenger = await pumpApp(tester);
    messenger.showSnackBar(snack('Added to downloads'));
    await tester.pumpAndSettle();
    expect(find.text('Added to downloads'), findsOneWidget);

    DownloadsSnack.downloadsOpened();
    await tester.pumpAndSettle();
    expect(find.text('Added to downloads'), findsNothing);
  });

  testWidgets('queued overlays never appear after Downloads was opened', (WidgetTester tester) async {
    final ScaffoldMessengerState messenger = await pumpApp(tester);
    messenger.showSnackBar(snack('Added: Taken'));
    messenger.showSnackBar(snack('Added: Taken 2'));
    messenger.showSnackBar(snack('Added: Taken 3'));
    await tester.pumpAndSettle();
    expect(find.text('Added: Taken'), findsOneWidget);

    DownloadsSnack.downloadsOpened();
    for (int i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Added: Taken 2'), findsNothing);
      expect(find.text('Added: Taken 3'), findsNothing);
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Added:'), findsNothing);
  });

  testWidgets('one made after Downloads was opened still shows', (WidgetTester tester) async {
    final ScaffoldMessengerState messenger = await pumpApp(tester);
    DownloadsSnack.downloadsOpened();
    messenger.showSnackBar(snack('Requested'));
    await tester.pumpAndSettle();
    expect(find.text('Requested'), findsOneWidget);
  });

  testWidgets('other snackbars are left alone', (WidgetTester tester) async {
    final ScaffoldMessengerState messenger = await pumpApp(tester);
    messenger.showSnackBar(const SnackBar(content: Text('Could not reach the NAS')));
    await tester.pumpAndSettle();
    DownloadsSnack.downloadsOpened();
    await tester.pumpAndSettle();
    expect(find.text('Could not reach the NAS'), findsOneWidget);
  });
}
