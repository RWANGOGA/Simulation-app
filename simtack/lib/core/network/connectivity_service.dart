import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Singleton service that monitors network connectivity.
/// Provides a stream of connectivity changes and a current status getter.
class ConnectivityService {
  ConnectivityService._();

  static final ConnectivityService instance = ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  ConnectivityResult _latestResult = ConnectivityResult.none;
  bool _initialized = false;

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
  }

  /// Convenience: one-time check (bypasses cache).
  Future<bool> checkOnline() async {
    final results = await _connectivity.checkConnectivity();
    _latestResult = results.any((r) => r != ConnectivityResult.none)
        ? results.firstWhere((r) => r != ConnectivityResult.none)
        : ConnectivityResult.none;
    return isOnline;
  }

  /// Update cached result from stream listener.
  void updateCachedResult(ConnectivityResult result) {
    _latestResult = result;
  }
}