/// The practitioner side's component vocabulary, built from GitHub's Primer
/// patterns: a bordered `Box` with a tinted header, rows separated by
/// hairlines, pill labels and counters for state, and a 32px control height.
///
/// These exist so the seven practitioner screens share one implementation of
/// each pattern instead of each re-deriving a card, a filter chip and a status
/// pill in its own purple. Nothing here reads `AppPalette` — that is the
/// patient side's language.
library;

import 'package:flutter/material.dart';

import 'github_palette.dart';

/// A bordered panel: optional tinted header, then body.
///
/// This is GitHub's `.Box`: 6px radius, 1px border, header on `canvas.subtle`
/// with its own bottom border. `flush` drops the body padding so a list of
/// [GhActionRow]s can span the full width and own its hairlines.
class GhBox extends StatelessWidget {
  final String? header;
  final List<Widget> headerActions;
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final bool flush;

  const GhBox({
    super.key,
    this.header,
    this.headerActions = const [],
    this.child,
    this.padding = const EdgeInsets.all(16),
    this.flush = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: GhColors.surface(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GhColors.border(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: GhColors.surfaceSubtle(context),
                border: Border(
                  bottom: BorderSide(color: GhColors.border(context)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      header!,
                      style: GhType.title.copyWith(color: GhColors.fg(context)),
                    ),
                  ),
                  for (final action in headerActions) ...[
                    const SizedBox(width: 8),
                    action,
                  ],
                ],
              ),
            ),
          if (child != null)
            Padding(
              padding: flush ? EdgeInsets.zero : padding,
              child: child!,
            ),
        ],
      ),
    );
  }
}

/// A pill label — GitHub's issue/PR label.
///
/// Meaning comes in as a [GhTone] and the palette decides the hue, so
/// "high risk" and "closed" cannot drift to two different reds.
class GhLabel extends StatelessWidget {
  final String label;
  final GhTone tone;
  final IconData? icon;

  const GhLabel(this.label, {super.key, this.tone = GhTone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final color = tone.color(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tone.subtle(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: GhType.meta.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded count — GitHub's counter next to a nav item or tab.
class GhCounter extends StatelessWidget {
  final String value;
  final GhTone tone;

  const GhCounter(this.value, {super.key, this.tone = GhTone.neutral});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone.subtle(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GhColors.borderMuted(context)),
      ),
      child: Text(
        value,
        style: GhType.meta.copyWith(
          color: GhColors.fgMuted(context),
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      ),
    );
  }
}

/// A small filled dot — the `●` that prefixes an open issue or a job status.
class GhDot extends StatelessWidget {
  final GhTone tone;
  final double size;

  const GhDot({super.key, this.tone = GhTone.success, this.size = 8});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tone.color(context),
        shape: BoxShape.circle,
      ),
    );
  }
}

enum GhButtonVariant {
  /// Green, for the one confirming action on a screen.
  primary,

  /// Grey with a border — the default action, and what GitHub uses for
  /// filter and dropdown triggers.
  secondary,

  /// Red, for destructive confirmation.
  danger,

  /// No fill or border; still a 32px hit target.
  ghost,

  /// No padding at all — an inline link in the accent colour.
  link,

  /// For the dark global nav: hairline outline in the bar's own foreground, so
  /// a labelled action stays legible on `headerBg`.
  header,
}

