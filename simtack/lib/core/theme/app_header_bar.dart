import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';

/// Gradient header banner shared by every practitioner screen — replaces
/// the old flat white bar so each screen reads as a distinct, branded
/// space rather than a generic admin panel.
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B21B6), Color(0xFF8B5CF6)],
        ),
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          if (onMenuTap != null) ...[
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: AppLocalizations.of(context)!.menuTooltip,
              onPressed: onMenuTap,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.82)),
                ),
              ],
            ),
          ),
          for (final action in actions) ...[const SizedBox(width: 4), action],
        ],
      ),
    );
  }
}

/// Header icon button pre-styled for the gradient bar (white icon on a
/// translucent white circle) so action icons stay visible on any accent
/// gradient without every call site repeating the same style.
class AppHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget? loadingChild;

  const AppHeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loadingChild,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: loadingChild ?? Icon(icon, color: Colors.white, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
