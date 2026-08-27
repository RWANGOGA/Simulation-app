import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/dashboard/ui/reports_screen.dart';

/// In-memory token storage so tests never touch platform secure storage —
/// the real SecureTokenStorage's method channel isn't mocked in widget
/// tests and hangs pumpAndSettle rather than failing fast.
class FakeTokenStorage implements TokenStorage {
  String? _token = 'test-token';

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> delete() async => _token = null;
}

void main() {
  final defaultClient = ApiClient.httpClient;
  final defaultStorage = ApiClient.tokenStorage;

  setUp(() {
    ApiClient.tokenStorage = FakeTokenStorage();
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
    ApiClient.tokenStorage = defaultStorage;
  });

  testWidgets('renders real aggregate data from /triage/reports', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/triage/reports')) {
        return http.Response(
          jsonEncode({
            'total': 12,
            'open_count': 9,
            'closed_count': 3,
            'avg_severity': 6.4,
            'avg_risk_score': 0.58,
            'by_region': [
              {'region': 'Chest / Heart', 'count': 5},
              {'region': 'Headache / Cranial', 'count': 3},
            ],
            'by_pain_type': [
              {'pain_type': 'Sharp', 'count': 7},
            ],
          }),
          200,
        );
      }
      return http.Response('Not found', 404);
    });

    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await tester.pumpAndSettle();

    // Matches both the screen's own header and the sidebar's "Reports" nav label.
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('12'), findsOneWidget); // Total Sessions
    expect(find.text('9'), findsWidgets); // Open count (stat card + status legend)
    expect(find.text('3'), findsWidgets); // Closed count and/or by_region count
    expect(find.text('Chest / Heart'), findsOneWidget);
    expect(find.text('Headache / Cranial'), findsOneWidget);
    expect(find.text('Sharp'), findsOneWidget);
  });

  testWidgets('shows a real empty state when there are no sessions yet', (tester) async {
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'total': 0,
          'open_count': 0,
          'closed_count': 0,
          'avg_severity': null,
          'avg_risk_score': null,
          'by_region': [],
          'by_pain_type': [],
        }),
        200,
      );
    });

    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No triage sessions in this period'), findsOneWidget);
  });

  testWidgets('shows an error with retry when the request fails', (tester) async {
    ApiClient.httpClient = MockClient((request) async => http.Response('Server error', 500));

    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });
}
