// The tap-to-organ lookup that replaced retrieval on the body map: the Dart
// port in lib/core/clinical/organ_lookup.dart against the same expectations
// as Backend-fastapi/tests/test_part_lookup.py, plus the card that shows it.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/clinical/organ_lookup.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/offline/offline_repository.dart';
import 'package:simtack/core/widgets/anatomy_insight_card.dart';

import 'support/clinical_assets.dart';

// Same table as SURFACE_CASES in the backend test: the region strings the
// body map really sends, and the report each should open.
const _surfaceCases = <String, String>{
  'Headache / Cranial': 'skull',
  'Neck': 'vertebral_column',
  'Chest / Heart': 'heart',
  'Abdomen (Upper)': 'stomach',
  'Abdomen (Lower Right)': 'appendix',
  'Abdomen (Lower Left)': 'large_intestine',
  'Hips / Groin': 'pelvis',
  'Thighs': 'femur',
  'Back Pain (Upper)': 'vertebral_column',
  'Back Pain (Lower)': 'vertebral_column',
  'Left Shoulder': 'deltoid',
  'Right Shoulder': 'deltoid',
  'Left Armpit': 'lymph_node',
  'Right Armpit': 'lymph_node',
  'Left Elbow': 'humerus',
  'Right Elbow': 'humerus',
  'Left Wrist': 'wrist',
  'Right Wrist': 'wrist',
  'Left Hand': 'hand',
  'Right Hand': 'hand',
  'Left Thigh': 'femur',
  'Right Thigh': 'femur',
  'Left Knee': 'knee',
  'Right Knee': 'knee',
  'Left Shin / Calf': 'tibia',
  'Right Shin / Calf': 'tibia',
  'Left Ankle': 'ligament',
  'Right Ankle': 'ligament',
  'Left Foot': 'foot',
  'Right Foot': 'foot',
  'Left Arm / Shoulder': 'humerus',
  'Right Arm / Shoulder': 'humerus',
  'Left Leg / Knee': 'knee',
  'Right Leg / Knee': 'knee',
};

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> _openCard(WidgetTester tester, Future<AnatomyInsight> future,
    {String region = 'Chest / Heart'}) async {
  await tester.pumpWidget(
      _wrap(AnatomyInsightCard(region: region, future: future)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Clinical Insight: $region'));
  await tester.pumpAndSettle();
}

void main() {
  late OrganLookup lookup;

  setUpAll(() async {
    OrganLookup.resetForTest();
    lookup = await OrganLookup.load(bundle: DiskAssetBundle());
    await loadClinicalDataForTest();
  });

  group('OrganLookup', () {
    test('every body-map region opens the expected report', () {
      for (final entry in _surfaceCases.entries) {
        final body = lookup.lookup(entry.key)!;
        expect(body['match'], 'report', reason: entry.key);
        expect(body['about'], entry.value, reason: entry.key);
      }
    });

    test('every region keeps its red flags and questions', () {
      for (final region in _surfaceCases.keys) {
        final info = lookup.lookup(region)!['region'] as Map<String, dynamic>;
        expect(info['region'], region);
        expect(info['red_flags'] as List, isNotEmpty, reason: region);
        expect(info['suggested_questions'] as List, isNotEmpty,
            reason: region);
      }
    });

    test('a mesh tap takes its safety text from the region passed in', () {
      final body = lookup.lookup('Skin', region: 'Left Knee')!;
      expect(body['about'], 'skin');
      expect((body['region'] as Map)['region'], 'Left Knee');
    });

    test('names are matched ignoring case and spacing', () {
      expect(lookup.lookup('  LEFT   knee ')!['about'], 'knee');
      expect(lookup.lookup('MITRAL VALVE')!['about'], 'heart_valve');
      expect(lookup.lookup('small intestine')!['about'], 'small_intestine');
    });

    test('a mapped part with no report says coming soon', () {
      final body = lookup.lookup('hyoid bone')!;
      expect(body['match'], 'system');
      expect(body['report'], isNull);
      expect(body['message'], OrganLookup.comingSoon);
    });

    test('an unknown name is null (the 404)', () {
      expect(lookup.lookup('not a body part'), isNull);
    });

    test('ships the same data the backend serves', () {
      for (final name in ['organ_reports.json', 'part_to_organ.json']) {
        final backend = File('../Backend-fastapi/app/data/$name');
        if (!backend.existsSync()) continue;
        expect(File('assets/clinical/$name').readAsBytesSync(),
            backend.readAsBytesSync(),
            reason: '$name drifted: rerun scripts.export_offline_assets');
      }
    });
  });

  group('OfflineRepository.organInfo', () {
    test('a skin tap answers for the region, not for skin', () async {
      final insight = await OfflineRepository.instance
          .organInfo(region: 'Left Knee', partName: 'Skin');
      expect(insight.organ!.about, 'knee');
      expect(insight.redFlags, isNotEmpty);
      expect(insight.likelyConditions, isNotEmpty);
    });

    test('a named inner structure answers for that structure', () async {
      final insight = await OfflineRepository.instance
          .organInfo(region: 'Chest / Heart', partName: 'Mitral valve');
      expect(insight.organ!.about, 'heart_valve');
      expect(insight.region, 'Chest / Heart');
    });
  });

  group('AnatomyInsightCard with an organ report', () {
    testWidgets('shows the report and hides build statistics',
        (tester) async {
      final json = lookup.lookup('Chest / Heart')!;
      final insight =
          AnatomyInsight.fromOrganJson(json, region: 'Chest / Heart');
      await _openCard(tester, Future.value(insight));

      expect(find.byKey(const ValueKey('organ-section')), findsOneWidget);
      expect(find.text('Organ reference'), findsOneWidget);
      expect(find.textContaining('About: Heart'), findsOneWidget);
      expect(find.text('Related Disorders'), findsOneWidget);
      final disorder = insight.organ!.disorders.first;
      expect(find.text(OrganInfo.humanize(disorder.name)), findsOneWidget);
      // Conditions, red flags and questions still come from the region.
      expect(find.text('Clinical Red Flags'), findsOneWidget);
      expect(find.text('Patient Assessment Questions'), findsOneWidget);
      expect(find.textContaining('mentions'), findsNothing);
      expect(find.textContaining('sentences_used'), findsNothing);
    });

    testWidgets('shows coming soon for a part with no report',
        (tester) async {
      final insight = AnatomyInsight.fromOrganJson(
          lookup.lookup('hyoid bone', region: 'Neck'),
          region: 'Neck');
      await _openCard(tester, Future.value(insight), region: 'Neck');

      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text(OrganLookup.comingSoon), findsOneWidget);
    });

    testWidgets('says so when the part is unknown', (tester) async {
      final insight =
          AnatomyInsight.fromOrganJson(null, region: 'Chest / Heart');
      await _openCard(tester, Future.value(insight));

      expect(find.text('Not covered'), findsOneWidget);
      expect(find.text(AnatomyInsight.organNotFound), findsOneWidget);
    });

    testWidgets('shows a loading line while the lookup runs',
        (tester) async {
      final pending = Completer<AnatomyInsight>();
      await tester.pumpWidget(_wrap(
          AnatomyInsightCard(region: 'Left Knee', future: pending.future)));
      await tester.pump();

      expect(find.text('Loading body part information...'), findsOneWidget);
      pending.complete(AnatomyInsight.fromOrganJson(
          lookup.lookup('Left Knee'),
          region: 'Left Knee'));
      await tester.pumpAndSettle();
      expect(find.text('Organ reference'), findsOneWidget);
    });
  });

  group('organ report with retrieval as a backstop', () {
    Set<String> lower(Iterable<String> items) =>
        {for (final i in items) i.trim().toLowerCase()};

    void expectNoRepeats(List<String> items, String what) {
      expect(lower(items).length, items.length, reason: '$what repeats');
    }

    test('fills gaps without repeating anything, for every region', () async {
      final repo = OfflineRepository.instance;
      for (final region in _surfaceCases.keys) {
        final organ = await repo.organInfo(region: region, partName: 'Skin');
        final rag = await repo.askAnatomy(region: region);
        final both = AnatomyInsight.combine(organ, rag);

        expect(both.organ!.about, organ.organ!.about, reason: region);
        final names = both.likelyConditions.map((c) => c.name).toList();
        expectNoRepeats(names, '$region conditions');
        expectNoRepeats(both.redFlags, '$region red flags');
        expectNoRepeats(both.suggestedQuestions, '$region questions');
        // Nothing either side had is lost.
        expect(lower(names),
            containsAll(lower(rag.likelyConditions.map((c) => c.name))));
        expect(lower(both.redFlags), containsAll(lower(rag.redFlags)));
        expect(lower(both.redFlags), containsAll(lower(organ.redFlags)));
        // A structure chip never repeats one of the report's parts.
        expect(lower(both.structures).intersection(lower(both.organ!.subparts)),
            isEmpty,
            reason: region);
      }
    });

    test('retrieval stands in when the part has no report', () async {
      final both = await OfflineRepository.instance.organAndRagInsight(
          region: 'Neck', partName: 'Hyoid bone');
      expect(both.organ!.hasReport, isFalse);
      expect(both.answered, isTrue);
      expect(both.summary, isNot(OrganLookup.comingSoon));
      expect(both.summary, isNotEmpty);
      expect(both.sources, isNotEmpty);
    });

    test('a retrieval abstention adds nothing', () {
      final organ = AnatomyInsight.fromOrganJson(lookup.lookup('Left Knee'),
          region: 'Left Knee');
      const abstained = AnatomyInsight(
        region: 'Left Knee',
        complaint: '',
        answered: false,
        llmUsed: false,
        cached: false,
        summary: 'nothing',
        structures: ['Invented'],
        likelyConditions: [],
        redFlags: ['Invented'],
        suggestedQuestions: [],
        disclaimer: '',
        sources: [],
        citations: [],
      );
      expect(identical(AnatomyInsight.combine(organ, abstained), organ),
          isTrue);
    });

    testWidgets('the card says both sources were used', (tester) async {
      final both = await tester.runAsync(() => OfflineRepository.instance
          .organAndRagInsight(region: 'Chest / Heart', partName: 'Skin'));
      await _openCard(tester, Future.value(both!));

      expect(find.text('Organ + clinical reference'), findsOneWidget);
      expect(find.byKey(const ValueKey('organ-section')), findsOneWidget);
      expect(find.text('Region Overview'), findsOneWidget);
    });
  });
}
