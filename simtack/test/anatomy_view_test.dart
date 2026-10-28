import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/body_map/ui/anatomy_2d_views.dart';
import 'package:simtack/features/body_map/ui/anatomy_3d_tap_view.dart';
import 'package:simtack/features/body_map/ui/anatomy_tap_view.dart';
import 'package:simtack/features/body_map/ui/anatomy_view.dart';
import 'package:simtack/features/body_map/ui/anatomy_view_mode.dart';
import 'package:simtack/features/body_map/ui/web_interop.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

/// These tests assert what [AnatomyView] *decides* — which image it hands the
/// flat renderer and which markers it hands down — rather than what ends up
/// painted. Pixels are not assertable here: the flat renderer decodes real PNGs
/// through `ui.instantiateImageCodec`, and that decode reliably completes for
/// the first test in a file but hangs for later ones, because the second test
/// reuses `rootBundle`'s warm cache and never gets a real-async boundary to
/// decode on. Asserting on the handed-down parameters tests the switch's own
/// logic without depending on the harness reproducing image decoding.
AnatomyTapView _flat(WidgetTester tester) =>
    tester.widget<AnatomyTapView>(find.byType(AnatomyTapView));

/// Two points at identical coordinates on opposite sides of the body. One point
/// alone would pass whether or not the angle filter works.
const _markers = <(String, double, double, String?)>[
  ('front-point', 0.4, 0.3, 'front'),
  ('back-point', 0.4, 0.3, 'back'),
];

List<PainMarker> _painMarkers() => [
      for (final (id, x, y, viewKey) in _markers)
        (id: id, x: x, y: y, z: null, viewKey: viewKey),
    ];

void main() {
  testWidgets('the flat renderer is given only the current angle\'s points',
      (tester) async {
    await tester.pumpWidget(_wrap(AnatomyView(
      gender: 'Female',
      mode: AnatomyViewMode.flat,
      markers: _painMarkers(),
      onRegionTapped: (_, __) {},
    )));
    await tester.pump();

    expect(_flat(tester).idmapAsset, Anatomy2DAngle.front.idmapAsset);
    // Both points are at the same coordinates; only the front one belongs on
    // the front image. Drawing both would put a back-of-body dot on the front.
    expect(_flat(tester).markers.map((m) => m.id), ['front-point']);
  });

  testWidgets('switching angle swaps both the image and the points',
      (tester) async {
    await tester.pumpWidget(_wrap(AnatomyView(
      gender: 'Female',
      mode: AnatomyViewMode.flat,
      markers: _painMarkers(),
      onRegionTapped: (_, __) {},
    )));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('anatomy-angle-back')));
    await tester.pump();

    expect(_flat(tester).idmapAsset, Anatomy2DAngle.back.idmapAsset);
    expect(_flat(tester).visibleAsset, Anatomy2DAngle.back.visibleAsset);
    expect(_flat(tester).markers.map((m) => m.id), ['back-point']);
  });

  testWidgets('a 3D-placed point is not handed to the flat renderer',
      (tester) async {
    // A point from the 3D viewer has box fractions from a camera projection and
    // no viewKey, so there is no honest flat position for it. It is not drawn
    // at a plausible-looking wrong spot; it still appears in the screen's
    // location list.
    await tester.pumpWidget(_wrap(const AnatomyView(
      gender: 'Male',
      mode: AnatomyViewMode.flat,
      markers: [(id: 'solid-point', x: 0.5, y: 0.5, z: 1.7, viewKey: null)],
      onRegionTapped: _ignoreTap,
    )));
    await tester.pump();

    expect(_flat(tester).markers, isEmpty);
  });

  testWidgets('no renderer switch is offered where 3D cannot run',
      (tester) async {
    // `flutter test` is not web, so this is also the phone case: offering a 3D
    // button that cannot work would be the same broken promise as the old
    // placeholder box. The angles are shown instead.
    await tester.pumpWidget(_wrap(AnatomyView(
      gender: 'Male',
      mode: AnatomyViewMode.auto,
      markers: const [],
      onRegionTapped: (_, __) {},
      onModeChanged: (_) {},
    )));
    await tester.pump();

    expect(find.byKey(const ValueKey('anatomy-view-2d')), findsNothing);
    expect(find.byKey(const ValueKey('anatomy-view-3d')), findsNothing);
    expect(find.byKey(const ValueKey('anatomy-angle-front')), findsOneWidget);
  });

  testWidgets('the switch is hidden when the caller has nothing to switch to',
      (tester) async {
    // Read-only embeds pass no onModeChanged.
    await tester.pumpWidget(_wrap(AnatomyView(
      gender: 'Male',
      mode: AnatomyViewMode.flat,
      markers: const [],
      onRegionTapped: (_, __) {},
    )));
    await tester.pump();

    expect(find.byKey(const ValueKey('anatomy-view-2d')), findsNothing);
    // Angles still render: they are part of the flat renderer, not of the
    // mode choice.
    expect(find.byKey(const ValueKey('anatomy-angle-front')), findsOneWidget);
  });
}

void _ignoreTap(BodyPartTap _, String? __) {}
