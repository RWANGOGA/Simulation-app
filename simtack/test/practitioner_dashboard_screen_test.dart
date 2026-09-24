import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/dashboard/ui/practitioner_dashboard_screen.dart';
import 'package:simtack/features/report/ui/clinical_report_screen.dart';

/// In-memory token storage so tests never touch platform secure storage.
class FakeTokenStorage implements TokenStorage {
  String? _token;
  String? _refreshToken;

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;

  @override
  Future<void> writeRefreshToken(String value) async => _refreshToken = value;

  @override
  Future<String?> readRefreshToken() async => _refreshToken;

  @override
  Future<void> delete() async {
    _token = null;
    _refreshToken = null;
  }
}

/// Mock client that handles all dashboard endpoints with realistic data.
MockClient _dashboardClient({List<Map<String, dynamic>>? sessions}) {
  final sessionData = sessions ?? [
    {
      'id': 1,
      'patient_id': 10,
      'anonymous_code': 'P-ABC12345678',
      'body_region': 'Chest / Heart',
      'pain_type': 'crushing',
      'severity': 8,
      'risk_score': 0.85,
      'status': 'open',
      'created_at': '2026-08-27T10:00:00',
      'patient_age': 45,
      'patient_gender': 'Male',
    },
    {
      'id': 2,
      'patient_id': 11,
      'anonymous_code': 'P-DEF98765432',
      'body_region': 'Headache / Cranial',
      'pain_type': 'throbbing',
      'severity': 5,
      'risk_score': 0.45,
      'status': 'open',
      'created_at': '2026-08-27T11:00:00',
      'patient_age': 32,
      'patient_gender': 'Female',
    },
    {
      'id': 3,
      'patient_id': 12,
      'anonymous_code': 'P-GHI11223344',
      'body_region': 'Abdomen (Upper)',
      'pain_type': 'cramping',
      'severity': 3,
      'risk_score': 0.25,
      'status': 'closed',
      'created_at': '2026-08-27T12:00:00',
      'patient_age': 28,
      'patient_gender': 'Male',
    },
  ];

  return MockClient((request) async {
    final path = request.url.path;

    if (path.endsWith('/triage/stats')) {
      return http.Response(
        jsonEncode({'total': 3, 'high_risk': 1, 'medium_risk': 1, 'low_risk': 1}),
        200,
      );
    }
    if (path.endsWith('/triage/list')) {
      return http.Response(jsonEncode(sessionData), 200);
    }
    if (path.endsWith('/auth/me')) {
      return http.Response(
        jsonEncode({'id': 1, 'email': 'doc@test.com', 'full_name': 'Dr. Test', 'is_active': true}),
        200,
      );
    }
    if (path.contains('/triage/patient/') && path.endsWith('/history')) {
      return http.Response(jsonEncode(sessionData), 200);
    }
    return http.Response('Not found', 404);
  });
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

  group('PractitionerDashboardScreen - Sidebar', () {
    testWidgets('sidebar is hidden by default', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Sidebar should not be visible initially
      expect(find.text('OVERVIEW'), findsNothing);
      expect(find.text('RECENT PATIENTS'), findsNothing);
    });

    testWidgets('tapping menu icon expands the sidebar', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Tap the menu button to expand sidebar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Sidebar content should now be visible
      expect(find.text('OVERVIEW'), findsOneWidget);
      expect(find.text('RECENT PATIENTS'), findsOneWidget);
      expect(find.text('Total Patients'), findsOneWidget);
    });

    testWidgets('tapping menu again collapses the sidebar', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Expand
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('OVERVIEW'), findsOneWidget);

      // Collapse
      await tester.tap(find.byIcon(Icons.menu_open));
      await tester.pumpAndSettle();
      expect(find.text('OVERVIEW'), findsNothing);
    });

    testWidgets('sidebar shows correct stats', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Expand sidebar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Check stats are displayed - "High Risk" appears in both card and sidebar
      expect(find.text('Total Patients'), findsOneWidget);
      expect(find.text('High Risk'), findsAtLeastNWidgets(1));
      expect(find.text('Medium Risk'), findsOneWidget);
      expect(find.text('Low Risk'), findsAtLeastNWidgets(1));
    });

    testWidgets('sidebar shows recent patients list', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Expand sidebar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Patient codes should be visible in sidebar
      expect(find.text('P-ABC12345678'), findsWidgets);
      expect(find.text('P-DEF98765432'), findsWidgets);
      expect(find.text('P-GHI11223344'), findsWidgets);
    });

    testWidgets('tapping patient in sidebar navigates to report', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Expand sidebar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Tap a patient in the sidebar
      await tester.tap(find.text('P-ABC12345678').last);
      await tester.pumpAndSettle();

      // Should navigate to ClinicalReportScreen
      expect(find.byType(ClinicalReportScreen), findsOneWidget);
    });
  });

  group('PractitionerDashboardScreen - Autocomplete Search', () {
    testWidgets('search field is present and functional', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Search field should be present
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search Patient ID (e.g., P-...)'), findsOneWidget);
    });

    testWidgets('typing in search field triggers filter', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Type in search field
      await tester.enterText(find.byType(TextField), 'P-ABC');
      await tester.pump();

      // The text should be in the field
      expect(find.text('P-ABC'), findsOneWidget);
    });

    testWidgets('clear button appears when text is entered', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Initially no clear button
      expect(find.byIcon(Icons.clear), findsNothing);

      // Type something
      await tester.enterText(find.byType(TextField), 'P-ABC');
      await tester.pump();

      // Clear button should appear
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('tapping clear button clears the search', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Type something
      await tester.enterText(find.byType(TextField), 'P-ABC');
      await tester.pump();

      // Tap clear
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      // Field should be empty
      expect(find.text('P-ABC'), findsNothing);
    });
  });

  group('PractitionerDashboardScreen - Existing Functionality', () {
    testWidgets('stats cards are displayed', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Stats cards should be visible
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('High Risk'), findsWidgets); // In both card and sidebar (sidebar hidden)
      expect(find.text('Low Risk'), findsWidgets);
    });

    testWidgets('session list shows patient data', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Patient codes should be in the session list
      expect(find.text('P-ABC12345678'), findsOneWidget);
      expect(find.text('P-DEF98765432'), findsOneWidget);
      expect(find.text('P-GHI11223344'), findsOneWidget);
    });

    testWidgets('risk level badges are displayed', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Risk level badges
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('MEDIUM'), findsOneWidget);
      expect(find.text('LOW'), findsOneWidget);
    });

    testWidgets('status badges are displayed', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Status badges
      expect(find.text('Open'), findsNWidgets(2)); // Two open sessions
      expect(find.text('Closed'), findsOneWidget);
    });

    testWidgets('tapping session navigates to report', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Tap a session
      await tester.tap(find.text('P-ABC12345678'));
      await tester.pumpAndSettle();

      // Should navigate to ClinicalReportScreen
      expect(find.byType(ClinicalReportScreen), findsOneWidget);
    });

    testWidgets('refresh button triggers reload', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Tap refresh
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();

      // Dashboard should still be visible
      expect(find.byType(PractitionerDashboardScreen), findsOneWidget);
    });

    testWidgets('risk filter dropdown is present', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Filter dropdowns should be present (DropdownButton widgets)
      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
    });

    testWidgets('demographics are shown in session list', (tester) async {
      ApiClient.httpClient = _dashboardClient();

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Demographic info should be displayed
      expect(find.textContaining('45 yrs'), findsOneWidget);
      expect(find.textContaining('32 yrs'), findsOneWidget);
    });
  });

  group('PractitionerDashboardScreen - Empty State', () {
    testWidgets('shows empty state when no sessions', (tester) async {
      ApiClient.httpClient = _dashboardClient(sessions: []);

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Should show empty state message
      expect(find.text('No triage sessions found.'), findsOneWidget);
    });

    testWidgets('sidebar shows no patients when empty', (tester) async {
      ApiClient.httpClient = _dashboardClient(sessions: []);

      await tester.pumpWidget(const MaterialApp(home: PractitionerDashboardScreen()));
      await tester.pumpAndSettle();

      // Expand sidebar
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();

      // Should show no patients message
      expect(find.text('No patients yet'), findsOneWidget);
    });
  });
}
