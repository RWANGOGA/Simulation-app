import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'anatomy3d_platform_view.dart';
import 'web_interop.dart';

/// One pain marker to draw inside the 3D scene, at its real 3D position —
/// deliberately minimal (not the full [PainPoint]) since this is all the
/// viewer needs to place/update/remove the actual marker object. [id] just
/// needs to be unique within one call to [Anatomy3DTapView]; the list is
/// fully resynced on every change rather than diffed incrementally, so an
/// id being reused across two different calls is harmless.
typedef PainMarker = ({String id, double? x, double? y, double? z});

/// Real interactive 3D body-part tapping, backed by BodyParts3D geometry
/// (see assets/anatomy3d/ATTRIBUTION.md for data sourcing/license) rendered
/// in a small Three.js page (web/anatomy3d/viewer.html) and embedded as a
/// Flutter Web platform view. Reports taps through the same
/// `atomybridge-bodypart` postMessage / [WebInterop] listener contract
/// documented in web_interop_web.dart, and pushes [markers] back INTO the
/// viewer via `postToIframe` so pain markers are real objects in the 3D
/// scene — they rotate correctly with the body, unlike an earlier version
/// that drew them as a flat Flutter-side overlay positioned only for the
/// camera angle at the moment of the original tap (reported directly: the
/// markers visibly "detached" from the body as soon as you rotated it).
///
/// Web only for now: mobile needs the same viewer.html loaded through
/// webview_flutter instead of HtmlElementView, which is follow-up work, not
/// done here yet — see anatomy3d_platform_view_stub.dart.
class Anatomy3DTapView extends StatefulWidget {
  final String gender; // 'Male' or 'Female', matching BodyMapScreen.gender
  final List<PainMarker> markers;
  final void Function(BodyPartTap tap) onRegionTapped;

  const Anatomy3DTapView({
    super.key,
    required this.gender,
    required this.markers,
    required this.onRegionTapped,
  });

  @override
  State<Anatomy3DTapView> createState() => _Anatomy3DTapViewState();
}

class _Anatomy3DTapViewState extends State<Anatomy3DTapView> {
  static int _instanceCounter = 0;
  late final String _viewType;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _viewType = 'anatomy3d-viewer-${_instanceCounter++}';
      final genderParam = widget.gender == 'Female' ? 'female' : 'male';
      registerAnatomy3DPlatformView(
        _viewType,
        'anatomy3d/viewer.html?gender=$genderParam&embedded=1',
      );
      _registered = true;
      WebInterop.registerBodyPartListener(_handleBodyPart);
      _syncMarkers();
    }
  }

  @override
  void didUpdateWidget(covariant Anatomy3DTapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // BodyMapScreen rebuilds this list fresh from _painPoints on every
    // build (a plain .map().toList()), so a same-instance check would
    // never actually skip a real resync — just always resync here, which
    // is cheap (an unchanged marker list is a harmless no-op on the
    // receiving end).
    if (kIsWeb) _syncMarkers();
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WebInterop.unregisterBodyPartListener(_handleBodyPart);
    }
    super.dispose();
  }

  void _syncMarkers() {
    final iframe = anatomy3DIframeFor(_viewType);
    if (iframe == null) return;
    WebInterop.postToIframe(iframe, {
      'type': 'atomybridge-set-markers',
      'points': [
        for (final m in widget.markers)
          {'id': m.id, 'x': m.x, 'y': m.y, 'z': m.z},
      ],
    });
  }

  void _handleBodyPart(BodyPartTap tap) {
    widget.onRegionTapped(tap);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_registered) {
      // Mobile 3D support is follow-up work (see the doc comment above) —
      // this keeps the screen functional rather than showing a blank box.
      return Container(
        color: AppPalette.subtleFill(context),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          'The 3D body view isn\'t available on this platform yet.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppPalette.textMuted(context)),
        ),
      );
    }
    return HtmlElementView(viewType: _viewType);
  }
}
