import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'anatomy3d_platform_view.dart';
import 'web_interop.dart';

/// Real interactive 3D body-part tapping, backed by BodyParts3D geometry
/// (see assets/anatomy3d/ATTRIBUTION.md for data sourcing/license) rendered
/// in a small Three.js page (web/anatomy3d/viewer.html) and embedded as a
/// Flutter Web platform view. Reports taps through the same
/// `atomybridge-bodypart` window event / [WebInterop] listener the app
/// already had wired (previously unused) for a 2018-era 3D tap attempt —
/// see web_interop_web.dart for the event contract.
///
/// Web only for now: mobile needs the same viewer.html loaded through
/// webview_flutter instead of HtmlElementView, which is follow-up work, not
/// done here yet — see anatomy3d_platform_view_stub.dart.
class Anatomy3DTapView extends StatefulWidget {
  final String gender; // 'Male' or 'Female', matching BodyMapScreen.gender
  final void Function(String region, double x, double y, String? partName)
      onRegionTapped;

  const Anatomy3DTapView({
    super.key,
    required this.gender,
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
    }
  }

  @override
  void dispose() {
    if (kIsWeb) {
      WebInterop.unregisterBodyPartListener(_handleBodyPart);
    }
    super.dispose();
  }

  void _handleBodyPart(String part, double? x, double? y, String? partName) {
    widget.onRegionTapped(part, x ?? 0.5, y ?? 0.5, partName);
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
