import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nas_app/clear_button.dart';

void main() {
  Future<TextEditingController> pump(WidgetTester tester, {VoidCallback? onCleared}) async {
    final TextEditingController c = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TextField(
          controller: c,
          decoration: InputDecoration(suffixIcon: ClearButton(c, onCleared: onCleared)),
        ),
      ),
    ));
    return c;
  }

  testWidgets('no button while the field is empty', (WidgetTester tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.clear), findsNothing);
  });

  testWidgets('one tap empties the field and hides the button', (WidgetTester tester) async {
    int cleared = 0;
    final TextEditingController c = await pump(tester, onCleared: () => cleared++);
    await tester.enterText(find.byType(TextField), 'scary movie');
    await tester.pump();
    expect(find.byIcon(Icons.clear), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();
    expect(c.text, isEmpty);
    expect(cleared, 1);
    expect(find.byIcon(Icons.clear), findsNothing);
  });
}
