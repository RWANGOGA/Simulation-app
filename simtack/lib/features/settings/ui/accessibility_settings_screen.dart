import 'package:flutter/material.dart';

import '../../../core/accessibility/accessibility_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../l10n/app_localizations.dart';
import 'language_picker_sheet.dart';

/// Scope that exposes the app-wide [AccessibilityController] to every
/// screen below the root MaterialApp, so settings can be read or changed
/// without threading the controller through constructors.
class A11yScope extends InheritedNotifier<AccessibilityController> {
  const A11yScope({
    super.key,
    required AccessibilityController controller,
    required super.child,
  }) : super(notifier: controller);

  static AccessibilityController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<A11yScope>();
    assert(scope != null, 'A11yScope missing — wrap the MaterialApp in A11yScope');
    return scope!.notifier!;
  }
}

/// "Display & Accessibility" settings: enlarge/reduce all text in the app
/// and switch between light, dark, or device-following appearance.
/// Every change applies instantly app-wide and is persisted.
class AccessibilitySettingsScreen extends StatelessWidget {
  const AccessibilitySettingsScreen({super.key});

  static final _scaleLabels = <double, String>{
    0.85: 'Small',
    1.0: 'Default',
    1.3: 'Large',
    1.6: 'Extra large',
  };

  @override
  Widget build(BuildContext context) {
    final controller = A11yScope.of(context);
    final localeController = LocaleScope.of(context);
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.scaffold(context),
        foregroundColor: AppPalette.textPrimary(context),
        elevation: 0,
        title: Text(
          'Display & Accessibility',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppPalette.textPrimary(context),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _sectionLabel(context, 'TEXT SIZE'),
            _card(
              context,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _stepButton(
                        context,
                        icon: Icons.remove,
                        tooltip: 'Reduce text size',
                        onTap: controller.decreaseFontScale,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            'Aa',
                            style: TextStyle(
                              fontSize: 28 * controller.fontScale,
                              fontWeight: FontWeight.bold,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                        ),
                      ),
                      _stepButton(
                        context,
                        icon: Icons.add,
                        tooltip: 'Enlarge text size',
                        onTap: controller.increaseFontScale,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AccessibilityController.fontScaleOptions
                        .map((scale) => ChoiceChip(
                              label: Text(
                                _scaleLabels[scale] ?? '${scale}x',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: controller.fontScale == scale
                                      ? Colors.white
                                      : AppPalette.textSecondary(context),
                                ),
                              ),
                              selected: controller.fontScale == scale,
                              selectedColor: const Color(0xFF6D28D9),
                              backgroundColor: AppPalette.subtleFill(context),
                              onSelected: (_) => controller.setFontScale(scale),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Changes the size of text everywhere in the app.',
                    style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionLabel(context, 'APPEARANCE'),
            _card(
              context,
              child: Column(
                children: [
                  _themeTile(
                    context,
                    controller,
                    mode: ThemeMode.light,
                    icon: Icons.light_mode_outlined,
                    title: 'Light',
                    subtitle: 'Always use the light theme',
                  ),
                  _themeTile(
                    context,
                    controller,
                    mode: ThemeMode.dark,
                    icon: Icons.dark_mode_outlined,
                    title: 'Dark',
                    subtitle: 'Easier on the eyes in low light',
                  ),
                  _themeTile(
                    context,
                    controller,
                    mode: ThemeMode.system,
                    icon: Icons.brightness_auto_outlined,
                    title: 'Follow device',
                    subtitle: 'Match the phone\'s own setting',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionLabel(context, 'LANGUAGE'),
            _card(
              context,
              child: FutureBuilder<LocaleController>(
                future: Future.value(localeController),
                builder: (context, snapshot) {
                  final lc = snapshot.data ?? localeController;
                  final currentCode = lc.locale?.languageCode ?? (lc.isSignLanguage ? LocaleController.signLanguageCode : 'en');
                  return ListTile(
                    leading: const Icon(Icons.translate, color: Color(0xFF6D28D9)),
                    title: Text(
                      'App Language',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary(context),
                      ),
                    ),
                    subtitle: Text(
                      _languageName(context, currentCode),
                      style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF6D28D9)),
                     onTap: () {
                       showModalBottomSheet(
                         context: context,
                         backgroundColor: Colors.white,
                         shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                         builder: (ctx) => LanguagePickerSheet(
                           currentCode: currentCode,
                           onChanged: (code) async {
                             await localeController.setLanguage(code);
                           },
                         ),
                       );
                     },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
          color: AppPalette.textMuted(context),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      // A RadioListTile (see _themeTile) paints its background and ink
      // splashes on the nearest Material ancestor — without this, this
      // Container's own background color hides those effects. Transparent
      // Material adds the painting surface without changing how anything
      // looks; cards with no ListTile-family child are unaffected.
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
  }

  Widget _stepButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppPalette.subtleFill(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: AppPalette.textPrimary(context)),
          ),
        ),
      ),
    );
  }

  Widget _themeTile(
    BuildContext context,
    AccessibilityController controller, {
    required ThemeMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = controller.themeMode == mode;
    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: controller.themeMode,
      onChanged: (value) {
        if (value != null) controller.setThemeMode(value);
      },
      activeColor: const Color(0xFF6D28D9),
      secondary: Icon(
        icon,
        color: selected ? const Color(0xFF6D28D9) : AppPalette.textMuted(context),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppPalette.textPrimary(context),
        ),
      ),
      subtitle: Text(
         subtitle,
        style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
      ),
    );
  }

  String _languageName(BuildContext context, String code) {
    final t = AppLocalizations.of(context)!;
    switch (code) {
      case 'en':
        return t.languageEnglish;
      case 'lg':
        return t.languageLuganda;
      case 'nyn':
        return t.languageRunyankole;
      case 'xog':
        return t.languageLusoga;
      case 'sw':
        return t.languageKiswahili;
      case LocaleController.signLanguageCode:
        return t.languageSignLanguage;
      default:
        return code;
    }
  }
}
