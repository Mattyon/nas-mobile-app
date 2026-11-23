import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/download_files_screen.dart';
import 'package:nas_app/i18n.dart';

/// Owner, 2026-11-23: tapping a season pack in Downloads shows every episode with its
/// progress, the finished ones too.
void main() {
  final List<dynamic> rows = <dynamic>[
    <String, dynamic>{'name': 'Manifest.S01E01.1080p.mkv', 'episode': 'S01E01', 'progress': 100.0,
      'size_bytes': 1610612736, 'downloaded_bytes': 1610612736},
    <String, dynamic>{'name': 'Manifest.S01E02.1080p.mkv', 'episode': 'S01E02', 'progress': 42.5,
      'size_bytes': 1073741824, 'downloaded_bytes': 456340275},
    <String, dynamic>{'name': 'Bonus.mkv', 'episode': null, 'progress': 0.0,
      'size_bytes': 10485760, 'downloaded_bytes': 0},
  ];

  Future<void> pump(WidgetTester tester, Future<List<dynamic>> Function() load) async {
    lang.value = 'en';
    await tester.pumpWidget(MaterialApp(home: DownloadFilesScreen(title: 'Manifest.S01', load: load)));
    await tester.pump();
  }

  testWidgets('every episode with its progress, finished ones included', (WidgetTester tester) async {
    await pump(tester, () async => rows);
    expect(find.text('Manifest.S01'), findsOneWidget);
    expect(find.text('1 of 3 done'), findsOneWidget);
    expect(find.text('S01E01'), findsOneWidget);
    expect(find.text('100%  •  1.5 GB'), findsOneWidget);
    expect(find.text('S01E02'), findsOneWidget);
    expect(find.text('42.5%  •  435 MB / 1.0 GB'), findsOneWidget);
    expect(find.text('Bonus.mkv'), findsOneWidget);           // no episode number: the name
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
    await tester.pumpWidget(const SizedBox());                 // stop the refresh timer
  });

  testWidgets('refreshes while open', (WidgetTester tester) async {
    int calls = 0;
    await pump(tester, () async {
      calls++;
      return rows;
    });
    expect(calls, 1);
    await tester.pump(DownloadFilesScreen.refreshEvery);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(DownloadFilesScreen.refreshEvery);
    expect(calls, 2);                                         // closed: no more requests
  });

  testWidgets('says so when the files cannot be loaded', (WidgetTester tester) async {
    await pump(tester, () async => throw Exception('offline'));
    expect(find.text('Could not load the files'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a download with no video files says so', (WidgetTester tester) async {
    await pump(tester, () async => <dynamic>[]);
    expect(find.text('No video files in this download'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
