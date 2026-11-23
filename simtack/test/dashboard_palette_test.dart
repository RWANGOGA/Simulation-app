import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import 'package:simtack/core/theme/github_palette.dart';

/// The practitioner/admin consoles keep the dense GitHub-shaped components but
/// must speak the same colour language as the patient side. These assertions
/// pin the choke point so a future palette split cannot creep back in.
void main() {
  testWidgets('console colours resolve to the patient palette', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (buildContext) {
        context = buildContext;
        return const SizedBox();
      }),
    ));

    expect(GhColors.canvas(context), AppPalette.scaffold(context));
    expect(GhColors.surface(context), AppPalette.surface(context));
    expect(GhColors.fg(context), AppPalette.textPrimary(context));
    expect(GhColors.fgMuted(context), AppPalette.textMuted(context));
    expect(GhColors.border(context), AppPalette.border(context));
    expect(GhColors.accent(context), AppAccent.primary(context));
    expect(GhColors.success(context), AppAccent.success(context));
    expect(GhColors.attention(context), AppAccent.warning(context));
    expect(GhColors.danger(context), AppAccent.danger(context));
    expect(GhColors.done(context), AppAccent.info(context));
    expect(GhColors.headerBg(context), AppAccent.primaryFill);
    expect(GhColors.primaryBg(context), AppAccent.primaryFill);
    expect(GhTone.danger.color(context), AppAccent.danger(context));
  });
}
