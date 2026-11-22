import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/offline/local_database.dart';
import 'package:simtack/features/admin/data/admin_repository.dart';
import 'package:simtack/features/admin/ui/admin_console_screen.dart';
import 'package:simtack/features/dashboard/ui/practitioner_sidebar.dart';
import 'package:simtack/l10n/app_localizations.dart';

class _TokenStorage implements TokenStorage {
  _TokenStorage(this._token);

  String? _token;

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> writeRefreshToken(String value) async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> delete() async => _token = null;
}

const _adminDoctor = {
  'id': 1,
  'email': 'admin@simtack.com',
  'full_name': 'Admin Person',
  'is_active': true,
  'is_approved': true,
  'access_level': 'admin',
  'hospital_name': 'St. Mary\'s',
};

const _practitionerDoctor = {
  'id': 2,
  'email': 'practitioner@simtack.com',
  'full_name': 'Practitioner Person',
  'is_active': true,
  'is_approved': true,
  'access_level': 'practitioner',
};

const _overview = {
  'generated_at': '2026-11-21T10:00:00+00:00',
  'environment': 'test',
  'version': '0.1.0',
  'users': {
    'total': 4,
    'approved': 3,
    'pending': 1,
    'active': 4,
    'inactive': 0,
    'admins': 1,
    'practitioners': 3,
  },
  'patients': {'total': 12},
  'triage': {
    'total': 30,
    'today': 4,
    'last_7_days': 18,
    'high_risk': 7,
    'medium_risk': 9,
    'low_risk': 14,
    'open': 11,
    'closed': 19,
    'by_tier': {'red': 6, 'orange': 8, 'yellow': 9, 'green': 7},
    'by_escalation': {'emergency': 6, 'urgent': 8, 'routine': 16},
    'by_region': [
      {'region': 'Chest / Heart', 'count': 12},
      {'region': 'Headache / Cranial', 'count': 8},
    ],
    'avg_severity': 5.4,
    'avg_risk_score': 0.51,
  },
  'activity': {
    'total': 44,
    'last_24h': 9,
    'denied': 2,
    'recent': [
      {
        'id': 9,
        'created_at': '2026-11-21T09:58:00+00:00',
        'action': 'aggregate',
        'outcome': 'allowed',
        'actor_type': 'doctor',
        'actor_id': 1,
        'actor_label': 'admin@simtack.com',
        'resource_type': 'triage_stats',
        'resource_id': null,
        'patient_id': null,
        'patient_code': null,
        'endpoint': 'GET /api/v1/admin/overview',
        'ip_address': null,
        'user_agent': null,
        'detail': 'administrator overview',
      },
    ],
  },
};

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<void> _seedOverviewCache() async {
  final db = await LocalDatabase.open();
  await db.mutate((db) {
    db.writeCache('admin.overview', {
      'at': '2026-11-21T09:00:00Z',
      'data': _overview,
    });
    return null;
  });
}

void main() {
  final defaultClient = ApiClient.httpClient;
  final defaultStorage = ApiClient.tokenStorage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDatabase.resetForTest();
    ApiClient.tokenStorage = _TokenStorage('token');
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
    ApiClient.tokenStorage = defaultStorage;
  });

  group('AdminRepository', () {
    test('serves the cached snapshot when the server is unreachable', () async {
      ApiClient.httpClient = MockClient((request) async {
        expect(request.url.path, endsWith('/admin/overview'));
        return http.Response(
          jsonEncode(_overview),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final live = await AdminRepository.instance.loadOverview();
      expect(live.fromCache, isFalse);
      expect(live.data['users']['pending'], 1);

      ApiClient.httpClient = MockClient((request) async {
        throw http.ClientException('offline');
      });

      final cached = await AdminRepository.instance.loadOverview();
      expect(cached.fromCache, isTrue);
      expect(cached.cachedAt, isNotNull);
      expect(cached.data['triage']['total'], 30);
    });

    test('rethrows when there is no cached snapshot to fall back to', () async {
      ApiClient.httpClient = MockClient((request) async {
        throw http.ClientException('offline');
      });

      await expectLater(
        AdminRepository.instance.loadOverview(),
        throwsA(isA<ApiException>().having(
          (error) => error.isNetworkError,
          'isNetworkError',
          isTrue,
        )),
      );
    });

    test('account changes require the server and invalidate the cache',
        () async {
      await _seedOverviewCache();

      ApiClient.httpClient = MockClient((request) async {
        expect(request.method, 'PATCH');
        return http.Response(
          jsonEncode({
            'id': 2,
            'email': 'practitioner@simtack.com',
            'full_name': 'Practitioner Person',
            'is_active': true,
            'is_approved': true,
            'access_level': 'admin',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final updated = await AdminRepository.instance.updateUser(
        2,
        accessLevel: 'admin',
      );
      expect(updated.isAdmin, isTrue);

      ApiClient.httpClient = MockClient((request) async {
        throw http.ClientException('offline');
      });
      await expectLater(
        AdminRepository.instance.loadOverview(),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('AdminConsoleScreen', () {
    testWidgets('refuses a non-administrator', (tester) async {
      ApiClient.httpClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/me'));
        return http.Response(
          jsonEncode(_practitionerDoctor),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await tester.pumpWidget(_wrap(const AdminConsoleScreen()));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Administrator access is required'),
        findsOneWidget,
      );
      expect(find.text('Triage distribution'), findsNothing);
    });

    testWidgets('renders the last snapshot with an honest offline banner',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _seedOverviewCache();

      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response(
            jsonEncode(_adminDoctor),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        throw http.ClientException('offline');
      });

      await tester.pumpWidget(_wrap(const AdminConsoleScreen()));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('Administration'), findsOneWidget);
      expect(find.textContaining('Showing the snapshot saved'), findsOneWidget);
      expect(find.text('Triage distribution'), findsOneWidget);
      expect(find.text('Top reported regions'), findsOneWidget);
      expect(find.text('Chest / Heart'), findsOneWidget);
      expect(find.text('30'), findsWidgets);
    });
  });

  group('PractitionerSidebar administration entry', () {
    Future<void> pumpSidebar(WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          const Scaffold(
            body: Row(
              children: [
                PractitionerSidebar(currentRoute: '/dashboard'),
                Expanded(child: Placeholder()),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('is offered to an administrator', (tester) async {
      ApiClient.httpClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/me'));
        return http.Response(
          jsonEncode(_adminDoctor),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await pumpSidebar(tester);

      expect(find.text('Admin Console'), findsOneWidget);
      expect(find.text('ADMINISTRATION'), findsOneWidget);
    });

    testWidgets('is hidden from an ordinary practitioner', (tester) async {
      ApiClient.httpClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/me'));
        return http.Response(
          jsonEncode(_practitionerDoctor),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      await pumpSidebar(tester);

      expect(find.text('Admin Console'), findsNothing);
      expect(find.text('ADMINISTRATION'), findsNothing);
    });
  });
}
