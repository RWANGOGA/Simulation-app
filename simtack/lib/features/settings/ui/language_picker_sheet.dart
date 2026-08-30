import 'package:flutter/material.dart';
import '../../../core/locale/app_languages.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/app_palette.dart';

class LanguagePickerSheet extends StatelessWidget {
  final String currentCode;
  final ValueChanged<String> onChanged;

  const LanguagePickerSheet({
    super.key,
    required this.currentCode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.chooseLanguageTitle,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 16),
              ...AppLanguages.pickerOptions.map((lang) {
                final selected = currentCode == lang.flutterCode;
                return ListTile(
                  title: Text(
                    switch (lang.flutterCode) {
                      'en' => t.languageEnglish,
                      'lg' => t.languageLuganda,
                      'nyn' => t.languageRunyankole,
                      'xog' => t.languageLusoga,
                      'sw' => t.languageKiswahili,
                      AppLanguages.signLanguageCode => t.languageSignLanguage,
                      _ => lang.flutterCode,
                    },
                  ),
                  trailing: selected
                      ? Icon(Icons.check_circle, color: const Color(0xFF6D28D9))
                      : null,
                  onTap: () {
                    onChanged(lang.flutterCode);
                    Navigator.of(context).pop();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
