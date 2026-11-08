import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import 'github_palette.dart';

/// The practitioner area's top bar, in GitHub's global-navigation idiom: a dark
/// chrome strip, the product mark on the left, the page title beside it, and
/// translucent square icon buttons on the right.
///
/// Only practitioner screens use this. The patient side never sees the console
/// chrome — it stays on the purple/teal language of `AppPalette`.
class AppHeaderBar extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onMenuTap;
  final List<Widget> actions;

  const AppHeaderBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.onMenuTap,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: GhColors.headerBg(context),
        border: Border(
          bottom: BorderSide(color: Colors.black.withOpacity(0.28)),
        ),
      ),
      child: Row(
        children: [
          if (onMenuTap != null) ...[
            AppHeaderIconButton(
              icon: Icons.menu,
              tooltip: AppLocalizations.of(context)!.menuTooltip,
              onPressed: onMenuTap,
              compact: true,
            ),
            const SizedBox(width: 8),
          ],
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GhColors.headerFg(context).withOpacity(0.14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: GhColors.headerFg(context).withOpacity(0.24),
              ),
            ),
            child: Icon(
              Icons.monitor_heart_outlined,
              size: 16,
              color: GhColors.headerFg(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: GhType.headerTitle.copyWith(
                    color: GhColors.headerFg(context),
                  ),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: GhType.headerSubtitle.copyWith(
                    color: GhColors.headerFgMuted(context),
                  ),
                ),
              ],
            ),
          ),
          for (final action in actions) ...[
            const SizedBox(width: 6),
            action,
          ],
        ],
      ),
    );
  }
}

/// Square 32px icon button sized for the dark bar.
///
/// `compact` drops the translucent plate, for icons that sit flush in a row
/// (the menu button, which GitHub also leaves unplated).
class AppHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget? loadingChild;
  final bool compact;

  const AppHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loadingChild,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: compact ? Colors.transparent : GhColors.headerActionBg(context),
        borderRadius: BorderRadius.circular(6),
        border: compact
            ? null
            : Border.all(color: GhColors.headerFg(context).withOpacity(0.16)),
      ),
      child: IconButton(
        icon: loadingChild ??
            Icon(icon, color: GhColors.headerFg(context), size: 16),
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
      ),
    );
  }
}
