import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_accent.dart';
import '../theme/app_palette.dart';
import '../theme/app_tokens.dart';

/// A horizontal, swipeable sequence over a fixed set of already-captured items.
///
/// Modelled on the way a stories surface pages: one item at a time, a segmented
/// rail that names which item you are on, horizontal swipe to move, no
/// auto-advance and no tap-to-advance zones. Both omissions are deliberate and
/// specific to this app:
///
///  - No auto-advance, because the reader is a clinician comparing findings, not
///    a viewer being fed content. A timer that moves a pain-point card while
///    someone is reading it is a defect dressed up as polish.
///  - No tap zones on the left and right halves, because a tap that silently
///    means "next" is invisible to anyone using a screen reader or with limited
///    motor control, and this app has users in both groups. The rail and the
///    explicit chevrons are the controls; they are focusable and labelled.
///
/// It only belongs in read-only contexts — a review of data already recorded.
/// On `body_map_screen.dart` a tap *is* the data (it records a pain location),
/// so a pager there would corrupt input, and it is not used for the intake
/// wizard for the same reason.
class StoryPager extends StatefulWidget {
  const StoryPager({
    super.key,
    required this.count,
    required this.itemBuilder,
    this.height = 460,
    this.semanticsLabel,
  });

  /// Number of items. Zero renders nothing rather than an empty pager, because a
  /// rail with no segments reads as a broken screen.
  final int count;
  final Widget Function(BuildContext context, int index) itemBuilder;

  /// PageView needs a bounded height; it does not size itself to its children.
  final double height;
  final String? semanticsLabel;

  @override
  State<StoryPager> createState() => _StoryPagerState();
}

class _StoryPagerState extends State<StoryPager> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int target) {
    if (target < 0 || target >= widget.count) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Rail(count: widget.count, index: _index),
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.count,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: widget.itemBuilder,
          ),
        ),
        _PagerControls(
          index: _index,
          count: widget.count,
          onPrevious: _index > 0 ? () => _go(_index - 1) : null,
          onNext: _index < widget.count - 1 ? () => _go(_index + 1) : null,
          semanticsLabel: widget.semanticsLabel,
        ),
      ],
    );
  }
}

/// One segment per item, the current one filled. Position within the group,
/// which is what the rail is for — it never shows progress through a timer,
/// because there is no timer.
class _Rail extends StatelessWidget {
  const _Rail({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i == index
                      ? AppAccent.primary(context)
                      : AppPalette.border(context),
                  // Half of sm: the rail is 3px tall, so the rounding is derived
                  // from the scale rather than a new number invented for it.
                  borderRadius: BorderRadius.circular(AppRadius.sm / 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PagerControls extends StatelessWidget {
  const _PagerControls({
    required this.index,
    required this.count,
    required this.onPrevious,
    required this.onNext,
    this.semanticsLabel,
  });

  final int index;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final position = '${index + 1} / $count';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: t.pagerPreviousTooltip,
          color: AppPalette.textSecondary(context),
        ),
        Text(
          position,
          semanticsLabel:
              semanticsLabel == null ? position : '$semanticsLabel, $position',
          // Sized from the TextTheme, not from a number invented here: the
          // colour guard's ratchet counts inline fontSize and this widget should
          // not be the reason it grows.
          style: (Theme.of(context).textTheme.labelMedium ?? const TextStyle())
              .copyWith(
            fontWeight: FontWeight.w600,
            color: AppPalette.textMuted(context),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: t.pagerNextTooltip,
          color: AppPalette.textSecondary(context),
        ),
      ],
    );
  }
}
