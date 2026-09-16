import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'practitioner_sidebar.dart';

class PractitionerScaffold extends StatelessWidget {
  final String currentRoute;
  final Widget Function(BuildContext context, VoidCallback? openDrawer) contentBuilder;

  const PractitionerScaffold({
    super.key,
    required this.currentRoute,
    required this.contentBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        return Scaffold(
          backgroundColor: AppPalette.scaffold(context),
          drawer: isWide
              ? null
              : Drawer(
                  width: MediaQuery.of(context).size.width * 0.75,
                  child: PractitionerSidebar(currentRoute: currentRoute),
                ),
          // Builder sits *under* Scaffold so Scaffold.of(context) can see it.
          // LayoutBuilder's context is an ancestor, so the old
          // Scaffold.maybeOf(context)?.openDrawer() was always a no-op.
          body: Builder(
            builder: (scaffoldContext) {
              return Row(
                children: [
                  if (isWide)
                    PractitionerSidebar(currentRoute: currentRoute),
                  Expanded(
                    child: contentBuilder(
                      scaffoldContext,
                      isWide
                          ? null
                          : () => Scaffold.of(scaffoldContext).openDrawer(),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
