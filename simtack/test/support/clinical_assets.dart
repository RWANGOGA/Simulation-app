import 'dart:io';

import 'package:flutter/services.dart';
import 'package:simtack/core/clinical/anatomy_engine.dart';
import 'package:simtack/core/clinical/clinical_data.dart';

/// Reads the app's shipped clinical files straight off disk.
///
/// `flutter test` runs with the package root as its working directory, and
/// reading the files directly keeps these tests independent of whether the test
/// runner happened to build an asset manifest.
class DiskAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

/// Loads the generated clinical assets into [ClinicalData] for a test.
Future<ClinicalData> loadClinicalDataForTest() async {
  ClinicalData.resetForTest();
  AnatomyEngine.resetForTest();
  return ClinicalData.load(bundle: DiskAssetBundle());
}
