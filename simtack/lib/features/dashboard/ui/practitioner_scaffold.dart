import 'package:flutter/material.dart';
import '../../../core/theme/github_palette.dart';
import 'practitioner_sidebar.dart';
import 'session_trust_strip.dart';

/// The practitioner area's page frame: a GitHub-style canvas with the
/// navigation rail on the left at wide sizes, and behind a drawer at narrow
/// ones.
///
/// The background is the Primer canvas rather than `AppPalette.scaffold` so
/// everything the practitioner sees sits on the console's own surface — the
/// patient flow's purple sheet never appears behind a session list.
class PractitionerScaffold extends StatelessWidget {
  final String currentRoute;
  final Widget Function(BuildContext context, VoidCallback? openDrawer)
      contentBuilder;
  final Widget? footer;

  const PractitionerScaffold({
    super.key,
    required this.currentRoute,
    required this.contentBuilder,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;

        return Scaffold(
          backgroundColor: GhColors.canvas(context),
          drawer: isWide
              ? null
              : Drawer(
                  width: MediaQuery.of(context).size.width * 0.75,
                  backgroundColor: GhColors.surface(context),
                  child: PractitionerSidebar(currentRoute: currentRoute),
                ),
          // Builder sits *under* Scaffold so Scaffold.of(context) can see it.
          // LayoutBuilder's context is an ancestor, so the old
          // Scaffold.maybeOf(context)?.openDrawer() was always a no-op.
          body: Builder(
            builder: (scaffoldContext) {
              return Column(
                children: [
                  // Above the sidebar split, because how current the session is
                  // applies to the whole console, not to one screen in it.
                  const SessionTrustStrip(),
                  Expanded(
                    child: Row(
                      children: [
                        if (isWide)
                          PractitionerSidebar(currentRoute: currentRoute),
                        Expanded(
                          child: contentBuilder(
                            scaffoldContext,
                            isWide
                                ? null
                                : () =>
                                    Scaffold.of(scaffoldContext).openDrawer(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (footer != null) footer!,
                ],
              );
            },
          ),
        );
      },
    );
  }
}
