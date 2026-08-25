import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/report/ui/clinical_report_screen.dart';

void main() {
  group('ClinicalReportScreen Widget Tests', () {
    testWidgets('renders initial loading indicator and watermark', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: ClinicalReportScreen(patientId: 'TEST-12345'),
      ));

      expect(find.text('ATOMYBRIDGE CARE'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
