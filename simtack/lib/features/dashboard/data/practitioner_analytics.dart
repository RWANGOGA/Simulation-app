import '../../../core/network/api_client.dart';
import '../../../core/offline/local_database.dart';
import '../../../core/offline/offline_repository.dart';

/// Server-authoritative analytics for the practitioner dashboard, with an
/// honest offline fallback.
///
/// The dashboard used to read only the device's local store, which meant the
/// numbers were correct for that phone but not for the system. The backend
/// already exposes the same aggregates over the shared database; this
/// repository prefers those, keeps the last successful response in the
/// encrypted cache, and only falls back to device-only figures when the server
/// cannot be reached. The returned `source` field lets the UI say which one the
/// patient is looking at instead of quietly mixing the two.
class PractitionerAnalytics {
  PractitionerAnalytics._();

  static final PractitionerAnalytics instance = PractitionerAnalytics._();

  /// Analysis seam: widget tests that deliberately exercise the offline store
  /// turn this off so they never start a platform-channel token read.
  bool allowServer = true;

  static const String _statsKey = 'practitioner.stats';
  static const String _reportsPrefix = 'practitioner.reports.';

  Future<Map<String, dynamic>> stats() =>
      _resolve(_statsKey, ApiClient.getTriageStats, OfflineRepository.instance.getTriageStats);

  Future<Map<String, dynamic>> reports({required String period}) => _resolve(
        '$_reportsPrefix$period',
        () => ApiClient.getTriageReports(period: period),
        () => OfflineRepository.instance.getTriageReports(period: period),
      );

  Future<Map<String, dynamic>> _resolve(
    String key,
    Future<Map<String, dynamic>> Function() fetch,
    Future<Map<String, dynamic>> Function() device,
  ) async {
    // No signed-in practitioner means the server endpoints are JWT-guarded and
    // would only burn a timeout. Go straight to the cached/device values.
    if (!allowServer) return _fallback(key, device);
    final token = await ApiClient.tokenStorage.read();
    if (token == null || token.isEmpty) return _fallback(key, device);

    try {
      final data = await fetch();
      await _write(key, data);
      return {...data, 'source': 'system'};
    } on ApiException catch (error) {
      if (!error.isNetworkError) rethrow;
      return _fallback(key, device);
    }
  }

  Future<Map<String, dynamic>> _fallback(
    String key,
    Future<Map<String, dynamic>> Function() device,
  ) async {
    final cached = await _read(key);
    if (cached != null) return {...cached, 'source': 'cached'};
    return {...await device(), 'source': 'device'};
  }

  Future<void> _write(String key, Map<String, dynamic> data) async {
    final db = await LocalDatabase.open();
    await db.mutate((db) {
      db.writeCache(key, data);
      return null;
    });
  }

  Future<Map<String, dynamic>?> _read(String key) async {
    final db = await LocalDatabase.open();
    final raw = await db.read((db) => db.cache[key]);
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }
}
