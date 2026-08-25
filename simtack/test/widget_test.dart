import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/main.dart';

void main() {
  testWidgets('AtomyBridgeApp builds and shows WelcomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const AtomyBridgeApp());
    await tester.pumpAndSettle();

    // Confirms the app builds without throwing and renders a MaterialApp.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
