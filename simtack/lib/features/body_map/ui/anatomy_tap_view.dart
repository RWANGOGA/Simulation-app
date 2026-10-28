import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_palette.dart';

/// Pure-Dart replacement for the old single-mesh GLB model-viewer.
///
/// Shows a pre-rendered anatomy image (real BodyParts3D data) and, on tap,
/// reads the pixel color at that spot from a matching (invisible) ID-map
/// image to identify exactly which named region was tapped — no 3D engine,
/// no WebView, no platform-specific JS bridge. Works the same on web,
/// Android, and iOS because it's just image decoding + a color lookup.
class AnatomyTapView extends StatefulWidget {
  final String visibleAsset;
  final String idmapAsset;
  final String colorsAsset;

  /// Called with the ID-map label (e.g. `left upper limb`) and the tap's
  /// position as a fraction of the *drawn image* — not of the widget box.
  /// The two differ whenever the box is not the image's aspect ratio, because
  /// `BoxFit.contain` letterboxes. Reporting image fractions means a marker
  /// lands on the body part the patient tapped at every box shape, and is what
  /// [markers] and [tapLabel] are positioned against.
  final void Function(String region, double x, double y) onRegionTapped;
  final void Function(String message)? onMiss;

  /// Persistent pain markers, in image fractions. Drawn inside the same
  /// letterbox rect the hit test samples, so a dot cannot end up where a tap
  /// would not.
  final List<({String id, double x, double y})> markers;

  /// The transient "you tapped <region>" label, also in image fractions.
  /// Drawn by this widget rather than by the screen so it shares the letterbox
  /// maths with the dots above.
  final ({String text, double x, double y})? tapLabel;

  const AnatomyTapView({
    super.key,
    required this.visibleAsset,
    required this.idmapAsset,
    required this.colorsAsset,
    required this.onRegionTapped,
    this.onMiss,
    this.markers = const [],
    this.tapLabel,
  });

  @override
  State<AnatomyTapView> createState() => _AnatomyTapViewState();
}

