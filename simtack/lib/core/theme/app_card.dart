import 'package:flutter/material.dart';
import 'app_palette.dart';
import 'app_tokens.dart';

/// Shared card style used across the app — a rounded, subtly shadowed
/// container. Surface and border resolve from AppPalette so the card
/// follows dark mode; the radius, padding and shadow come from the shared
/// scales so every panel in the app agrees on them.
///
/// The defaults used to be their own literals (`EdgeInsets.all(16)`, radius 16,
/// and a third shadow — `blur 10 / 4%` — that matched neither [AppShadow.soft]
/// nor anything else). Two cards on two screens therefore sat at slightly
/// different depths, which reads as sloppiness even when no one can say why.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final double borderWidth;
  final double? width;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.borderRadius = AppRadius.lg,
    this.borderColor,
    this.borderWidth = 1,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? AppPalette.border(context),
          width: borderWidth,
        ),
        boxShadow: AppShadow.soft(context),
      ),
      child: child,
    );
  }
}
