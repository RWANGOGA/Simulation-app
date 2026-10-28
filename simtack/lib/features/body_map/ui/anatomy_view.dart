import 'package:flutter/material.dart';

import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import 'anatomy_2d_views.dart';
import 'anatomy_3d_tap_view.dart';
import 'anatomy_tap_view.dart';
import 'anatomy_view_mode.dart';
import 'web_interop.dart';

/// The one place the app decides how to draw a body.
///
/// Two renderers exist and both work; they are good at different things, so
/// this widget picks between them instead of each screen hard-coding one:
///
/// * **3D** ([Anatomy3DTapView]) — the Three.js viewer. Rotatable, and resolves
///   a tap to one of the 34 region strings `body_graph.json` is keyed on.
///   Needs a browser.
/// * **Flat** ([AnatomyTapView]) — a pre-rendered image plus an invisible ID
///   map, decoded in Dart. Works identically on web, Android and iOS, and
///   resolves only seven coarse regions.
///
/// Before this existed, the body-map screen used the 3D viewer directly and
/// every non-web build got a box reading "the 3D body view isn't available on
/// this platform yet" instead of a body. [AnatomyViewMode.auto] means that can
/// no longer happen: there is always a renderer, and the switch only ever
/// chooses between two working ones.
class AnatomyView extends StatefulWidget {
  /// 'Male' or 'Female', matching `BodyMapScreen.gender`. The 3D viewer loads a
  /// matching atlas; the flat renders are an unbranded/single build, so a
  /// female patient's body is not represented differently there — a real
  /// limitation of the flat assets, not something this widget can fix.
  final String gender;

  /// Every marked point, in either coordinate system. Filtering to the active
  /// renderer happens here so callers never have to know which is live.
  final List<PainMarker> markers;

  /// A tap, already resolved to a region string the rest of the app knows.
  ///
  /// [flatViewKey] is the flat angle the tap came from (`front`, `back`, …), or
  /// null when it came from the 3D viewer. The caller stores it on the point so
  /// a dot is only ever drawn on the image it was placed on.
  final void Function(BodyPartTap tap, String? flatViewKey) onRegionTapped;

  /// Reported for taps that land on background or a colour the ID map cannot
  /// place. The 3D viewer reports its own misses internally.
  final void Function(String message)? onMiss;

  final AnatomyViewMode mode;

  /// Called when the user picks 2D or 3D. Null hides the control entirely —
  /// used by read-only embeds that have nothing to switch.
  final ValueChanged<AnatomyViewMode>? onModeChanged;

  /// The transient tapped-region label, already in image fractions. Only the
  /// flat renderer needs it: it draws the label itself so the label and the
  /// dots share one letterbox calculation instead of two that can drift.
  final ({String text, double x, double y})? tapLabel;

  const AnatomyView({
    super.key,
    required this.gender,
    required this.markers,
    required this.onRegionTapped,
    required this.mode,
    this.onModeChanged,
    this.onMiss,
    this.tapLabel,
  });

  @override
  State<AnatomyView> createState() => _AnatomyViewState();
}

class _AnatomyViewState extends State<AnatomyView> {
  Anatomy2DAngle _angle = Anatomy2DAngle.front;

  @override
  Widget build(BuildContext context) {
    final threeD = widget.mode.renders3D();

    // Angles only apply to the flat renderer: the 3D viewer rotates freely, and
    // offering "front/back" beside a model you can spin would be a control that
    // does nothing visible.
    final showAngles = !threeD;
    final showModeToggle =
        widget.onModeChanged != null && AnatomyViewMode.platformCanRender3D;

    final renderer = threeD ? _build3D() : _build2D();
    if (!showAngles && !showModeToggle) return renderer;

    return Column(
      children: [
        Expanded(child: renderer),
        _Controls(
          showModeToggle: showModeToggle,
          mode: widget.mode,
          onModeChanged: widget.onModeChanged,
          angle: _angle,
          onAngleChanged:
              showAngles ? (angle) => setState(() => _angle = angle) : null,
        ),
      ],
    );
  }

