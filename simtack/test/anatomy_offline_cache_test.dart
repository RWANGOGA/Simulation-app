import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/offline/anatomy_offline_cache.dart';

void main() {
  test('the offline cache derives chunk URLs from the viewer manifests', () {
    final manifest = <String, dynamic>{
      'chunks': [
        {'url': 'models/body-0.bin', 'gzip': 'models/body-0.bin.gz'},
        {'url': 'models/body-1.bin', 'gzip': 'models/body-1.bin.gz'},
      ],
    };

    expect(
      AnatomyOfflineCache.chunkUrlsFromManifest(manifest),
      ['models/body-0.bin.gz', 'models/body-1.bin.gz'],
    );
    expect(AnatomyOfflineCache.chunkUrlsFromManifest({}), isEmpty);
    expect(
      AnatomyOfflineCache.resolveAssetPath('models/body-0.bin.gz'),
      'anatomy3d/models/body-0.bin.gz',
    );
  });

  test('the tracked viewer source and served copy are byte-identical', () {
    // Two copies of the atlas exist: assets/ is the source, web/ is what the
    // browser actually loads. If they drift, the offline cache would warm one
    // set of geometry while the viewer rendered another.
    for (final name in [
      'viewer.html',
      'viewer.js',
      'region-map.js',
      'models/atlas.json',
      'models/atlas-lite-male.json',
      'models/skin-male.bin.gz',
      'models/atlas-female.json',
      'models/atlas-lite-female.json',
      'models/skin-female.bin.gz',
      'models/female-10.bin.gz',
      'models/female-11.bin.gz',
      'models/female-12.bin.gz',
      'models/female-13.bin.gz',
      'models/female-14.bin.gz',
      'models/female-15.bin.gz',
    ]) {
      final source = File('assets/anatomy3d/$name').readAsBytesSync();
      final served = File('web/anatomy3d/$name').readAsBytesSync();
      expect(served, source, reason: '$name drifted between the two copies');
    }
  });

  test('the female atlas contains full-body systems, not organ-only fragments', () {
    final manifest = jsonDecode(
      File('web/anatomy3d/models/atlas-female.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final parts = (manifest['parts'] as List).cast<Map<String, dynamic>>();
    final chunks = (manifest['chunks'] as List).cast<Map<String, dynamic>>();

    List<Map<String, dynamic>> systemParts(String system) => parts
        .where((p) => p['system'] == system)
        .cast<Map<String, dynamic>>()
        .toList();

    double span(String system, int axis) {
      final sys = systemParts(system);
      var min = double.infinity;
      var max = -double.infinity;
      for (final p in sys) {
        final bounds = (p['bounds'] as List).cast<List>();
        min = min < (bounds[0][axis] as num).toDouble()
            ? min
            : (bounds[0][axis] as num).toDouble();
        max = max > (bounds[1][axis] as num).toDouble()
            ? max
            : (bounds[1][axis] as num).toDouble();
      }
      return max - min;
    }

    expect(systemParts('arterial').length, greaterThan(300),
        reason: 'female arteries should be a full-body system');
    expect(systemParts('venous').length, greaterThan(200),
        reason: 'female veins should be a full-body system');
    expect(systemParts('muscular').length, greaterThan(200),
        reason: 'female muscles should be a full-body system');
    expect(span('arterial', 1), greaterThan(1.4),
        reason: 'arterial system should span the body vertically');
    expect(span('venous', 1), greaterThan(1.4),
        reason: 'venous system should span the body vertically');
    expect(span('muscular', 1), greaterThan(1.4),
        reason: 'muscular system should span the body vertically');
    expect(span('arterial', 0), greaterThan(0.6),
        reason: 'arterial system should span both arms/body width');

    // Every referenced chunk file must exist in both copies.
    for (final chunk in chunks) {
      final gz = chunk['gzip'] as String;
      final web = File('web/anatomy3d/$gz');
      final asset = File('assets/anatomy3d/$gz');
      expect(web.existsSync(), isTrue, reason: '$gz missing from web');
      expect(asset.existsSync(), isTrue, reason: '$gz missing from assets');
      expect(asset.readAsBytesSync(), web.readAsBytesSync(),
          reason: '$gz drifted between copies');
    }
  });
}
