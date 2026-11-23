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
    ]) {
      final source = File('assets/anatomy3d/$name').readAsBytesSync();
      final served = File('web/anatomy3d/$name').readAsBytesSync();
      expect(served, source, reason: '$name drifted between the two copies');
    }
  });
}
