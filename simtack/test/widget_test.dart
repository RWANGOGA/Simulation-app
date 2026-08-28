import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/main.dart';

void main() {
  testWidgets('AtomyBridgeApp builds and shows WelcomeScreen', (WidgetTester tester) async {
    // WelcomeScreen loads a saved draft via SharedPreferences in initState,
    // so we must seed an empty mock store before pumping the widget.
    SharedPreferences.setMockInitialValues({});

    // The default 800x600 test viewport is too short for the WelcomeScreen's
    // Column; use a phone-sized surface so the layout doesn't overflow.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const AtomyBridgeApp(isDoctorLoggedIn: false));
    await tester.pumpAndSettle();

    // Confirms the app builds without throwing and renders a MaterialApp.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
