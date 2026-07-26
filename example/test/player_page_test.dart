import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_player_android_example/main.dart';

void main() {
  testWidgets('renders the URL player showcase on the first frame',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MdPlayerExampleApp());

    expect(
      find.widgetWithText(
        TextField,
        'YouTube, Vimeo, or direct video URL',
      ),
      findsOneWidget,
    );
    expect(find.text('Modern'), findsOneWidget);
    expect(find.text('Legacy'), findsOneWidget);
  });

  testWidgets('validates the video URL without creating a player',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MdPlayerExampleApp());

    await tester.enterText(
      find.widgetWithText(
        TextField,
        'YouTube, Vimeo, or direct video URL',
      ),
      'not a URL',
    );
    await tester.tap(find.text('Load and play'));
    await tester.pump();

    expect(
      find.text('Enter a valid HTTP or HTTPS video URL.'),
      findsOneWidget,
    );
  });
}
