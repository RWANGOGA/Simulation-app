import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/core/offline/offline_repository.dart';
import 'package:simtack/core/storage/draft_storage.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';
import 'package:simtack/features/review/ui/review_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

import 'support/offline_fixtures.dart';

void main() {
  setUp(setUpOfflineWorld);

  testWidgets(
    'submitting records every pain point on this device under one visit and '
    'leaves no draft behind',
    (WidgetTester tester) async {
      final patient = await seedPatient();

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReviewScreen(
          painPoints: [
            PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.3),
            PainPoint(region: 'Left Arm / Shoulder', x: 0.8, y: 0.3),
          ],
          patientId: patient.id,
          patientCode: patient.code,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Both points landed in the patient's record, newest first.
      final history =
          await OfflineRepository.instance.getPatientHistory(patient.code);
      expect(
        history.map((r) => r.bodyRegion),
        ['Left Arm / Shoulder', 'Chest / Heart'],
      );
      // One visit, not two: the QR lookup has to return the whole visit.
      expect(history.map((r) => r.visitId).toSet(), hasLength(1));

      // A draft left over from a successful submit would be resubmitted as a
      // duplicate the next time the app opened.
      expect(await DraftStorage.loadAll(), isEmpty);
    },
  );
}
