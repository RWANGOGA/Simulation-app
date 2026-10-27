import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/offline/passport_cipher.dart';
import '../../../core/offline/passport_record.dart';
import '../../../core/offline/qr_passport.dart';
import '../../../core/theme/github_palette.dart';

/// Full-screen camera scanner for the patient's QR clinical passport
/// (blueprint section 2 — "Point camera to scan the patient's QR code").
///
/// Two payload families reach this camera and they are answered differently:
///
///   * a legacy report link ("<base>/#/report/P-XXXX") carries no record, so the
///     only thing to recover is the anonymous patient code, and the full report
///     still needs the network to open;
///   * a sealed passport ("ABP1:...") carries the clinical essentials encrypted
///     inside itself. It is opened with the six-character phrase printed on the
///     card, which works with no connection at all. The record is shown from the
///     decrypted bytes; the code it holds is handed back so the practitioner can
///     also open the full online report if they have a connection.
///
/// The family is decided by the bytes ([passportCarriesRecord]), never by a guess
/// about what the patient meant to show.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  /// Extracts the patient anonymous code from any payload shape the app
  /// might produce:
  ///   * deep-link URL -> "https://rwangoga.github.io/Simulation-app/#/report/P-770043"
  ///   * localhost URL -> "http://localhost:5000/#/report/P-770043"
  ///   * plain code    -> "P-770043"
  /// Returns null when the payload contains no code (wrong QR).
  static String? extractPatientCode(String payload) {
    // Codes are generated as "P-" + uppercase Base36, so a single regex
    // covers every format above without URL parsing.
    final match = RegExp(r'P-[A-Z0-9]{4,}').firstMatch(payload);
    return match?.group(0);
  }

  /// True when the camera found an encrypted passport rather than a link.
  static bool isSealedPassport(String payload) =>
      passportCarriesRecord(payload);

  /// The single decision the scanner makes from a raw barcode and a phrase:
  /// what it yields is either a patient code to open, or a typed reason the
  /// scan did not succeed. Kept free of widgets so it can be tested directly.
  static ScanOutcome openScanned(String payload, String phrase) {
    if (!isSealedPassport(payload)) {
      final code = extractPatientCode(payload);
      return code == null
          ? const ScanOutcome.unrecognized()
          : ScanOutcome.online(code);
    }
    final opening = openPassport(payload, phrase);
    if (opening.isOpened) {
      return ScanOutcome.offline(PassportRecord.fromMap(opening.record!),
          code: opening.record!['c'] as String?);
    }
    return ScanOutcome.rejected(opening.failure!);
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

/// What a scan resolved to. The three states the practitioner can be told
/// about, and nothing in between: this is where a wrong phrase stops being a
/// silent failure and becomes a sentence.
class ScanOutcome {
  const ScanOutcome._(
      {this.code, this.record, this.failure, this.online = false});

  /// Legacy link: a code, but the record lives on a server.
  factory ScanOutcome.online(String code) =>
      ScanOutcome._(code: code, online: true);

  /// Sealed passport opened with the phrase: the record is already in hand.
  factory ScanOutcome.offline(PassportRecord record, {String? code}) =>
      ScanOutcome._(record: record, code: code ?? record.patientCode);

  const ScanOutcome.unrecognized() : this._();

  const ScanOutcome.rejected(PassportFailure failure) : this._(failure: failure);

  final String? code;
  final PassportRecord? record;
  final PassportFailure? failure;
  final bool online;

  bool get hasCode => code != null;
  bool get isOffline => record != null;
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  // The camera fires a detection callback for every frame; without this
  // guard we would pop the route several times over.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      // A legacy link needs no phrase: recover the code and hand it straight
      // back, which is exactly the behaviour that existed before the passport
      // was encrypted.
      if (!QrScanScreen.isSealedPassport(raw)) {
        final code = QrScanScreen.extractPatientCode(raw);
        if (code == null) continue; // ignore unrelated QRs
        _handled = true;
        _controller.stop();
        Navigator.of(context).pop(code);
        return;
      }

      _handled = true;
      _controller.stop();
      _reviewSealedPassport(raw);
      return;
    }
  }

  /// Opens a sealed passport: ask for the phrase, decrypt, then show the record
  /// it carried. Only when a genuine code is recovered does the scan finish; a
  /// wrong phrase or a damaged card returns the practitioner to the camera
  /// rather than pretending the visit was read.
  Future<void> _reviewSealedPassport(String payload) async {
    final recovered = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PassportPhraseSheet(payload: payload),
    );
    if (!mounted) return;
    if (recovered != null && recovered.isNotEmpty) {
      Navigator.of(context).pop(recovered);
      return;
    }
    // Cancelled or refused — give the camera back so another card can be tried.
    _handled = false;
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: GhColors.headerBg(context),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Scan Patient QR',
            style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              // Permission denied / no camera — say why instead of a blank screen.
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera permission denied. Allow camera access in system settings to scan patient QR codes.'
                        : 'Could not start the camera (${error.errorCode}).',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          // Viewfinder frame + hint, purely visual guidance.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: GhColors.accent(context),
                  width: 2,
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Point the camera at the patient\'s QR passport',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// The phrase-entry and offline-record step for a sealed passport.
///
/// It runs in two phases in one sheet: type the phrase, then read the record
/// the phrase unlocked. Keeping both in one route means the decrypted record is
/// never held while a second sheet is stacked on top of it, and a wrong phrase
/// stays on the same screen with the reason spelled out instead of closing and
/// losing what the practitioner was doing.
class _PassportPhraseSheet extends StatefulWidget {
  const _PassportPhraseSheet({required this.payload});

