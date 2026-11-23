import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/offline/passport_cipher.dart';
import '../../../core/offline/passport_record.dart';
import '../../../core/offline/qr_passport.dart';
import '../../../core/theme/app_accent.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page.dart';

/// The page a generic QR scanner opens.
///
/// The QR carries the encrypted record inside a fragment URL. A camera app
/// opens this static page; the practitioner types the phrase printed on the
/// card, and [openPassport] verifies and decrypts the bytes on the device.
/// There is deliberately no `ApiClient` call here: a passport is readable by
/// someone who has never signed in and has no connection.
class PassportUnlockScreen extends StatefulWidget {
  const PassportUnlockScreen({super.key, required this.payload});

  final String payload;

  @override
  State<PassportUnlockScreen> createState() => _PassportUnlockScreenState();
}

class _PassportUnlockScreenState extends State<PassportUnlockScreen> {
  final TextEditingController _phrase = TextEditingController();
  PassportRecord? _record;
  PassportFailure? _failure;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  void _open() {
    final envelope = passportEnvelope(widget.payload);
    if (envelope == null) {
      setState(() => _failure = PassportFailure.notAPassport);
      return;
    }
    final result = openPassport(envelope, _phrase.text);
    setState(() {
      _record = result.isOpened ? PassportRecord.fromMap(result.record!) : null;
      _failure = result.failure;
    });
  }

  String _message(PassportFailure failure) => switch (failure) {
        PassportFailure.malformed =>
          'This passport is damaged or unreadable. Ask for another copy.',
        PassportFailure.authenticationFailed =>
          'That phrase does not open this passport. Check the characters '
              'printed on the card and try again.',
        PassportFailure.notAPassport => 'This is not a patient passport code.',
      };

  @override
  Widget build(BuildContext context) {
    final record = _record;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        title: const Text('Simtack Care · Patient passport'),
        backgroundColor: AppAccent.primaryFill,
        foregroundColor: AppAccent.onPrimary,
      ),
      body: AppPage(
        maxWidth: AppContentWidth.form,
        child: Card(
          color: AppPalette.surface(context),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: record == null ? _entry(context) : _recordView(context, record),
          ),
        ),
      ),
    );
  }

  Widget _entry(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 40, color: AppAccent.primary(context)),
          const SizedBox(height: 12),
          Text(
            'Unlock this passport',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppPalette.textPrimary(context),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'This QR carries the patient record inside it. Enter the six '
            'characters printed under the code to read it here — no internet '
            'or account is needed.',
            style: TextStyle(color: AppPalette.textMuted(context)),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _phrase,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            maxLength: passportPhraseLength,
            inputFormatters: [
              LengthLimitingTextInputFormatter(passportPhraseLength),
              FilteringTextInputFormatter.allow(RegExp(r'[A-Z]')),
            ],
            decoration: InputDecoration(
              labelText: 'Unlock phrase',
              border: const OutlineInputBorder(),
              errorText: _failure == null ? null : _message(_failure!),
            ),
            onSubmitted: (_) => _open(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _open,
            child: const Text('Show patient record'),
          ),
        ],
      );

  Widget _recordView(BuildContext context, PassportRecord record) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  color: AppAccent.success(context)),
              const SizedBox(width: 8),
              Text(
                'Record read offline',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppPalette.textPrimary(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Patient ${record.patientCode}',
            style: TextStyle(color: AppPalette.textPrimary(context)),
          ),
          if (record.tier != null)
            Text('Triage category: ${record.tier}',
                style: TextStyle(color: AppPalette.textSecondary(context))),
          if (record.escalationLevel != null)
            Text('Red flag: ${record.escalationLevel}',
                style: TextStyle(color: AppPalette.textSecondary(context))),
          const SizedBox(height: 16),
          for (final point in record.points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${point.bodyRegion} · ${point.severity}/10'
                '${point.painType.isEmpty ? '' : ' · ${point.painType}'}',
                style: TextStyle(color: AppPalette.textPrimary(context)),
              ),
            ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => setState(() {
              _record = null;
              _failure = null;
              _phrase.clear();
            }),
            child: const Text('Try another phrase'),
          ),
        ],
      );
}
