import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  final void Function(String region, double x, double y) onRegionTapped;
  final void Function(String message)? onMiss;

  const AnatomyTapView({
    super.key,
    required this.visibleAsset,
    required this.idmapAsset,
    required this.colorsAsset,
    required this.onRegionTapped,
    this.onMiss,
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
    if (oldWidget.idmapAsset != widget.idmapAsset || oldWidget.colorsAsset != widget.colorsAsset) {
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
      final colors = decoded.map((k, v) => MapEntry(k, (v as List).map((e) => (e as num).toInt()).toList()));

      final bytes = await rootBundle.load(widget.idmapAsset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final pixels = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);

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

  void _handleTapUp(TapUpDetails details, BoxConstraints constraints) {
    if (_idmapPixels == null || _idmapImage == null) return;

    final localX = details.localPosition.dx;
    final localY = details.localPosition.dy;
    if (localX < 0 || localY < 0 || localX > constraints.maxWidth || localY > constraints.maxHeight) {
      return;
    }

    // Image.asset uses BoxFit.contain, which letterboxes (adds empty
    // padding on either the sides or top/bottom) whenever the widget's box
    // isn't exactly the image's aspect ratio. The bug this fixes: taps were
    // being mapped as if the image filled the whole box with no padding,
    // so a tap that visually landed on, say, the head could sample a
    // completely different pixel from the ID map — misidentifying the
    // region even though the marker dot itself displayed at the right
    // screen position (that one already used plain box-fraction math).
    final boxW = constraints.maxWidth;
    final boxH = constraints.maxHeight;
    final imgAspect = _idmapImage!.width / _idmapImage!.height;
    final boxAspect = boxW / boxH;

    late double renderW, renderH, offsetX, offsetY;
    if (imgAspect > boxAspect) {
      renderW = boxW;
      renderH = boxW / imgAspect;
      offsetX = 0;
      offsetY = (boxH - renderH) / 2;
    } else {
      renderH = boxH;
      renderW = boxH * imgAspect;
      offsetY = 0;
      offsetX = (boxW - renderW) / 2;
    }

    final imgLocalX = localX - offsetX;
    final imgLocalY = localY - offsetY;
    if (imgLocalX < 0 || imgLocalY < 0 || imgLocalX > renderW || imgLocalY > renderH) {
      widget.onMiss?.call('That spot is outside the image, not part of the body.');
      return;
    }

    final imgX = (imgLocalX / renderW * _idmapImage!.width).floor().clamp(0, _idmapImage!.width - 1);
    final imgY = (imgLocalY / renderH * _idmapImage!.height).floor().clamp(0, _idmapImage!.height - 1);
    final pixelIndex = (imgY * _idmapImage!.width + imgX) * 4;

    final r = _idmapPixels!.getUint8(pixelIndex);
    final g = _idmapPixels!.getUint8(pixelIndex + 1);
    final b = _idmapPixels!.getUint8(pixelIndex + 2);
    final a = _idmapPixels!.getUint8(pixelIndex + 3);

    final normX = localX / constraints.maxWidth;
    final normY = localY / constraints.maxHeight;

    if (a == 0 || (r > 250 && g > 250 && b > 250)) {
      widget.onMiss?.call('That spot is background, not part of the body.');
      return;
    }

    final match = _nearestRegion(r, g, b);
    // Squared-distance threshold: ~60 straight-line distance in 0-255 RGB
    // space (matches the tolerance already proven out in the tested HTML
    // pages) — squared here since we skip the sqrt for speed.
    if (match == null || match.dist > 3600) {
      widget.onMiss?.call('Could not confidently match that spot — try tapping more centrally on a region.');
      return;
    }

    widget.onRegionTapped(match.label, normX, normY);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.redAccent), textAlign: TextAlign.center),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapUp: (details) => _handleTapUp(details, constraints),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Image.asset(widget.visibleAsset, fit: BoxFit.contain),
          ),
        );
      },
    );
  }
}