  final String payload;

  @override
  State<_PassportPhraseSheet> createState() => _PassportPhraseSheetState();
}

class _PassportPhraseSheetState extends State<_PassportPhraseSheet> {
  final TextEditingController _phrase = TextEditingController();
  PassportRecord? _record;
  String? _code;
  PassportFailure? _failure;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  void _tryOpen() {
    final outcome = QrScanScreen.openScanned(widget.payload, _phrase.text);
    setState(() {
      _record = outcome.record;
      _code = outcome.code;
      _failure = outcome.failure;
    });
  }

  String _rejectMessage(PassportFailure failure) => switch (failure) {
        // A code that decrypts to nothing meaningful is damaged, not typed
        // wrong; the two need different instructions or a station gives up.
        PassportFailure.malformed =>
          'This passport is damaged or unreadable. Ask for another copy.',
        PassportFailure.authenticationFailed =>
          'That phrase does not open this passport. Check the characters '
              'printed on the card and try again.',
        PassportFailure.notAPassport => 'This is not a patient passport code.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final opened = _record;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: opened == null ? _entryStep(theme) : _recordView(theme, opened),
    );
  }

  Widget _entryStep(ThemeData theme) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Unlock phrase',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Enter the six characters printed under the patient\'s passport '
            'code. This works without internet.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phrase,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Unlock phrase',
              border: const OutlineInputBorder(),
              errorText: _failure == null ? null : _rejectMessage(_failure!),
            ),
            onSubmitted: (_) => _tryOpen(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _tryOpen,
                child: const Text('Open passport'),
              ),
            ],
          ),
        ],
      );

  Widget _recordView(ThemeData theme, PassportRecord record) {
    final bodySmall = theme.textTheme.bodySmall;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Record read offline',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Patient ${record.patientCode}',
              style: theme.textTheme.bodyMedium),
          if (record.tier != null)
            Text('Triage category: ${record.tier}',
                style: theme.textTheme.bodyMedium),
          if (record.escalationLevel != null)
            Text('Red flag: ${record.escalationLevel}', style: bodySmall),
          const SizedBox(height: 12),
          for (final point in record.points)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${point.bodyRegion} — ${point.severity}/10'
                '${point.painType.isEmpty ? '' : ' (${point.painType})'}',
                style: bodySmall,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              const Spacer(),
              FilledButton(
                // Hands the recovered code back so the caller opens the full
                // report; without a connection the essentials above already
                // told the practitioner what they need to act on.
                onPressed: () => Navigator.of(context).pop(_code),
                child: const Text('Open Full Clinical Report'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
