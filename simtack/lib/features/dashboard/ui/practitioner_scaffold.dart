import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'practitioner_sidebar.dart';

class PractitionerScaffold extends StatelessWidget {
  final String currentRoute;
  final Widget Function(BuildContext context, VoidCallback openDrawer) contentBuilder;

  const PractitionerScaffold({
    super.key,
    required this.currentRoute,
    required this.contentBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: Row(
        children: [
          PractitionerSidebar(currentRoute: currentRoute),
          Expanded(
            child: contentBuilder(context, () {
              // Drawer is always visible on desktop, but this callback
              // can be used for mobile drawer toggling in the future.
            }),
          ),
        ],
      ),
    );
  }
}
