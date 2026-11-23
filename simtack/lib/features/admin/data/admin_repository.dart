import '../../../core/network/api_client.dart';
import '../../../core/offline/local_database.dart';

/// A server payload plus the honest provenance of the copy being shown.
///
/// [fromCache] is not a UI nicety: the console must be able to say "these
/// numbers are from 14:05 yesterday" instead of presenting a stale snapshot as
/// live. [cachedAt] is null only for a fresh response.
class AdminSnapshot {
  const AdminSnapshot({
    required this.data,
    this.cachedAt,
    this.fromCache = false,
  });

  final Map<String, dynamic> data;
  final DateTime? cachedAt;
  final bool fromCache;
}

class _CachedAdminSnapshot {
  const _CachedAdminSnapshot(this.data, this.at);

  final Map<String, dynamic> data;
  final DateTime? at;
}

/// Read-through cache for the administrator console.
///
/// The console is the one part of the app that genuinely needs the server:
/// accounts, the audit trail and system-wide triage counts do not exist on a
/// single device. It is still expected to open in a clinic with no signal, so
/// the last successful response for each section is kept in the same encrypted
/// local document as the clinical records and served with [AdminSnapshot.fromCache]
/// set. Mutations are not cached — approving an account without the server
/// answering would be a lie the next sign-in would expose.
class AdminRepository {
  AdminRepository._();

  static final AdminRepository instance = AdminRepository._();

  static const String _overviewKey = 'admin.overview';
  static const String _usersKey = 'admin.users';
  static const String _activityKey = 'admin.activity';
  static const String _sessionsKey = 'admin.sessions';
  static const String _patientsKey = 'admin.patients';

  Future<AdminSnapshot> loadOverview() =>
      _load(_overviewKey, ApiClient.getAdminOverview);

  Future<AdminSnapshot> loadUsers({
    int page = 1,
    int limit = 25,
    String? query,
    String? status,
  }) =>
      _load(
        _usersKey,
        () => ApiClient.getAdminUsers(
          page: page,
          limit: limit,
          query: query,
          status: status,
        ),
      );

  Future<AdminSnapshot> loadActivity({
    int page = 1,
    int limit = 50,
    String? action,
    String? outcome,
  }) =>
      _load(
        _activityKey,
        () => ApiClient.getAdminActivity(
          page: page,
          limit: limit,
          action: action,
          outcome: outcome,
        ),
      );

  Future<AdminSnapshot> loadSessions({
    int page = 1,
    int limit = 25,
    String? riskLevel,
    String? status,
  }) =>
      _load(
        _sessionsKey,
        () => ApiClient.getAdminSessions(
          page: page,
          limit: limit,
          riskLevel: riskLevel,
          status: status,
        ),
      );

  Future<AdminSnapshot> loadPatients({
    int page = 1,
    int limit = 25,
    String? query,
    bool? hasSessions,
  }) =>
      _load(
        _patientsKey,
        () => ApiClient.getAdminPatients(
          page: page,
          limit: limit,
          query: query,
          hasSessions: hasSessions,
        ),
      );

  /// Detail reads are cached per id so reopening a record works offline.
  Future<AdminSnapshot> loadPatient(int patientId) => _load(
        'admin.patient.$patientId',
        () => ApiClient.getAdminPatient(patientId),
      );

  Future<AdminSnapshot> loadUserDetail(int doctorId) => _load(
        'admin.user.$doctorId',
        () => ApiClient.getAdminUser(doctorId),
      );

  /// Approve, deactivate or promote an account.
  ///
  /// Requires the server. The cached users list is dropped afterwards so the
  /// next read cannot show the pre-change row as if nothing happened.
  Future<Doctor> updateUser(
    int doctorId, {
    bool? isApproved,
    bool? isActive,
    String? accessLevel,
  }) async {
    final doctor = await ApiClient.updateAdminUser(
      doctorId,
      isApproved: isApproved,
      isActive: isActive,
      accessLevel: accessLevel,
    );
    await _invalidate(const [_usersKey, _overviewKey]);
    return doctor;
  }

  Future<AdminSnapshot> _load(
    String key,
    Future<Map<String, dynamic>> Function() fetch,
  ) async {
    try {
      final data = await fetch();
      await _write(key, data);
      return AdminSnapshot(data: data, cachedAt: DateTime.now());
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      final cached = await _read(key);
      if (cached == null) rethrow;
      return AdminSnapshot(
        data: cached.data,
        cachedAt: cached.at,
        fromCache: true,
      );
    }
  }

  Future<void> _write(String key, Map<String, dynamic> data) async {
    final db = await LocalDatabase.open();
    await db.mutate((db) {
      db.writeCache(key, {
        'at': DateTime.now().toUtc().toIso8601String(),
        'data': data,
      });
      return null;
    });
  }

  Future<_CachedAdminSnapshot?> _read(String key) async {
    final db = await LocalDatabase.open();
    final raw = await db.read((db) => db.cache[key]);
    if (raw is! Map) return null;
    final data = raw['data'];
    if (data is! Map) return null;
    return _CachedAdminSnapshot(
      Map<String, dynamic>.from(data),
      DateTime.tryParse(raw['at']?.toString() ?? ''),
    );
  }

  Future<void> _invalidate(List<String> keys) async {
    final db = await LocalDatabase.open();
    await db.mutate((db) {
      for (final key in keys) {
        db.removeCache(key);
      }
      return null;
    });
  }
}
