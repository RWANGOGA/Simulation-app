import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/body_map/ui/anatomy_2d_views.dart';
import 'package:simtack/features/body_map/ui/anatomy_view_mode.dart';

/// The flat renderer reports one of seven coarse labels; everything downstream
/// of a tap — the risk engine, the anatomy KB, every stored session — is keyed
/// on one of the 34 strings in `body_graph.json`. If the translation table ever
/// names a region the graph does not have, a patient's pain point silently
/// lands on a region with no rules, no connections and no knowledge article.
///
/// Read from the real asset rather than a copy of the list here, so the test
/// fails if either side drifts.
Set<String> _bodyGraphRegions() {
  final file = File('assets/clinical/body_graph.json');
  expect(file.existsSync(), isTrue, reason: 'body_graph.json must be present');
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return decoded.keys.toSet();
}

void main() {
  group('flat-view region mapping', () {
    test('every angle resolves all seven ID-map labels to a real region', () {
      final known = _bodyGraphRegions();
      for (final angle in Anatomy2DAngle.values) {
        for (final label in anatomy2DRawLabels) {
          final region = backendRegionFor2D(idmapLabel: label, angle: angle);
          expect(region, isNotNull,
              reason: '$label has no region for ${angle.name}');
          expect(known, contains(region),
              reason: '${angle.name}/$label maps to "$region", which is not a '
                  'body_graph.json region');
        }
      }
    });

    test('the seven labels are exactly the ones the colour table defines', () {
      // A label added to region_id_colors.json without a mapping here would
      // make taps on that region fall through to a miss message.
      final colors = jsonDecode(
        File('assets/anatomy/region_id_colors.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(colors.keys.toSet(), anatomy2DRawLabels);
    });

    test('the trunk means something different on each side of the body', () {
      // One shared colour table cannot tell a frontal torso from a dorsal one,
      // so the angle has to carry that. Collapsing these would file back pain
      // as chest pain.
      final front =
          backendRegionFor2D(idmapLabel: 'trunk', angle: Anatomy2DAngle.front);
      final back =
          backendRegionFor2D(idmapLabel: 'trunk', angle: Anatomy2DAngle.back);
      expect(front, 'Chest / Heart');
      expect(back, 'Back Pain (Upper)');
      expect(front, isNot(back));
    });

    test('a limb resolves to the same region from either side-facing angle',
        () {
      for (final angle in Anatomy2DAngle.values) {
        expect(
          backendRegionFor2D(idmapLabel: 'left upper limb', angle: angle),
          'Left Arm / Shoulder',
        );
      }
    });

    test('an unknown label is a miss, not a guess', () {
      expect(
        backendRegionFor2D(idmapLabel: 'spleen', angle: Anatomy2DAngle.front),
        isNull,
      );
    });

    test('every angle has both of its images on disk', () {
      for (final angle in Anatomy2DAngle.values) {
        expect(File(angle.visibleAsset).existsSync(), isTrue,
            reason: 'missing ${angle.visibleAsset}');
        expect(File(angle.idmapAsset).existsSync(), isTrue,
            reason: 'missing ${angle.idmapAsset}');
      }
      expect(File(anatomy2DColorsAsset).existsSync(), isTrue);
    });
  });

  group('AnatomyViewMode', () {
    test('auto follows the platform, the explicit modes do not', () {
      // The test binding is not web, so the capability flag is false here. That
      // is the same situation as a phone build, which is the case that used to
      // render a placeholder box.
      expect(AnatomyViewMode.platformCanRender3D, isFalse);
      expect(AnatomyViewMode.auto.renders3D(), isFalse);
      expect(AnatomyViewMode.flat.renders3D(), isFalse);
      // A stored `solid` preference made on web must degrade to the flat
      // renderer rather than to nothing.
      expect(AnatomyViewMode.solid.renders3D(), isFalse);
    });

    test('an unknown or missing stored value falls back to auto', () {
      expect(AnatomyViewMode.fromName(null), AnatomyViewMode.auto);
      expect(AnatomyViewMode.fromName(''), AnatomyViewMode.auto);
      expect(AnatomyViewMode.fromName('hologram'), AnatomyViewMode.auto);
    });

    test('every stored name round-trips', () {
      for (final mode in AnatomyViewMode.values) {
        expect(AnatomyViewMode.fromName(mode.name), mode);
      }
    });
  });
}
