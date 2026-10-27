import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:simtack/core/theme/app_tokens.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import 'package:intl/intl.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/network/api_client.dart';
import '../../../core/offline/offline_repository.dart';
import '../../../core/offline/qr_passport.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/github_kit.dart';
import '../../../core/theme/github_palette.dart';
import '../../../core/theme/app_header_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../report/ui/clinical_report_screen.dart';
import 'qr_scan_screen.dart';
import 'practitioner_scaffold.dart';

/// The one input border shape in this screen: 6px radius, one pixel, so the
/// code field matches every other control on the console.
OutlineInputBorder _inputBorder(Color color, [double width = 1]) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: color, width: width),
    );

const _regionPositions = <String, Offset>{
  'Headache / Cranial': Offset(0.50, 0.08),
  'Head': Offset(0.50, 0.08),
  'Neck': Offset(0.50, 0.15),
  'Chest / Heart': Offset(0.50, 0.27),
  'Chest': Offset(0.50, 0.27),
  'Abdomen (Upper)': Offset(0.50, 0.37),
  'Abdomen (Lower)': Offset(0.50, 0.45),
  'Abdomen (Lower Right)': Offset(0.42, 0.45),
  'Abdomen (Lower Left)': Offset(0.58, 0.45),
  'Abdomen': Offset(0.50, 0.41),
  'Back Pain (Upper)': Offset(0.50, 0.27),
  'Back Pain (Lower)': Offset(0.50, 0.42),
  'Back': Offset(0.50, 0.35),
  'Left Arm / Shoulder': Offset(0.22, 0.27),
  'Right Arm / Shoulder': Offset(0.78, 0.27),
  'Left Shoulder': Offset(0.22, 0.22),
  'Right Shoulder': Offset(0.78, 0.22),
  'Left Arm': Offset(0.16, 0.37),
  'Right Arm': Offset(0.84, 0.37),
  'Left Hand': Offset(0.11, 0.50),
  'Right Hand': Offset(0.89, 0.50),
  'Hip (Left)': Offset(0.38, 0.52),
  'Hip (Right)': Offset(0.62, 0.52),
  'Left Leg / Knee': Offset(0.38, 0.70),
  'Right Leg / Knee': Offset(0.62, 0.70),
  'Left Leg': Offset(0.38, 0.70),
  'Right Leg': Offset(0.62, 0.70),
  'Left Knee': Offset(0.38, 0.75),
  'Right Knee': Offset(0.62, 0.75),
  'Left Foot': Offset(0.38, 0.93),
  'Right Foot': Offset(0.62, 0.93),
  'Groin': Offset(0.50, 0.53),
  'Pelvis': Offset(0.50, 0.50),
};

Offset _positionForRegion(String region) {
  final r = region.toLowerCase();
  for (final entry in _regionPositions.entries) {
    if (r == entry.key.toLowerCase()) return entry.value;
  }
  for (final entry in _regionPositions.entries) {
    if (r.contains(entry.key.toLowerCase()) ||
        entry.key.toLowerCase().contains(r)) {
      return entry.value;
    }
  }
  if (r.contains('chest') || r.contains('heart')) {
    return const Offset(0.50, 0.27);
  }
  if (r.contains('head') || r.contains('cranial')) {
    return const Offset(0.50, 0.08);
  }
  if (r.contains('abdomen') || r.contains('stomach')) {
    return const Offset(0.50, 0.41);
  }
  if (r.contains('back')) return const Offset(0.50, 0.35);
  if (r.contains('left arm') || r.contains('left shoulder')) {
    return const Offset(0.22, 0.27);
  }
  if (r.contains('right arm') || r.contains('right shoulder')) {
    return const Offset(0.78, 0.27);
  }
  if (r.contains('left leg') || r.contains('left knee')) {
    return const Offset(0.38, 0.70);
  }
  if (r.contains('right leg') || r.contains('right knee')) {
    return const Offset(0.62, 0.70);
  }
  return const Offset(0.50, 0.40);
}

