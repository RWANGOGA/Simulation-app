import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/widgets/body_3d_fallback.dart';

/// The three body views used to mount `ModelViewer` with no capability check,
/// so a browser that cannot create a WebGL context got an empty panel: the
/// renderer throws in its constructor and removes its own element. These tests
/// pin the decision that replaced it — a body is always shown.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('Body3DFallback', () {
    testWidgets('shows a still body when no WebGL context can be created',
        (tester) async {
      await tester.pumpWidget(wrap(const Body3DFallback(
        viewer: Text('live-3d'),
        canRender3D: false,
      )));
      await tester.pump();

      expect(find.byKey(Body3DFallback.stillKey), findsOneWidget);
      expect(find.text('live-3d'), findsNothing);
    });

    testWidgets('mounts the viewer when a context is available',
        (tester) async {
      await tester.pumpWidget(wrap(const Body3DFallback(
        viewer: Text('live-3d'),
        canRender3D: true,
      )));
      await tester.pump();

      expect(find.text('live-3d'), findsOneWidget);
      expect(find.byKey(Body3DFallback.stillKey), findsNothing);
    });

    testWidgets('the still is the same figure the flat body map draws',
        (tester) async {
      await tester.pumpWidget(wrap(const Body3DFallback(
        viewer: Text('live-3d'),
        canRender3D: false,
      )));
      await tester.pump();

      final image = tester.widget<Image>(find.byKey(Body3DFallback.stillKey));
      expect((image.image as AssetImage).assetName, kBodyStillFront);
      // Named rather than opaque: this is the flat renderer's visible layer, so
      // the fallback cannot drift onto a different body than the one the body
      // map shows.
      expect(kBodyStillFront, 'assets/anatomy/body_visible_front.png');
    });

    testWidgets('off the web the platform renderer keeps its chance',
        (tester) async {
      // No override: this asks the platform. The non-web implementation reports
      // available, because a native WebView cannot be probed ahead of time and
      // the screens that use it already work that way.
      await tester
          .pumpWidget(wrap(const Body3DFallback(viewer: Text('live-3d'))));
      await tester.pump();

      expect(find.text('live-3d'), findsOneWidget);
      expect(find.byKey(Body3DFallback.stillKey), findsNothing);
    });
  });
}
