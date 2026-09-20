import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';

/// Singleton service that monitors network connectivity.
/// Provides a stream of connectivity changes and a current status getter.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  ConnectivityResult _latestResult = ConnectivityResult.none;
  bool _initialized = false;
  DateTime? _lastActualCheck;
  bool _lastActualOnline = false;

  /// Current connectivity status (cached from last event).
  ConnectivityResult get latestResult => _latestResult;

  /// True if we currently have any network connection.
  bool get isOnline => _latestResult != ConnectivityResult.none;

  /// Stream of connectivity changes for UI/reactive listeners.
  /// The connectivity_plus 6.0+ API emits a list of results (one per interface).
  /// We flatten to a single "best" result: online if any interface is online.
  Stream<ConnectivityResult> get onConnectivityChanged =>
      _connectivity.onConnectivityChanged.map((results) {
        final hasOnline = results.any((r) => r != ConnectivityResult.none);
        return hasOnline ? results.firstWhere((r) => r != ConnectivityResult.none) : ConnectivityResult.none;
      });

  /// Initialize the service — fetches initial state and starts listening.
  Future<void> initialize() async {
    if (_initialized) return;
    final results = await _connectivity.checkConnectivity();
    _latestResult = results.any((r) => r != ConnectivityResult.none)
        ? results.firstWhere((r) => r != ConnectivityResult.none)
        : ConnectivityResult.none;
    _initialized = true;
    if (kDebugMode) {
      debugPrint('[ConnectivityService] Initialized: $_latestResult');
    }
    // Do an actual connectivity check after initialization
    await _verifyActualConnectivity();
  }

  /// Convenience: one-time check (bypasses cache).
  Future<bool> checkOnline() async {
    final results = await _connectivity.checkConnectivity();
    _latestResult = results.any((r) => r != ConnectivityResult.none)
        ? results.firstWhere((r) => r != ConnectivityResult.none)
        : ConnectivityResult.none;
    
    // Also verify actual internet connectivity (not just network interface)
    await _verifyActualConnectivity();
    return _lastActualOnline;
  }

  /// Verify actual internet connectivity by making a lightweight request.
  /// Caches result for 30 seconds to avoid excessive requests.
  Future<void> _verifyActualConnectivity() async {
    final now = DateTime.now();
    if (_lastActualCheck != null && 
        now.difference(_lastActualCheck!) < const Duration(seconds: 30)) {
      return; // Use cached result
    }
    _lastActualCheck = now;

    try {
      // Try to reach the API health endpoint or a simple public endpoint
      // Using a short timeout to fail fast when offline
      final client = ApiClient.httpClient;
      final response = await client.get(
        Uri.parse('${ApiClient.baseUrl}/healthy'),
      ).timeout(const Duration(seconds: 5));
      
      _lastActualOnline = response.statusCode == 200;
      if (kDebugMode) {
        debugPrint('[ConnectivityService] Actual connectivity check: $_lastActualOnline');
      }
    } catch (_) {
      _lastActualOnline = false;
      if (kDebugMode) {
        debugPrint('[ConnectivityService] Actual connectivity check: false (offline)');
      }
    }
  }

  /// Update cached result from stream listener.
  void updateCachedResult(ConnectivityResult result) {
    _latestResult = result;
    // Trigger actual connectivity verification when network interface changes
    _verifyActualConnectivity();
  }

  /// Get the actual internet connectivity status (verified via request).
  bool get isActuallyOnline => _lastActualOnline;
}