class _AnatomyTapViewState extends State<AnatomyTapView> {
  ui.Image? _idmapImage;
  ByteData? _idmapPixels;
  Map<String, List<int>>? _regionColors;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AnatomyTapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idmapAsset != widget.idmapAsset ||
        oldWidget.colorsAsset != widget.colorsAsset) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final colorsJson = await rootBundle.loadString(widget.colorsAsset);
      final decoded = jsonDecode(colorsJson) as Map<String, dynamic>;
      final colors = decoded.map((k, v) =>
          MapEntry(k, (v as List).map((e) => (e as num).toInt()).toList()));

      final bytes = await rootBundle.load(widget.idmapAsset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final pixels =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);

      if (!mounted) return;
      setState(() {
        _regionColors = colors;
        _idmapImage = frame.image;
        _idmapPixels = pixels;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load anatomy data: $e';
        _loading = false;
      });
    }
  }

  ({String label, double dist})? _nearestRegion(int r, int g, int b) {
    if (_regionColors == null) return null;
    String? best;
    double bestDist = double.infinity;
    for (final entry in _regionColors!.entries) {
      final c = entry.value;
      final dr = r - c[0], dg = g - c[1], db = b - c[2];
      final dist = (dr * dr + dg * dg + db * db).toDouble();
      if (dist < bestDist) {
        bestDist = dist;
        best = entry.key;
      }
    }
    if (best == null) return null;
    return (label: best, dist: bestDist);
  }

  /// Where the image actually sits inside the widget box.
  ///
  /// `Image.asset`/`BoxFit.contain` letterboxes (empty padding on either the
  /// sides or top/bottom) whenever the box is not exactly the image's aspect
  /// ratio. Every position this widget reports, samples or draws comes from
  /// here, so the hit test and the markers can never disagree — the bug this
  /// replaces was taps mapped as if the image filled the whole box, sampling a
  /// pixel from a completely different body part than the one under the finger.
  Rect _imageRect(BoxConstraints constraints) {
    final image = _idmapImage!;
    final boxW = constraints.maxWidth;
    final boxH = constraints.maxHeight;
    final imgAspect = image.width / image.height;
    final boxAspect = boxW / boxH;

    if (imgAspect > boxAspect) {
      final renderH = boxW / imgAspect;
      return Rect.fromLTWH(0, (boxH - renderH) / 2, boxW, renderH);
    }
    final renderW = boxH * imgAspect;
    return Rect.fromLTWH((boxW - renderW) / 2, 0, renderW, boxH);
  }

  void _handleTapUp(Offset localPosition, BoxConstraints constraints) {
    if (_idmapPixels == null || _idmapImage == null) return;

    final localX = localPosition.dx;
    final localY = localPosition.dy;
    if (localX < 0 ||
        localY < 0 ||
        localX > constraints.maxWidth ||
        localY > constraints.maxHeight) {
      return;
    }

    final rect = _imageRect(constraints);
    final imgLocalX = localX - rect.left;
    final imgLocalY = localY - rect.top;
    if (imgLocalX < 0 ||
        imgLocalY < 0 ||
        imgLocalX > rect.width ||
        imgLocalY > rect.height) {
      widget.onMiss
          ?.call('That spot is outside the image, not part of the body.');
      return;
    }

    final imgX = (imgLocalX / rect.width * _idmapImage!.width)
        .floor()
        .clamp(0, _idmapImage!.width - 1);
    final imgY = (imgLocalY / rect.height * _idmapImage!.height)
        .floor()
        .clamp(0, _idmapImage!.height - 1);
    final pixelIndex = (imgY * _idmapImage!.width + imgX) * 4;

    final r = _idmapPixels!.getUint8(pixelIndex);
    final g = _idmapPixels!.getUint8(pixelIndex + 1);
    final b = _idmapPixels!.getUint8(pixelIndex + 2);
    final a = _idmapPixels!.getUint8(pixelIndex + 3);

    if (a == 0 || (r > 250 && g > 250 && b > 250)) {
      widget.onMiss?.call('That spot is background, not part of the body.');
      return;
    }

    final match = _nearestRegion(r, g, b);
    // Squared-distance threshold: ~60 straight-line distance in 0-255 RGB
    // space (matches the tolerance already proven out in the tested HTML
    // pages) — squared here since we skip the sqrt for speed.
    if (match == null || match.dist > 3600) {
      widget.onMiss?.call(
          'Could not confidently match that spot — try tapping more centrally on a region.');
      return;
    }

    widget.onRegionTapped(
      match.label,
      imgLocalX / rect.width,
      imgLocalY / rect.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: TextStyle(color: AppAccent.danger(context)),
              textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Listener + onPointerDown instead of GestureDetector.onTapUp: a
        // regular tap recognizer has to win Flutter's "gesture arena"
        // against every other gesture-sensitive widget on screen (the
        // toolbar buttons, the pain-point list, etc.) before it fires,
        // which is almost certainly why taps needed ~20 tries to register.
        // A raw pointer listener reacts on contact, unconditionally, with
        // nothing to lose an arena contest against.
        final rect = _imageRect(constraints);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) =>
              _handleTapUp(event.localPosition, constraints),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(widget.visibleAsset, fit: BoxFit.contain),
                ),
                // Markers and the tap label are positioned inside [rect], the
                // letterboxed image, so a dot sits on the body part actually
                // under it rather than on the empty padding beside it.
                for (final marker in widget.markers)
                  _dot(
                    context,
                    left: rect.left + marker.x * rect.width,
                    top: rect.top + marker.y * rect.height,
                    key: ValueKey('anatomy2d-marker-${marker.id}'),
                  ),
                if (widget.tapLabel != null)
                  _label(context, rect, widget.tapLabel!),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dot(
    BuildContext context, {
    required double left,
    required double top,
    required Key key,
  }) {
    const size = 18.0;
    return Positioned(
      left: left - size / 2,
      top: top - size / 2,
      child: IgnorePointer(
        child: Container(
          key: key,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppAccent.danger(context),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }

  /// The transient region name, centred above the point that was tapped.
  /// Clamped horizontally so a tap near the edge does not push the label off
  /// screen.
  Widget _label(
    BuildContext context,
    Rect rect,
    ({String text, double x, double y}) label,
  ) {
    const width = 180.0;
    final centre = rect.left + label.x * rect.width;
    return Positioned(
      left: (centre - width / 2).clamp(0.0, rect.right - width),
      top: (rect.top + label.y * rect.height - 56).clamp(0.0, rect.bottom),
      width: width,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppPalette.textPrimary(context).withOpacity(0.92),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label.text,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
