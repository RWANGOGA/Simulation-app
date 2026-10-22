import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/models/patient_profile.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/offline/local_database.dart';
import 'package:simtack/core/offline/offline_repository.dart';

import 'clinical_assets.dart';

/// Fixtures for the screens that now read the device's own records.
///
/// These screens stopped calling the API, so a test that used to answer HTTP has
/// to put the same records in the local store instead. Everything here goes
/// through the real [OfflineRepository]: the risk score, the visit grouping and
/// the SHAP explanation are the ones a device with no signal would produce. Only
/// the columns a caller genuinely needs to control — the timestamp, the stored
/// score, the stored explanation — are overwritten afterwards, and they are
/// overwritten on the stored row rather than by hand-building a row, so the
/// shape under test stays the shape the app writes.

/// A complete patient profile, since a report printed for a patient with no
/// demographics looks different from one printed for a real person.
const PatientProfile testPatientProfile = PatientProfile(
  age: 41,
  gender: 'Female',
  weight: 82,
  height: 160,
  fullName: 'Amina Nakato',
  phone: '+256700000000',
  nextOfKinName: 'Joan Nakato',
  nextOfKinPhone: '+256700000001',
);

/// A patient that exists only on this device, with the code its QR carries.
class SeededPatient {
  const SeededPatient({required this.id, required this.code});

  /// Negative by design: it has not reached a server.
  final int id;
  final String code;
}

/// Puts the process in the state a freshly installed device is in: an empty
/// store, no cached database, and the clinical assets in memory the way
/// `main()` loads them before the first frame.
///
/// Without this the store hangs rather than failing: `shared_preferences` has no
/// platform channel in a widget test, so every read waits forever and any
/// `pumpAndSettle` on a screen that shows a spinner times out.
Future<OfflineRepository> setUpOfflineWorld() async {
  SharedPreferences.setMockInitialValues({});
  OfflineRepository.resetForTest();
  await loadClinicalDataForTest();
  return OfflineRepository.instance;
}

/// Records a patient on the device and hands back the code everything else
/// addresses.
Future<SeededPatient> seedPatient({
  PatientProfile profile = testPatientProfile,
}) async {
  final result = await OfflineRepository.instance.createPatient(profile);
  return SeededPatient(id: result.id, code: result.anonymousCode);
}

/// A visit identifier in the same shape the capture flow mints.
String newVisitId() =>
    'visit-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

/// Scores and stores one pain point for [patientCode].
///
/// The optional overrides exist for the screens whose tests are about
/// presentation — a report that shows a HIGH band has to be given a high score,
/// and a timeline has to be given timestamps in a known order — and they are
/// applied to the row the repository just wrote. Nothing else about the record
/// is fabricated.
Future<TriageResult> fileReport({
  required String patientCode,
  required String region,
  String painType = 'throbbing',
  int severity = 5,
  String? visitId,
  String? createdAt,
  double? riskScore,
  String status = 'open',
  String? shapExplanation,
}) async {
  final report = await OfflineRepository.instance.sendTriage(
    TriageReport(
      bodyRegion: region,
      painType: painType,
      severity: severity,
      patientCode: patientCode,
      visitId: visitId ?? newVisitId(),
    ),
  );

  if (createdAt == null &&
      riskScore == null &&
      status == 'open' &&
      shapExplanation == null) {
    return report;
  }

  final db = await LocalDatabase.open();
  await db.mutate((db) {
    final session = db.sessionByLocalId(report.id);
    if (session == null) {
      throw StateError('Report ${report.id} was not stored');
    }
    if (createdAt != null) session['created_at'] = createdAt;
    if (riskScore != null) session['risk_score'] = riskScore;
    if (status != 'open') session['status'] = status;
    if (shapExplanation != null) session['shap_explanation'] = shapExplanation;
  });
  return report;
}
