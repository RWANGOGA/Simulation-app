import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/theme/app_theme.dart';

void main() {
  testWidgets('lightTheme sets Inter as the default font, applied to plain Text widgets',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      // A Text widget with no fontFamily of its own — this is how nearly
      // every screen in the app builds its TextStyles, so this proves the
      // font actually cascades rather than just being declared and unused.
      home: const Scaffold(body: Text('Hello', style: TextStyle(fontSize: 16))),
    ));

    final textWidget = tester.widget<Text>(find.text('Hello'));
    final resolvedFont = DefaultTextStyle.of(tester.element(find.text('Hello'))).style.fontFamily;

    expect(textWidget.style?.fontFamily, isNull); // confirms the widget itself set nothing
    expect(resolvedFont, 'Inter'); // yet the ambient default is Inter
  });

  testWidgets('darkTheme also sets Inter as the default font', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: Text('Hello')),
    ));

    expect(Theme.of(tester.element(find.text('Hello'))).textTheme.bodyMedium?.fontFamily, 'Inter');
  });
}