  Widget _build3D() => Anatomy3DTapView(
        gender: widget.gender,
        markers: widget.markers,
        onRegionTapped: (tap) => widget.onRegionTapped(tap, null),
      );

  Widget _build2D() {
    final angle = _angle;
    return AnatomyTapView(
      visibleAsset: angle.visibleAsset,
      idmapAsset: angle.idmapAsset,
      colorsAsset: anatomy2DColorsAsset,
      // A dot is drawn only on the angle it was marked on. Points from the 3D
      // viewer have no flat position at all (their x/y are box fractions from a
      // camera projection), so they are deliberately not drawn here rather than
      // shown at a plausible-looking but wrong spot — they still appear in the
      // screen's location list.
      markers: [
        for (final marker in widget.markers)
          if (marker.viewKey == angle.name &&
              marker.x != null &&
              marker.y != null)
            (id: marker.id, x: marker.x!, y: marker.y!),
      ],
      tapLabel: widget.tapLabel,
      onRegionTapped: (label, x, y) {
        final region = backendRegionFor2D(idmapLabel: label, angle: angle);
        if (region == null) {
          widget.onMiss?.call(
            'Could not tell which body part that was — try a different angle '
            'or switch to the 3D view.',
          );
          return;
        }
        widget.onRegionTapped(
          (
            part: region,
            x: x,
            y: y,
            partName: label,
            hitX: null,
            hitY: null,
            hitZ: null,
          ),
          angle.name,
        );
      },
    );
  }
}

/// The footer: an optional 2D/3D choice plus the flat view's four angles.
class _Controls extends StatelessWidget {
  final bool showModeToggle;
  final AnatomyViewMode mode;
  final ValueChanged<AnatomyViewMode>? onModeChanged;
  final Anatomy2DAngle angle;
  final ValueChanged<Anatomy2DAngle>? onAngleChanged;

  const _Controls({
    required this.showModeToggle,
    required this.mode,
    required this.onModeChanged,
    required this.angle,
    required this.onAngleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final children = <Widget>[];

    if (showModeToggle) {
      children.add(_Segment(
        label: '2D',
        selected: !mode.renders3D(),
        onTap: () => onModeChanged!(AnatomyViewMode.flat),
        tooltip: 'Flat view — works everywhere, seven broad regions',
        key: const ValueKey('anatomy-view-2d'),
      ));
      children.add(const SizedBox(width: 6));
      children.add(_Segment(
        label: '3D',
        selected: mode.renders3D(),
        onTap: () => onModeChanged!(AnatomyViewMode.solid),
        tooltip: '3D view — rotatable, precise body parts',
        key: const ValueKey('anatomy-view-3d'),
      ));
    }

    if (onAngleChanged != null) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 14));
      for (final option in Anatomy2DAngle.values) {
        children.add(_Segment(
          label: switch (option) {
            Anatomy2DAngle.front => t.viewFront,
            Anatomy2DAngle.back => t.viewBack,
            Anatomy2DAngle.left => t.viewLeft,
            Anatomy2DAngle.right => t.viewRight,
          },
          selected: option == angle,
          onTap: () => onAngleChanged!(option),
          key: ValueKey('anatomy-angle-${option.name}'),
        ));
        if (option != Anatomy2DAngle.values.last) {
          children.add(const SizedBox(width: 6));
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppPalette.surface(context),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 0,
        runSpacing: 6,
        children: children,
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Shown on hover/long-press. Only the 2D/3D segments carry one: their
  /// difference is not self-evident from two characters, while the angle names
  /// are the same words already visible on the button.
  final String? tooltip;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = AppAccent.primary(context);
    final button = Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected ? accent : AppPalette.border(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : AppPalette.textSecondary(context),
            ),
          ),
        ),
      ),
    );
    final message = tooltip;
    return message == null ? button : Tooltip(message: message, child: button);
  }
}