/// A Primer-sized button: 32px tall, 6px radius, 14px medium label.
class GhButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final GhButtonVariant variant;
  final bool busy;
  final bool expanded;

  const GhButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.variant = GhButtonVariant.secondary,
    this.busy = false,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final BorderSide side;

    switch (variant) {
      case GhButtonVariant.primary:
        background = GhColors.primaryBg(context);
        foreground = GhColors.fgOnEmphasis;
        side = BorderSide(color: Colors.black.withOpacity(0.12));
        break;
      case GhButtonVariant.danger:
        background = GhColors.dangerBg(context);
        foreground = GhColors.fgOnEmphasis;
        side = BorderSide(color: Colors.black.withOpacity(0.12));
        break;
      case GhButtonVariant.secondary:
        background = GhColors.defaultButtonBg(context);
        foreground = GhColors.fg(context);
        side = BorderSide(color: GhColors.border(context));
        break;
      case GhButtonVariant.ghost:
        background = Colors.transparent;
        foreground = GhColors.fg(context);
        side = BorderSide.none;
        break;
      case GhButtonVariant.link:
        background = Colors.transparent;
        foreground = GhColors.accent(context);
        side = BorderSide.none;
        break;
      case GhButtonVariant.header:
        background = Colors.transparent;
        foreground = GhColors.headerFg(context);
        side = BorderSide(
          color: GhColors.headerFg(context).withOpacity(0.32),
        );
        break;
    }

    final isLink = variant == GhButtonVariant.link;
    final style = TextButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledBackgroundColor: background.withOpacity(0.5),
      disabledForegroundColor: foreground.withOpacity(0.5),
      minimumSize: Size(0, isLink ? 24 : 32),
      padding: isLink
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: GhType.body.copyWith(fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: side,
      ),
    );

    final child = busy
        ? SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        : icon != null
            ? Icon(icon, size: 16)
            : null;

    final button = icon != null || busy
        ? TextButton.icon(
            onPressed: busy ? null : onPressed,
            icon: child!,
            label: Text(label),
            style: style,
          )
        : TextButton(
            onPressed: onPressed,
            style: style,
            child: Text(label),
          );

    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A GitHub input: 32px tall, one-pixel border, blue ring on focus.
class GhTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String hint;

  /// A label above the field. GitHub labels the input rather than floating a
  /// legend into the border, which keeps the control's height constant whether
  /// or not it holds content — a form of eight fields does not shift as the
  /// practitioner fills it in.
  final String? label;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;

  /// Trailing control, typically the reveal toggle on a password field.
  final Widget? suffix;
  final double? width;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const GhTextField({
    super.key,
    this.controller,
    required this.hint,
    this.label,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffix,
    this.width,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: color, width: width),
        );

    final field = TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: GhType.body.copyWith(color: GhColors.fg(context)),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: GhColors.surface(context),
        hintText: hint,
        hintStyle: GhType.body.copyWith(color: GhColors.fgMuted(context)),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, size: 16, color: GhColors.fgMuted(context)),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 34, minHeight: 32),
        suffixIcon: suffix,
        suffixIconConstraints: suffix == null
            ? null
            : const BoxConstraints(minWidth: 34, minHeight: 32),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: border(GhColors.border(context)),
        enabledBorder: border(GhColors.border(context)),
        disabledBorder: border(GhColors.borderMuted(context)),
        focusedBorder: border(GhColors.accent(context), 2),
      ),
    );

    final content = label == null
        ? field
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label!,
                style: GhType.bodyStrong.copyWith(color: GhColors.fg(context)),
              ),
              const SizedBox(height: 6),
              field,
            ],
          );

    return width == null ? content : SizedBox(width: width, child: content);
  }
}

/// One row in a [GhSelect]. A `null` [value] is the "all" entry — the one that
/// clears the filter.
class GhOption {
  final String label;
  final String? value;

  const GhOption(this.label, [this.value]);
}

/// A GitHub select. In Primer the dropdown trigger *is* a default button — same
/// fill, same border, same 6px radius — with a chevron where the label ends, so
/// a filter bar of selects reads as a row of controls rather than as a form.
class GhSelect extends StatelessWidget {
  final List<GhOption> options;
  final String? value;
  final IconData icon;
  final ValueChanged<String?> onChanged;

