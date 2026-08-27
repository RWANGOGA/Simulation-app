import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/app_palette.dart';
import '../../report/ui/clinical_report_screen.dart';
import 'qr_scan_screen.dart';
import 'practitioner_sidebar.dart';

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
    if (r.contains(entry.key.toLowerCase()) || entry.key.toLowerCase().contains(r)) {
      return entry.value;
    }
  }
  if (r.contains('chest') || r.contains('heart')) return const Offset(0.50, 0.27);
  if (r.contains('head') || r.contains('cranial')) return const Offset(0.50, 0.08);
  if (r.contains('abdomen') || r.contains('stomach')) return const Offset(0.50, 0.41);
  if (r.contains('back')) return const Offset(0.50, 0.35);
  if (r.contains('left arm') || r.contains('left shoulder')) return const Offset(0.22, 0.27);
  if (r.contains('right arm') || r.contains('right shoulder')) return const Offset(0.78, 0.27);
  if (r.contains('left leg') || r.contains('left knee')) return const Offset(0.38, 0.70);
  if (r.contains('right leg') || r.contains('right knee')) return const Offset(0.62, 0.70);
  return const Offset(0.50, 0.40);
}

String _qrUrl(String patientCode) {
  if (kIsWeb) {
    final base = Uri.base;
    final url = '${base.origin}${base.path}';
    final cleaned = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    return '$cleaned/#/report/$patientCode';
  }
  return 'https://rwangoga.github.io/Simulation-app/#/report/$patientCode';
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
    _debounce = Timer(const Duration(milliseconds: 500), () => _loadHistory(code));
  }

  Future<void> _loadHistory(String code) async {
    setState(() {
      _enteredCode = code;
      _loading = true;
      _error = null;
    });
    try {
      final results = await ApiClient.getLatestVisit(code);
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

  Color _getRiskColor(double? score) {
    final s = score ?? 0.0;
    if (s >= 0.7) return const Color(0xFFDC2626);
    if (s >= 0.4) return const Color(0xFFF59E0B);
    return const Color(0xFF16A34A);
  }

  String _getRiskLabel(double? score) {
    final s = score ?? 0.0;
    if (s >= 0.7) return 'HIGH';
    if (s >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  @override
  Widget build(BuildContext context) {
    return PractitionerScaffold(
      currentRoute: '/patients',
      contentBuilder: (context, openDrawer) => Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              border: Border(bottom: BorderSide(color: AppPalette.border(context))),
            ),
            child: Row(
              children: [
                if (openDrawer != null) ...[
                  IconButton(
                    icon: const Icon(Icons.menu),
                    tooltip: 'Menu',
                    onPressed: openDrawer,
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Patient Overview',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                      Text(
                        'Review patient history, body map, and triage data.',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF6D28D9)),
                  tooltip: 'Refresh Data',
                  onPressed: _enteredCode.isNotEmpty ? () => _loadHistory(_enteredCode) : null,
                ),
              ],
            ),
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.qr_code_2, 'Patient Lookup'),
          const SizedBox(height: 16),
          TextField(
            key: const Key('patient_code_field'),
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context),
              letterSpacing: 1.2,
            ),
            decoration: InputDecoration(
              hintText: 'Enter patient code e.g. P-770043',
              hintStyle: TextStyle(color: AppPalette.textDisabled(context), fontWeight: FontWeight.normal, letterSpacing: 0),
              prefixIcon: Icon(Icons.search, color: AppPalette.textMuted(context)),
              filled: true,
              fillColor: AppPalette.inputFill(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            ),
            onChanged: _onCodeChanged,
          ),
          const SizedBox(height: 12),
          if (!kIsWeb)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('scan_qr_button'),
                onPressed: _scanQr,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: const Text('Scan Patient QR'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          if (_enteredCode.isNotEmpty) ...[
            const SizedBox(height: 20),
            Divider(color: AppPalette.border(context)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(color: const Color(0xFF6D28D9), borderRadius: BorderRadius.circular(10)),
              child: Column(
                children: [
                  const Text('PATIENT ANONYMOUS ID', style: TextStyle(fontSize: 10, color: Colors.white70, letterSpacing: 2, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(_enteredCode, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
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
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.30), width: 2),
                ),
                child: QrImageView(
                  data: _qrUrl(_enteredCode),
                  version: QrVersions.auto,
                  size: 160,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF6D28D9)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1E293B)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Encrypted QR Passport', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('open_report_button'),
                onPressed: () => _openReport(_enteredCode),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open Full Clinical Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rightPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bodyMapCard(),
          const SizedBox(height: 24),
          _timelineCard(),
        ],
      );

  Widget _bodyMapCard() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.accessibility_new, '3D Body Map'),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 360,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: ModelViewer(
                          src: kIsWeb ? 'models/human_body_male.glb' : 'assets/models/human_body_male.glb',
                          alt: 'Front-view body map — read only',
                          ar: false,
                          autoRotate: false,
                          cameraControls: false,
                          cameraOrbit: '0deg 75deg 105%',
                          disableZoom: true,
                          backgroundColor: AppPalette.subtleFill(context),
                          interactionPromptThreshold: 999999,
                        ),
                      ),
                      Positioned.fill(
                        child: PointerInterceptor(intercepting: true, child: const SizedBox.expand()),
                      ),
                      if (_sessions.isNotEmpty)
                        ..._sessions.map((s) {
                          final pos = _positionForRegion(s.bodyRegion);
                          final color = _getRiskColor(s.riskScore);
                          final left = pos.dx * constraints.maxWidth - 7;
                          final top = pos.dy * constraints.maxHeight - 7;
                          return Positioned(
                            left: left.clamp(0, constraints.maxWidth - 14),
                            top: top.clamp(0, constraints.maxHeight - 14),
                            child: IgnorePointer(
                              child: Tooltip(
                                message: '${s.bodyRegion}\n${_getRiskLabel(s.riskScore)} RISK (${((s.riskScore ?? 0) * 100).toInt()}%)',
                                child: Container(
                                  key: Key('pain_dot_${s.id}'),
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                    boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6, spreadRadius: 1)],
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
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.40), borderRadius: BorderRadius.circular(8)),
                                child: Text(
                                  _loading ? 'Loading...' : 'Enter a patient code to see pain points',
                                  style: const TextStyle(fontSize: 11, color: Colors.white70),
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
                _legendDot(const Color(0xFFDC2626), 'High Risk'),
                const SizedBox(width: 16),
                _legendDot(const Color(0xFFF59E0B), 'Medium Risk'),
                const SizedBox(width: 16),
                _legendDot(const Color(0xFF16A34A), 'Low Risk'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context), fontWeight: FontWeight.w500)),
        ],
      );

  Widget _timelineCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionHeader(Icons.timeline, 'Visit History'),
              if (_sessions.isNotEmpty) ...[
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF6D28D9).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                  child: Text('${_sessions.length} session${_sessions.length == 1 ? '' : 's'}', style: const TextStyle(fontSize: 11, color: Color(0xFF6D28D9), fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 24), child: CircularProgressIndicator(strokeWidth: 2)))
          else if (_error != null)
            _errorRow(_error!)
          else if (_sessions.isEmpty && _enteredCode.isEmpty)
            _emptyHint('Enter a patient code above to view visit history')
          else if (_sessions.isEmpty)
            _emptyHint('No visits found for $_enteredCode')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _sessionRow(i, _sessions.length - i),
            ),
        ],
      ),
    );
  }

  Widget _sessionRow(int index, int sessionNumber) {
    final session = _sessions[index];
    final score = session.riskScore ?? 0.0;
    final color = _getRiskColor(score);
    final label = _getRiskLabel(score);
    final date = session.createdAt;
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(date);

    return InkWell(
      key: Key('session_row_$index'),
      onTap: () => _openReport(_enteredCode),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppPalette.inputFill(context), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppPalette.border(context))),
        child: Row(
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Session $sessionNumber', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppPalette.subtleFill(context),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          session.status == 'closed' ? 'Closed' : 'Open',
                          style: TextStyle(fontSize: 10, color: AppPalette.textMuted(context)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(dateStr, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                  const SizedBox(height: 4),
                  Text('${session.bodyRegion} • ${session.painType} (${session.severity}/10)', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppPalette.textSecondary(context))),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: 0.25))),
              child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: AppPalette.textMuted(context)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFF6D28D9).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: const Color(0xFF6D28D9), size: 18),
          ),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
        ],
      );

  Widget _errorRow(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(children: [const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18), const SizedBox(width: 8), Expanded(child: Text(message, style: const TextStyle(fontSize: 13, color: Color(0xFFDC2626))))]),
      );

  Widget _emptyHint(String text) => Center(
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)))),
      );
}
