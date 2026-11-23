import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Warms the browser cache with the **same** anatomy3d files the viewer uses.
///
/// The 3D body is an iframe, so it cannot read Flutter's asset bundle. It is
/// served from `web/anatomy3d/` and Flutter's generated service worker caches
/// a resource the first time it is fetched while the worker controls the page.
/// On a first visit that control can arrive after the first frame, so relying
/// on "the patient happened to open the body map while online" is not enough.
/// This service explicitly fetches every file, which makes the offline state a
/// prepared, testable condition rather than a hope.
///
/// Nothing is generated here: the manifests and `.bin.gz` chunks are the exact
/// tracked files the online viewer loads, including the full atlas that carries
/// the muscle, arterial and venous meshes.
class AnatomyOfflineCache {
  AnatomyOfflineCache._();

  static final AnatomyOfflineCache instance = AnatomyOfflineCache._();

  static const String _fullWarmKey = 'anatomy3d.full_cached.v1';
  static const String _liteWarmKey = 'anatomy3d.lite_cached.v1';

  static const List<String> _viewerFiles = [
    'anatomy3d/viewer.html',
    'anatomy3d/viewer.js',
    'anatomy3d/region-map.js',
    'anatomy3d/vendor/three/three.module.js',
    'anatomy3d/vendor/three/three.core.js',
    'anatomy3d/vendor/three/addons/controls/OrbitControls.js',
    'anatomy3d/vendor/three/addons/utils/BufferGeometryUtils.js',
  ];

  static const List<String> _liteAtlases = [
    'anatomy3d/models/atlas-lite-male.json',
    'anatomy3d/models/skin-male.bin.gz',
    'anatomy3d/models/atlas-lite-female.json',
    'anatomy3d/models/skin-female.bin.gz',
  ];

  static const List<String> _fullManifests = [
    'anatomy3d/models/atlas.json',
    'anatomy3d/models/atlas-female.json',
  ];

  /// Manifest chunk paths are relative to `anatomy3d/models/`, not to the app
  /// root. Resolving them at the root produced `/models/body-0.bin.gz` 404s,
  /// which left the full atlas uncached and offline 3D stuck on the lite body.
  static String resolveAssetPath(String path) =>
      path.startsWith('anatomy3d/') ? path : 'anatomy3d/$path';

  /// Chunk URLs from a viewer manifest, kept pure so the contract is testable.
  static List<String> chunkUrlsFromManifest(Map<String, dynamic> manifest) {
    final chunks = manifest['chunks'];
    if (chunks is! List) return const [];
    return [
      for (final chunk in chunks)
        if (chunk is Map && chunk['gzip'] is String) chunk['gzip'] as String,
    ];
  }

  /// Small first-paint set. Safe to run on every online start.
  Future<void> warmLite() async {
    if (!kIsWeb) return;
    await _fetchAll([..._viewerFiles, ..._liteAtlases]);
  }

  /// Full atlas including every muscle, artery and vein mesh.
  ///
  /// Done once per app version; the flag is only written after every fetch
  /// succeeded, so an interrupted download is retried on the next launch.
  Future<void> warmFullIfNeeded() async {
    if (!kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_fullWarmKey) == true) return;

    await warmLite();
    final manifests = await _fetchManifests();
    final chunks = <String>{
      for (final manifest in manifests)
        ...chunkUrlsFromManifest(manifest).map(resolveAssetPath),
    };
    await _fetchAll(chunks.toList()..sort());

    if (!prefs.containsKey(_liteWarmKey)) {
      await prefs.setBool(_liteWarmKey, true);
    }
    await prefs.setBool(_fullWarmKey, true);
  }

  Future<List<Map<String, dynamic>>> _fetchManifests() async {
    final client = http.Client();
    try {
      final result = <Map<String, dynamic>>[];
      for (final path in _fullManifests) {
        final response = await client.get(_uri(path)).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw StateError('Could not cache $path (${response.statusCode})');
        }
        result.add(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return result;
    } finally {
      client.close();
    }
  }

  Future<void> _fetchAll(Iterable<String> paths) async {
    final client = http.Client();
    try {
      // Three concurrent fetches, the same shape the viewer's own loader uses.
      final queue = paths.toList();
      final workers = List.generate(3, (_) async {
        while (queue.isNotEmpty) {
          final path = queue.removeAt(0);
          final response =
              await client.get(_uri(path)).timeout(const Duration(seconds: 45));
          if (response.statusCode != 200) {
            throw StateError('Could not cache $path (${response.statusCode})');
          }
        }
      });
      await Future.wait(workers);
    } finally {
      client.close();
    }
  }

  Uri _uri(String path) => Uri.base.resolve(path);
}
