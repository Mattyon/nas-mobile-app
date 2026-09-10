import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/main.dart';

void main() {
  group('AI chat — input placement', () {
    testWidgets('input row is inside a SafeArea so it clears system nav',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: AiChatScreen(chatId: 'test-chat', initialTitle: 'Chat'),
      ));
      // First pump shows the loading spinner; the history fetch fails fast in
      // tests (no API configured) and the catch clears _loading.
      await tester.pump();
      await tester.pump();

      final Finder input = find.byType(TextField);
      expect(input, findsOneWidget);
      expect(
        find.ancestor(of: input, matching: find.byType(SafeArea)),
        findsWidgets,
        reason: 'chat input must sit above the Android gesture/nav bar',
      );
    });
  });
}