class PatientOverviewScreen extends StatefulWidget {
  final String? initialCode;
  const PatientOverviewScreen({super.key, this.initialCode});

  @override
  State<PatientOverviewScreen> createState() => _PatientOverviewScreenState();
}

class _PatientOverviewScreenState extends State<PatientOverviewScreen> {
  final TextEditingController _codeController = TextEditingController();
  Timer? _debounce;

  String _enteredCode = '';
  List<TriageResult> _sessions = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null && widget.initialCode!.isNotEmpty) {
      _codeController.text = widget.initialCode!;
      _enteredCode = widget.initialCode!;
      _loadHistory(widget.initialCode!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged(String value) {
    final code = value.trim().toUpperCase();
    _debounce?.cancel();
    if (code.isEmpty) {
      setState(() {
        _enteredCode = '';
        _sessions = [];
        _error = null;
      });
      return;
    }
    _debounce =
        Timer(const Duration(milliseconds: 500), () => _loadHistory(code));
  }

  Future<void> _loadHistory(String code) async {
    setState(() {
      _enteredCode = code;
      _loading = true;
      _error = null;
    });
    try {
      final results = await OfflineRepository.instance.getLatestVisit(code);
      if (!mounted) return;
      setState(() {
        _sessions = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load patient history.';
        _sessions = [];
        _loading = false;
      });
    }
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push<String>(
      AppPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (code == null || !mounted) return;
    _codeController.text = code;
    _onCodeChanged(code);
  }

  void _openReport(String code) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ClinicalReportScreen(
          patientId: code,
          practitionerMode: true,
        ),
      ),
    );
  }

  /// Score → tone. This is the same mapping the dashboard uses, so a pin on the
  /// body map and a label in the session list cannot disagree about "medium".
  GhTone _riskTone(double? score) {
    final s = score ?? 0.0;
    if (s >= 0.7) return GhTone.danger;
    if (s >= 0.4) return GhTone.attention;
    return GhTone.success;
  }

  String _getRiskLabel(double? score) {
    final s = score ?? 0.0;
    if (s >= 0.7) return 'HIGH';
    if (s >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  String _riskDisplayLabel(BuildContext context, String level) {
    final t = AppLocalizations.of(context)!;
    switch (level) {
      case 'HIGH':
        return t.statHighRiskLabel.toUpperCase();
      case 'MEDIUM':
        return t.statMediumRiskLabel.toUpperCase();
      default:
        return t.statLowRiskLabel.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return PractitionerScaffold(
      currentRoute: '/patients',
      contentBuilder: (context, openDrawer) => Column(
        children: [
          AppHeaderBar(
            title: t.patientOverviewTitle,
            subtitle: t.patientOverviewSubtitle,
            onMenuTap: openDrawer,
            actions: [
              AppHeaderIconButton(
                icon: Icons.refresh,
                tooltip: t.refreshDataTooltip,
                onPressed: _enteredCode.isNotEmpty
                    ? () => _loadHistory(_enteredCode)
                    : null,
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: MediaQuery.of(context).size.width >= 700
                  ? _buildWide()
                  : _buildNarrow(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWide() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 340, child: _leftPanel()),
          const SizedBox(width: 24),
          Expanded(child: _rightPanel()),
        ],
      );

  Widget _buildNarrow() => Column(
        children: [
          _leftPanel(),
          const SizedBox(height: 24),
          _rightPanel(),
        ],
      );

  Widget _leftPanel() {
    final t = AppLocalizations.of(context)!;
    return GhBox(
      header: t.patientLookupTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _codeField(t),
          const SizedBox(height: 12),
          if (!kIsWeb)
            GhButton(
              t.scanPatientQrButton,
              key: const Key('scan_qr_button'),
              icon: Icons.qr_code_scanner,
              variant: GhButtonVariant.secondary,
              expanded: true,
              onPressed: _scanQr,
            ),
          if (_enteredCode.isNotEmpty) ...[
            const SizedBox(height: 16),
            const GhRule(),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: GhColors.surfaceSubtle(context),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: GhColors.border(context)),
              ),
              child: Column(
                children: [
                  Text(t.patientAnonymousIdLabel,
                      style: GhType.meta.copyWith(
                          color: GhColors.fgMuted(context),
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(_enteredCode,
                      style: GhType.code.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: GhColors.accent(context),
                          letterSpacing: 2)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                key: const Key('qr_code_display'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: GhColors.border(context)),
                ),
                child: QrImageView(
                  data: passportPayload(_enteredCode),
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                  eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: AppAccent.info(context)),
                  dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: AppPalette.textPrimary(context)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(t.qrPassportLabel,
                textAlign: TextAlign.center,
                style: GhType.meta.copyWith(
                    color: GhColors.fgMuted(context),
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),
            GhButton(
              t.openFullClinicalReportButton,
              key: const Key('open_report_button'),
              icon: Icons.open_in_new,
              variant: GhButtonVariant.primary,
              expanded: true,
              onPressed: () => _openReport(_enteredCode),
            ),
          ],
        ],
      ),
    );
  }

  /// The lookup field: 32px, one border, blue ring on focus — GitHub's input.
  Widget _codeField(AppLocalizations t) => TextField(
        key: const Key('patient_code_field'),
        controller: _codeController,
        textCapitalization: TextCapitalization.characters,
        style: GhType.code
            .copyWith(color: GhColors.fg(context), fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: GhColors.surface(context),
          hintText: t.patientCodeHint,
          hintStyle: GhType.body.copyWith(
              color: GhColors.fgMuted(context),
              fontWeight: FontWeight.normal,
              letterSpacing: 0),
          prefixIcon:
              Icon(Icons.search, size: 16, color: GhColors.fgMuted(context)),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 32),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: _inputBorder(GhColors.border(context)),
          enabledBorder: _inputBorder(GhColors.border(context)),
          focusedBorder: _inputBorder(GhColors.accent(context), 2),
        ),
        onChanged: _onCodeChanged,
      );

  Widget _rightPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bodyMapCard(),
          const SizedBox(height: 24),
          _timelineCard(),
        ],
      );

  Widget _bodyMapCard() {
    final t = AppLocalizations.of(context)!;
    return GhBox(
      header: t.bodyMapTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 360,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: ModelViewer(
                          src: kIsWeb
                              ? 'models/human_body_male.glb'
                              : 'assets/models/human_body_male.glb',
                          alt: 'Front-view body map — read only',
                          ar: false,
                          autoRotate: false,
                          cameraControls: false,
                          cameraOrbit: '0deg 75deg 105%',
                          disableZoom: true,
                          backgroundColor: GhColors.canvasInset(context),
                          interactionPromptThreshold: 999999,
                        ),
                      ),
                      Positioned.fill(
                        child: PointerInterceptor(
                            intercepting: true, child: const SizedBox.expand()),
                      ),
                      if (_sessions.isNotEmpty)
                        ..._sessions.map((s) {
                          final pos = _positionForRegion(s.bodyRegion);
                          final color = _riskTone(s.riskScore).color(context);
                          final redFlag = s.needsEmergencyCare;
                          final left = pos.dx * constraints.maxWidth - 7;
                          final top = pos.dy * constraints.maxHeight - 7;
                          return Positioned(
                            left: left.clamp(0, constraints.maxWidth - 14),
                            top: top.clamp(0, constraints.maxHeight - 14),
                            child: IgnorePointer(
                              child: Tooltip(
                                message:
                                    '${s.bodyRegion}\n${_riskDisplayLabel(context, _getRiskLabel(s.riskScore))} (${((s.riskScore ?? 0) * 100).toInt()}%)${redFlag ? '\n${AppLocalizations.of(context)!.redFlagLabel}' : ''}',
                                child: Container(
                                  key: Key('pain_dot_${s.id}'),
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: redFlag
                                            ? GhColors.danger(context)
                                            : Colors.white,
                                        width: redFlag ? 2.5 : 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                          color: color.withOpacity(0.55),
                                          blurRadius: 6,
                                          spreadRadius: 1)
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      if (_sessions.isEmpty)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Align(
                              alignment: const Alignment(0, 0.7),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.40),
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.sm)),
                                child: Text(
                                  _loading
                                      ? t.loadingEllipsis
                                      : t.bodyMapEmptyHint,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white70),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (_sessions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(GhTone.danger, t.statHighRiskLabel),
                const SizedBox(width: 16),
                _legendDot(GhTone.attention, t.statMediumRiskLabel),
                const SizedBox(width: 16),
                _legendDot(GhTone.success, t.statLowRiskLabel),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(GhTone tone, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GhDot(tone: tone, size: 10),
          const SizedBox(width: 6),
          Text(label,
              style: GhType.meta.copyWith(
                  color: GhColors.fgMuted(context),
                  fontWeight: FontWeight.w500)),
        ],
      );

  Widget _timelineCard() {
    final t = AppLocalizations.of(context)!;
    return GhBox(
      header: t.visitHistoryTitle,
      headerActions: [
        if (_sessions.isNotEmpty)
          GhCounter('${_sessions.length}', tone: GhTone.accent),
      ],
      flush: true,
      child: _loading
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GhColors.accent(context),
                ),
              ),
            )
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: _errorRow(_error!),
                )
              : _sessions.isEmpty && _enteredCode.isEmpty
                  ? _emptyHint(t.enterCodeForHistoryHint)
                  : _sessions.isEmpty
                      ? _emptyHint(t.noVisitsFoundHint(_enteredCode))
                      : Column(
                          children: [
                            for (var i = 0; i < _sessions.length; i++)
                              _sessionRow(i, _sessions.length - i),
                          ],
                        ),
    );
  }

  /// A timeline row in the console idiom: hairline divider, state labels on the
  /// right, and the risk hue carried by the leading dot instead of by a filled
  /// card — so a long visit list reads as a table, not as a stack of tiles.
  Widget _sessionRow(int index, int sessionNumber) {
    final t = AppLocalizations.of(context)!;
    final session = _sessions[index];
    final score = session.riskScore ?? 0.0;
    final tone = _riskTone(score);
    final label = _riskDisplayLabel(context, _getRiskLabel(score));
    // A red flag outranks the score colour on this row. The score is a clamped
    // sum, so an escalated session can otherwise sit here looking ordinary.
    final redFlag = session.needsEmergencyCare;
    final isClosed = session.status == 'closed';
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(session.createdAt);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: Key('session_row_$index'),
            onTap: () => _openReport(_enteredCode),
            hoverColor: GhColors.surfaceHover(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  GhDot(tone: tone, size: 10),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                t.sessionNumberLabel(sessionNumber),
                                overflow: TextOverflow.ellipsis,
                                style: GhType.bodyStrong
                                    .copyWith(color: GhColors.fg(context)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GhLabel(
                              isClosed
                                  ? t.statusClosedLabel
                                  : t.statusOpenLabel,
                              tone: isClosed ? GhTone.done : GhTone.success,
                            ),
                            if (redFlag) ...[
                              const SizedBox(width: 6),
                              KeyedSubtree(
                                key: Key('red_flag_$index'),
                                child: GhLabel(
                                  t.redFlagLabel.toUpperCase(),
                                  tone: GhTone.danger,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(dateStr,
                            style: GhType.meta
                                .copyWith(color: GhColors.fgMuted(context))),
                        const SizedBox(height: 2),
                        Text(
                            '${session.bodyRegion} • ${session.painType} (${session.severity}/10)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GhType.meta
                                .copyWith(color: GhColors.fgMuted(context))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GhLabel(label, tone: tone),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      size: 16, color: GhColors.fgMuted(context)),
                ],
              ),
            ),
          ),
        ),
        Container(height: 1, color: GhColors.borderMuted(context)),
      ],
    );
  }

  Widget _errorRow(String message) => GhBanner(
        message,
        tone: GhTone.danger,
        icon: Icons.error_outline,
      );

  Widget _emptyHint(String text) => GhEmptyState(
        icon: Icons.history,
        message: text,
      );
}