  const GhSelect({
    super.key,
    required this.options,
    required this.onChanged,
    this.value,
    this.icon = Icons.unfold_more,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue =
        options.any((option) => option.value != null && option.value == value);
    final textStyle = GhType.body.copyWith(color: GhColors.fg(context));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: GhColors.defaultButtonBg(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GhColors.border(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: hasValue ? value : null,
          isDense: true,
          borderRadius: BorderRadius.circular(6),
          dropdownColor: GhColors.surface(context),
          style: textStyle,
          icon: Icon(icon, size: 14, color: GhColors.fgMuted(context)),
          hint: Text(options.first.label, style: textStyle),
          items: [
            for (final option in options)
              DropdownMenuItem<String?>(
                value: option.value,
                child: Text(option.label, style: textStyle),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// A full-width clickable row inside a [GhBox]: leading icon, title, optional
/// metadata, optional trailing widget, and a hairline underneath.
class GhActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final GhTone? tone;
  final bool selected;
  final Widget? titlePrefix;

  const GhActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.tone,
    this.selected = false,
    this.titlePrefix,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone?.color(context) ?? GhColors.fgMuted(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: selected ? GhColors.accentSubtle(context) : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: GhColors.surfaceHover(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (titlePrefix != null) ...[
                              titlePrefix!,
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                title,
                                overflow: TextOverflow.ellipsis,
                                style: GhType.body.copyWith(
                                  color: selected
                                      ? GhColors.accent(context)
                                      : GhColors.fg(context),
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              overflow: TextOverflow.ellipsis,
                              style: GhType.meta.copyWith(
                                color: GhColors.fgMuted(context),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Container(height: 1, color: GhColors.borderMuted(context)),
      ],
    );
  }
}

/// A GitHub `.Box`-shaped statistic: muted label, oversized number, tone dot.
class GhStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final GhTone tone;
  final VoidCallback? onTap;
  final double width;
  final String? caption;

  const GhStatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = GhTone.accent,
    this.onTap,
    this.width = 200,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: GhColors.surfaceHover(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: GhColors.surface(context),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: GhColors.border(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 14, color: tone.color(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: GhType.meta.copyWith(
                          color: GhColors.fgMuted(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: GhType.statValue.copyWith(
                    color: GhColors.fg(context),
                  ),
                ),
                if (caption != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      caption!,
                      overflow: TextOverflow.ellipsis,
                      style: GhType.meta.copyWith(
                        color: tone.color(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A heading that sits above a box, with the "see all"-style actions on the
/// right — GitHub's section header.
class GhSectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const GhSectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: GhType.sectionTitle.copyWith(
                  color: GhColors.fg(context),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: GhType.meta.copyWith(
                      color: GhColors.fgMuted(context),
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final action in actions) ...[
          const SizedBox(width: 8),
          action,
        ],
      ],
    );
  }
}

/// A circular monogram, used for the signed-in practitioner.
class GhAvatar extends StatelessWidget {
  final String? name;
  final double size;

  const GhAvatar({super.key, this.name, this.size = 32});

  String get _initials {
    final source = (name ?? '').trim();
    if (source.isEmpty) return 'DR';
    final parts =
        source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: GhColors.surfaceSubtle(context),
        shape: BoxShape.circle,
        border: Border.all(color: GhColors.border(context)),
      ),
      child: Text(
        _initials,
        style: GhType.meta.copyWith(
          color: GhColors.fgMuted(context),
          fontWeight: FontWeight.w600,
          fontSize: size <= 24 ? 10 : 12,
        ),
      ),
    );
  }
}

/// A flash message — success, warning or error — in Primer's tinted style.
class GhBanner extends StatelessWidget {
  final String message;
  final GhTone tone;
  final IconData icon;
  final List<Widget> actions;

  const GhBanner(
    this.message, {
    super.key,
    this.tone = GhTone.accent,
    this.icon = Icons.info_outline,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tone.subtle(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tone.color(context).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: tone.color(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
            ),
          ),
          for (final action in actions) ...[
            const SizedBox(width: 8),
            action,
          ],
        ],
      ),
    );
  }
}

/// A centred empty state: muted glyph, one line of what happened, one line of
/// what to do about it.
class GhEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const GhEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GhColors.surfaceSubtle(context),
              shape: BoxShape.circle,
              border: Border.all(color: GhColors.border(context)),
            ),
            child: Icon(icon, size: 18, color: GhColors.fgMuted(context)),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GhType.body.copyWith(color: GhColors.fgMuted(context)),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A repository-style underline tab bar: the selected tab is bold with a 2px
/// orange rule under it.
class GhUnderlineTabs extends StatelessWidget {
  final List<String> labels;

  /// Optional per-tab glyph. Omit for GitHub's icon-less settings nav.
  final List<IconData>? icons;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const GhUnderlineTabs({
    super.key,
    required this.labels,
    this.icons,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: GhColors.border(context))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index++)
              _tab(context, labels[index], index == selectedIndex, index),
          ],
        ),
      ),
    );
  }

  Widget _tab(BuildContext context, String label, bool selected, int index) {
    final icon = icons != null && index < icons!.length ? icons![index] : null;
    return InkWell(
      onTap: () => onSelected(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  selected ? GhColors.underline(context) : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color:
                    selected ? GhColors.fg(context) : GhColors.fgMuted(context),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GhType.body.copyWith(
                color:
                    selected ? GhColors.fg(context) : GhColors.fgMuted(context),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A one-pixel rule, for separating blocks that are not inside a [GhBox].
class GhRule extends StatelessWidget {
  const GhRule({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: GhColors.borderMuted(context));
  }
}
