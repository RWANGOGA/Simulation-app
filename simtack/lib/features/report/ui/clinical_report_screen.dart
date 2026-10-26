import 'package:flutter/material.dart';
import 'package:simtack/core/theme/app_tokens.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/offline_repository.dart';
import '../../../core/models/patient_profile.dart';
import '../../../l10n/app_localizations.dart';
import 'shap_explanation_widget.dart';
import '../../../core/widgets/story_pager.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Medical Slate Clinical Palette
// ──────────────────────────────────────────────────────────────────────────────
class ClinicalReportScreen extends StatefulWidget {
  final String patientId;
  // The decision card (status / priority / actions / notes) is for
  // practitioners only — patients viewing their own report must not see it.
  final bool practitionerMode;

  const ClinicalReportScreen({
    super.key,
    required this.patientId,
    this.practitionerMode = false,
  });

  @override
  State<ClinicalReportScreen> createState() => _ClinicalReportScreenState();
}

class _ClinicalReportScreenState extends State<ClinicalReportScreen> {
  List<TriageResult> _reports = [];
  // Sessions grouped into visits (newest first). Practitioners can scrub
  // through the patient's whole history; patients only ever get their
  // latest visit from the backend.
  List<List<TriageResult>> _visits = [];
  int _selectedVisit = 0;
  bool _isLoading = true;
  String? _error;

  // ---- Practitioner decision workflow state ----
  String _decisionStatus = 'open';
  final Set<String> _checkedActions = {};
  final TextEditingController _notesController = TextEditingController();
  bool _savingDecision = false;

  List<TriageResult> get _currentVisit =>
      _visits.isEmpty ? const <TriageResult>[] : _visits[_selectedVisit];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      // Practitioners get the FULL history (visit timeline); patients keep
      // the unauthenticated latest-visit route.
      final results = widget.practitionerMode
          ? await OfflineRepository.instance.getPatientHistory(widget.patientId)
          : await OfflineRepository.instance.getLatestVisit(widget.patientId);
      setState(() {
        _reports = results;
        _visits = _groupIntoVisits(results);
        _selectedVisit = 0;
        _isLoading = false;
        // Pre-fill the decision form from whatever a practitioner saved
        // on a previous review of the selected (latest) visit.
        if (widget.practitionerMode && _currentVisit.isNotEmpty) {
          _applyDecisionFrom(_visitWorst(_currentVisit));
        }
      });
    } catch (e) {
      // These reads are answered by the device, so a 404 means no record with
      // that code exists *here* — not that a server was unreachable. The empty
      // state's own copy already says so; only a real store failure keeps a
      // message of its own.
      final notFound = e is ApiException && e.statusCode == 404;
      if (!mounted) return;
      setState(() {
        if (!notFound) _error = '$e';
        _isLoading = false;
      });
    }
  }

  /// Groups sessions into visits, preserving the backend's newest-first
  /// visit order. Rows without a visit_id (legacy submissions) each count
  /// as a visit of one.
  List<List<TriageResult>> _groupIntoVisits(List<TriageResult> sessions) {
    final grouped = <String, List<TriageResult>>{};
    final order = <String>[];
    for (final s in sessions) {
      final key = s.visitId ?? 'single-${s.id}';
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        order.add(key);
      }
      // Insert at the front so sessions inside a visit read chronologically.
      grouped[key]!.insert(0, s);
    }
    return order.map((k) => grouped[k]!).toList();
  }

  TriageResult _visitWorst(List<TriageResult> visit) => visit.reduce(
        (a, b) => (a.riskScore ?? 0.0) >= (b.riskScore ?? 0.0) ? a : b,
      );

  // Mirrors TriageResult.riskLevel's own thresholds/format ("HIGH RISK" etc.)
  // but through AppLocalizations, since that getter's English text is baked
  // in and shared by other screens that don't need localizing.
  String _riskLevelDisplay(BuildContext context, double score) {
    final t = AppLocalizations.of(context)!;
    if (score >= 0.7) return t.statHighRiskLabel.toUpperCase();
    if (score >= 0.4) return t.statMediumRiskLabel.toUpperCase();
    return t.statLowRiskLabel.toUpperCase();
  }

  /// Switching visits re-points the decision form at that visit's saved
  /// outcome, so each visit is reviewed on its own terms.
  void _applyDecisionFrom(TriageResult worst) {
    _decisionStatus = worst.status;
    _notesController.text = worst.clinicalNotes ?? '';
    _checkedActions
      ..clear()
      ..addAll(worst.actionsTaken);
  }

  void _selectVisit(int index) {
    if (index == _selectedVisit) return;
    setState(() {
      _selectedVisit = index;
      if (_currentVisit.isNotEmpty) {
        _applyDecisionFrom(_visitWorst(_currentVisit));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppPalette.textPrimary(context)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.clinicalReportTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppPalette.textPrimary(context),
              ),
            ),
            Text(
              widget.patientId,
              style: TextStyle(
                fontSize: 12,
                color: AppPalette.textMuted(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          if (widget.practitionerMode)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: Chip(
                label: Text(
                  t.practitionerModeChip,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.textPrimary(context)),
                ),
                backgroundColor: AppAccent.info(context).withOpacity(0.1),
                side: BorderSide(color: AppAccent.info(context)),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // THE WATERMARK
          Positioned.fill(
            child: Center(
              child: Transform.rotate(
                angle: -0.3,
                child: Text(
                  'SIMTACK',
                  style: TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    color: Colors.black.withOpacity(0.03),
                    letterSpacing: 10,
                  ),
                ),
              ),
            ),
          ),

          // MAIN CONTENT
          SafeArea(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                        color: AppAccent.info(context)))
                : (_error != null || _reports.isEmpty)
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline,
                                color: Colors.red, size: 48),
                            const SizedBox(height: 16),
                            Text(
                              _error ?? t.reportNotFoundError,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 16),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _fetchReport,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    AppPalette.textPrimary(context),
                              ),
                              child: Text(t.retryButton,
                                  style: const TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      )
                    : _buildReport(),
          ),
        ],
      ),
    );
  }

  Widget _buildReport() {
    final t = AppLocalizations.of(context)!;
    final visit = _currentVisit;
    final worst = _visitWorst(visit);
    final score = worst.riskScore ?? 0.0;
    final isHighRisk = score >= 0.7;
    final riskColor =
        isHighRisk ? AppAccent.danger(context) : AppAccent.success(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Clinical Document Header ──────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppAccent.info(context).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.medical_services,
                    color: AppAccent.info(context), size: 32),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.clinicalTriageReportTitle,
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppPalette.textPrimary(context)),
                  ),
                  Text(
                    t.officialDocumentSubtitle,
                    style: TextStyle(
                        fontSize: 12, color: AppPalette.textMuted(context)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          // ── Patient ID Passport Bar ───────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.textPrimary(context),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              children: [
                Text(
                  t.patientAnonymousIdLabel,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white70, letterSpacing: 2),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.patientId,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _buildPatientDemographics(),
          const SizedBox(height: 24),

          if (widget.practitionerMode && _visits.length > 1) ...[
            _buildVisitTimeline(),
            const SizedBox(height: 24),
          ],

          // ── Overall Risk Assessment Card ──────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: riskColor),
            ),
            child: Row(
              children: [
                Icon(
                  isHighRisk
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: riskColor,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.riskAssessmentHighestLabel,
                        style: TextStyle(
                            fontSize: 12,
                            color: riskColor,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_riskLevelDisplay(context, score)} (${(score * 100).toInt()}%)',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: riskColor),
                      ),
                      if (visit.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            t.drivenByLabel(worst.bodyRegion),
                            style: TextStyle(
                                fontSize: 12,
                                color: riskColor.withOpacity(0.8)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _buildRiskExplanation(worst),

          if (widget.practitionerMode) ...[
            _buildDecisionCard(worst),
            const SizedBox(height: 24),
          ],

          Text(
            visit.length > 1
                ? t.clinicalDetailsWithCountTitle(visit.length)
                : t.clinicalDetailsTitle,
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppPalette.textPrimary(context)),
          ),
          const SizedBox(height: 16),

          // One pain point: the card is the whole section, and a pager with a
          // single segment would be chrome around nothing.
          //
          // Several: one at a time. A visit with four points stacked vertically
          // asks the clinician to scroll past three of them to weigh the fourth,
          // and the comparison is the work. Each page scrolls on its own, because
          // the cards are not a fixed height and clipping a finding is worse than
          // a scrollbar inside a page.
          if (visit.length == 1)
            _buildPainPointCard(visit.single, 1, 1)
          else
            StoryPager(
              count: visit.length,
              itemBuilder: (context, index) => SingleChildScrollView(
                child:
                    _buildPainPointCard(visit[index], index + 1, visit.length),
              ),
            ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // STRUCTURED PAIN POINT CARD
  // ════════════════════════════════════════════════════════════════════════

  Widget _buildPainPointCard(TriageResult report, int index, int total) {
    final t = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pain Point header (only for multi-point visits)
          if (total > 1)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppPalette.textPrimary(context),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(11)),
              ),
              child: Text(
                '${t.painPointLabel} #$index — ${report.bodyRegion}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── PRIMARY PAIN CHARACTERISTICS ────────────────────────
                _sectionLabel(t.primaryPainCharacteristicsText),
                const SizedBox(height: 8),
                _buildDetailRow(
                    t.painLocationLabel, report.bodyRegion, Icons.location_on),
                _buildDetailRow(t.painTypeLabel,
                    '${report.painType} (${report.severity}/10)', Icons.sick),
                _buildDetailRow(t.directionLabel, report.direction ?? t.naLabel,
                    Icons.arrow_right_alt),
                _buildDetailRow(
                    t.depthLabel, report.depth ?? t.naLabel, Icons.layers),

                // ── SECTION A: PAIN EXPANSION BEHAVIOR ──────────────────
                if (report.expansionBehavior != null &&
                    report.expansionBehavior!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(t.painExpansionBehaviorSectionText),
                  const SizedBox(height: 8),
                  _buildExpansionBadge(report.expansionBehavior!),
                ],

                // ── SECTION B: AGGRAVATING & ALLEVIATING FACTORS ────────
                if (report.triggers.isNotEmpty ||
                    report.relievers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(t.aggravatingAlleviatingFactorsText),
                  const SizedBox(height: 8),
                  if (report.triggers.isNotEmpty) ...[
                    Text(
                      t.triggersWorseLabel,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppAccent.danger(context)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          report.triggers.map((t) => _triggerTag(t)).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (report.relievers.isNotEmpty) ...[
                    Text(
                      t.relieversBetterLabel,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppAccent.success(context)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          report.relievers.map((r) => _relieverTag(r)).toList(),
                    ),
                  ],
                ],

                // ── SECTION C: FUNCTIONAL & DAILY LIFE LIMITATIONS ──────
                if (report.dailyLimitations.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(t.dailyLifeImpactSectionText),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: report.dailyLimitations
                        .map((l) => _limitationBadge(l))
                        .toList(),
                  ),
                ],

                // ── ASSESSMENT ──────────────────────────────────────────
                const SizedBox(height: 16),
                _sectionLabel(t.assessmentSectionText),
                const SizedBox(height: 8),
                _buildDetailRow(
                    t.riskLabel,
                    '${_riskLevelDisplay(context, report.riskScore ?? 0.0)} (${((report.riskScore ?? 0.0) * 100).toInt()}%)',
                    Icons.analytics),
                _buildDetailRow(
                    t.reportedAtLabel,
                    report.createdAt.toString().substring(0, 16),
                    Icons.access_time),

                // ── INTAKE QUESTIONNAIRE Q&A ────────────────────────────
                if (report.questionAnswers != null &&
                    report.questionAnswers!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionLabel(t.intakeQuestionnaireSectionText),
                  const SizedBox(height: 8),
                  ..._buildQuestionAnswersRows(report.questionAnswers!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label (replaces inline section text) ──────────────────────

  Widget _sectionLabel(String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: AppAccent.info(context),
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: AppAccent.info(context).withOpacity(0.2)),
      ],
    );
  }

  // ── Expansion behavior badge ──────────────────────────────────────────

  Widget _buildExpansionBadge(String behavior) {
    final isMultiplying = behavior == 'Multiplying';
    final isSpreading = behavior == 'Spreading';
    final Color badgeColor;
    final IconData icon;
    if (isMultiplying) {
      badgeColor = AppAccent.danger(context);
      icon = Icons.blur_on;
    } else if (isSpreading) {
      badgeColor = AppAccent.warning(context);
      icon = Icons.open_in_full;
    } else {
      badgeColor = AppAccent.success(context);
      icon = Icons.fiber_manual_record;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: badgeColor.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: badgeColor),
          const SizedBox(width: 8),
          Text(
            behavior.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  // ── Trigger tag (red warning) ─────────────────────────────────────────

  Widget _triggerTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppAccent.danger(context).withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppAccent.danger(context).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 14, color: AppAccent.danger(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppAccent.danger(context)),
          ),
        ],
      ),
    );
  }

  // ── Reliever tag (green relief) ───────────────────────────────────────

  Widget _relieverTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppAccent.success(context).withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppAccent.success(context).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.health_and_safety_outlined,
              size: 14, color: AppAccent.success(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppAccent.success(context)),
          ),
        ],
      ),
    );
  }

  // ── Daily limitation badge ────────────────────────────────────────────

  Widget _limitationBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.textPrimary(context).withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border:
            Border.all(color: AppPalette.textPrimary(context).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: 14, color: AppPalette.textPrimary(context)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppPalette.textPrimary(context)),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // DEMOGRAPHICS, TIMELINE, SHAP, DECISION — restyled
  // ════════════════════════════════════════════════════════════════════════

  String _formatDob(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }

  Widget _buildPatientDemographics() {
    final t = AppLocalizations.of(context)!;
    final p = _reports.first;
    final hasAny = p.patientAge != null ||
        p.patientGender != null ||
        p.patientWeight != null ||
        p.patientHeight != null ||
        (p.patientName?.isNotEmpty ?? false) ||
        (p.patientDateOfBirth?.isNotEmpty ?? false) ||
        (p.patientPhone?.isNotEmpty ?? false) ||
        (p.patientAddress?.isNotEmpty ?? false) ||
        (p.patientNextOfKinName?.isNotEmpty ?? false) ||
        (p.patientHospitalName?.isNotEmpty ?? false);
    // A practitioner can still open the edit sheet to ADD demographics
    // that were never captured (anonymous walk-in) — only patients with
    // literally nothing to show AND no edit capability skip the card.
    if (!hasAny && !widget.practitionerMode) return const SizedBox.shrink();

    final chips = <Widget>[];
    if (p.patientName != null && p.patientName!.isNotEmpty) {
      chips.add(_demoChip(Icons.badge_outlined, t.nameLabel, p.patientName!));
    }
    if (p.patientDateOfBirth != null && p.patientDateOfBirth!.isNotEmpty) {
      chips.add(_demoChip(Icons.calendar_today_outlined, t.dobLabel,
          _formatDob(p.patientDateOfBirth!)));
    }
    if (p.patientAge != null) {
      chips.add(_demoChip(
          Icons.cake_outlined, t.ageLabel, '${p.patientAge} ${t.yearsSuffix}'));
    }
    if (p.patientGender != null && p.patientGender!.isNotEmpty) {
      chips.add(
          _demoChip(Icons.person_outline, t.genderLabel, p.patientGender!));
    }
    if (p.patientWeight != null) {
      chips.add(_demoChip(Icons.monitor_weight_outlined, t.weightLabel,
          '${p.patientWeight!.toInt()} ${t.kgSuffix}'));
    }
    if (p.patientHeight != null) {
      chips.add(_demoChip(Icons.height_outlined, t.heightLabel,
          '${p.patientHeight!.toInt()} ${t.cmSuffix}'));
    }
    if (p.patientPhone != null && p.patientPhone!.isNotEmpty) {
      chips.add(_demoChip(Icons.phone_outlined, t.phoneLabel, p.patientPhone!));
    }
    if (p.patientAddress != null && p.patientAddress!.isNotEmpty) {
      chips.add(
          _demoChip(Icons.home_outlined, t.addressLabel, p.patientAddress!));
    }
    if ((p.patientNextOfKinName?.isNotEmpty ?? false) ||
        (p.patientNextOfKinPhone?.isNotEmpty ?? false)) {
      final kin = [
        if (p.patientNextOfKinName != null &&
            p.patientNextOfKinName!.isNotEmpty)
          p.patientNextOfKinName!,
        if (p.patientNextOfKinPhone != null &&
            p.patientNextOfKinPhone!.isNotEmpty)
          p.patientNextOfKinPhone!,
      ].join(' · ');
      chips.add(_demoChip(Icons.family_restroom, t.nextOfKinShortLabel, kin));
    }
    if (p.patientHospitalName != null && p.patientHospitalName!.isNotEmpty) {
      chips.add(_demoChip(Icons.local_hospital_outlined, t.hospitalLabel,
          p.patientHospitalName!));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t.patientProfileSectionTitle,
                style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted(context),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold),
              ),
              if (widget.practitionerMode)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => _showEditDemographicsSheet(p),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.edit_outlined,
                        size: 18, color: AppAccent.info(context)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (chips.isEmpty)
            Text(t.noDemographicsOnFileMessage,
                style: TextStyle(
                    fontSize: 13, color: AppPalette.textDisabled(context)))
          else
            Wrap(spacing: 12, runSpacing: 12, children: chips),
        ],
      ),
    );
  }

  Future<void> _showEditDemographicsSheet(TriageResult p) async {
    final anonymousCode = p.anonymousCode;
    if (anonymousCode == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _EditDemographicsSheet(anonymousCode: anonymousCode, current: p),
    );
    if (saved == true) _fetchReport();
  }

  Widget _buildVisitTimeline() {
    final t = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.visitTimelineTitle,
            style: TextStyle(
                fontSize: 12,
                color: AppPalette.textMuted(context),
                letterSpacing: 1.5,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _visits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _visitCard(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _visitCard(int index) {
    final t = AppLocalizations.of(context)!;
    final visit = _visits[index];
    final worst = _visitWorst(visit);
    final score = worst.riskScore ?? 0.0;
    final isSelected = index == _selectedVisit;
    final riskColor = score >= 0.7
        ? AppAccent.danger(context)
        : score >= 0.4
            ? AppAccent.warning(context)
            : AppAccent.success(context);
    final number = _visits.length - index;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final date = visit.first.createdAt;
    final dateLabel = '${date.day} ${months[date.month - 1]} ${date.year}';

    return GestureDetector(
      onTap: () => _selectVisit(index),
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? AppPalette.textPrimary(context) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected
                ? AppPalette.textPrimary(context)
                : AppPalette.border(context),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.visitNumberLabel(number),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color:
                    isSelected ? Colors.white : AppPalette.textPrimary(context),
              ),
            ),
            Text(
              dateLabel,
              style: TextStyle(
                  fontSize: 11,
                  color: isSelected
                      ? Colors.white70
                      : AppPalette.textMuted(context)),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.white.withOpacity(0.2)
                        : riskColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    '${(score * 100).toInt()}%',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : riskColor),
                  ),
                ),
                const Spacer(),
                Text(
                  t.ptCountLabel(visit.length),
                  style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.white70
                          : AppPalette.textMuted(context)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiskExplanation(TriageResult report) {
    return ShapExplanationWidget(
      shapExplanation: report.shapExplanation,
      expandable: true,
      initiallyExpanded: false,
    );
  }

  /// Urgency implied by the score band alone.
  int _bandRank(double? score) {
    if ((score ?? 0) >= 0.7) return 2;
    if ((score ?? 0) >= 0.4) return 1;
    return 0;
  }

  /// Urgency the clinician is actually asked to act on.
  ///
  /// The score and the red-flag screen answer different questions, and the screen
  /// exists for exactly the cases the bands miss. An ankle sprain with a heart rate
  /// of 130 scores 0.35 - "routine" - while the screen fires emergency on the rate
  /// alone, so reading the score alone suggested "Routine Follow-up" for a patient
  /// whose own report had already tripped an emergency rule.
  ///
  /// The worse of the two wins: nothing changes when they agree, and a red flag is
  /// never softened by a low total. The score can still raise the priority, which
  /// keeps the dozen graded weights doing their job.
  int _urgencyRank(double? score, TriageEscalation? escalation) {
    final band = _bandRank(score);
    final flag = escalation == null
        ? 0
        : escalation.isEmergency
            ? 2
            : escalation.isUrgent
                ? 1
                : 0;
    return flag > band ? flag : band;
  }

  String _suggestedPriority(int rank) {
    if (rank >= 2) return 'Review Immediately';
    if (rank == 1) return 'Urgent Review (24h)';
    return 'Routine Follow-up';
  }

  List<String> _recommendedActions(int rank) {
    if (rank >= 2) {
      return [
        'Physical examination',
        'Urgent review',
        'Consider urgent labs / imaging'
      ];
    }
    if (rank == 1) {
      return ['Urgent review within 24h', 'Targeted physical exam'];
    }
    return ['Routine follow-up', 'Safety-net advice'];
  }

  Future<void> _saveDecision(TriageResult worst) async {
    setState(() => _savingDecision = true);
    try {
      for (final report in _currentVisit) {
        await OfflineRepository.instance.updateTriageDecision(
          report.id,
          status: _decisionStatus,
          priority: _suggestedPriority(
              _urgencyRank(worst.riskScore, worst.escalation)),
          actionsTaken: _checkedActions.toList(),
          clinicalNotes: _notesController.text,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.decisionSavedSnackbar),
              backgroundColor: AppAccent.success(context)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to save decision: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDecision = false);
    }
  }

  Widget _buildDecisionCard(TriageResult worst) {
    final t = AppLocalizations.of(context)!;
    final score = worst.riskScore;
    final escalation = worst.escalation;
    final rank = _urgencyRank(score, escalation);
    final suggested = _suggestedPriority(rank);
    final options = _recommendedActions(rank);
    final allOptions = [
      ...options,
      ..._checkedActions.where((a) => !options.contains(a))
    ];
    final priorityColor = rank >= 2
        ? AppAccent.danger(context)
        : rank == 1
            ? AppAccent.warning(context)
            : AppAccent.success(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
            color: AppPalette.textPrimary(context).withOpacity(0.35)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.triageDecisionTitle,
              style: TextStyle(
                  fontSize: 12,
                  color: AppPalette.textMuted(context),
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.flag_outlined,
                    size: 18, color: AppPalette.textMuted(context)),
                const SizedBox(width: 8),
                Text(t.suggestedPriorityLabel,
                    style: TextStyle(
                        fontSize: 14, color: AppPalette.textPrimary(context))),
                const Spacer(),
                Text(suggested,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: priorityColor)),
              ],
            ),
            // Why the priority is what it is, when that reason is not the score.
            // Without this line a red flag on a 0.35 report reads as the panel
            // contradicting the percentage above it.
            if (escalation != null &&
                _urgencyRank(score, escalation) > _bandRank(score)) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 16, color: AppAccent.danger(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${t.redFlagLabel}: ${escalation.action}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppAccent.danger(context)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(t.statusColonLabel,
                    style: TextStyle(
                        fontSize: 14, color: AppPalette.textPrimary(context))),
                const SizedBox(width: 8),
                for (final value in const ['open', 'closed'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(value == 'closed'
                          ? t.statusClosedLabel
                          : t.statusOpenLabel),
                      selected: _decisionStatus == value,
                      onSelected: (picked) =>
                          setState(() => _decisionStatus = value),
                      selectedColor: value == 'closed'
                          ? AppAccent.success(context).withOpacity(0.2)
                          : AppPalette.textPrimary(context).withOpacity(0.2),
                      checkmarkColor: value == 'closed'
                          ? AppAccent.success(context)
                          : AppPalette.textPrimary(context),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: _decisionStatus == value
                            ? (value == 'closed'
                                ? AppAccent.success(context)
                                : AppPalette.textPrimary(context))
                            : AppPalette.textMuted(context),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.recommendedActionsLabel,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppPalette.textPrimary(context)),
            ),
            ...allOptions.map(
              (action) => CheckboxListTile(
                value: _checkedActions.contains(action),
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: AppAccent.info(context),
                title: Text(action, style: const TextStyle(fontSize: 14)),
                onChanged: (checked) {
                  setState(() {
                    if (checked == true) {
                      _checkedActions.add(action);
                    } else {
                      _checkedActions.remove(action);
                    }
                  });
                },
              ),
            ),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: t.clinicalNotesHint,
                filled: true,
                fillColor: AppPalette.inputFill(context),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _savingDecision ? null : () => _saveDecision(worst),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.textPrimary(context),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                icon: _savingDecision
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(t.saveDecisionButton,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _demoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppAccent.info(context).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppAccent.info(context).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppAccent.info(context), size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 10, color: AppPalette.textMuted(context))),
              Text(value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.textPrimary(context))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppAccent.info(context), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: AppPalette.textMuted(context))),
                Text(value,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppPalette.textPrimary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildQuestionAnswersRows(Map<String, String> answers) {
    return [
      const SizedBox(height: 12),
      ...answers.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(Icons.question_answer_outlined,
                    size: 16, color: AppAccent.info(context)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textSecondary(context)),
                    ),
                    Text(
                      entry.value,
                      style: TextStyle(
                          fontSize: 14, color: AppPalette.textPrimary(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    ];
  }
}

/// Practitioner-only form for correcting a patient's demographics.
/// Pre-filled from the currently displayed report; pops `true` on a
/// successful save so the caller knows to refetch.
class _EditDemographicsSheet extends StatefulWidget {
  final String anonymousCode;
  final TriageResult current;

  const _EditDemographicsSheet(
      {required this.anonymousCode, required this.current});

  @override
  State<_EditDemographicsSheet> createState() => _EditDemographicsSheetState();
}

class _EditDemographicsSheetState extends State<_EditDemographicsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _weightController;
  late final TextEditingController _heightController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _nextOfKinNameController;
  late final TextEditingController _nextOfKinPhoneController;
  late final TextEditingController _hospitalController;
  String? _gender;
  DateTime? _dateOfBirth;
  bool _isSaving = false;
  String? _error;

  static const _genders = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
    final p = widget.current;
    _nameController = TextEditingController(text: p.patientName ?? '');
    _ageController =
        TextEditingController(text: p.patientAge?.toString() ?? '');
    _weightController =
        TextEditingController(text: p.patientWeight?.toString() ?? '');
    _heightController =
        TextEditingController(text: p.patientHeight?.toString() ?? '');
    _phoneController = TextEditingController(text: p.patientPhone ?? '');
    _addressController = TextEditingController(text: p.patientAddress ?? '');
    _nextOfKinNameController =
        TextEditingController(text: p.patientNextOfKinName ?? '');
    _nextOfKinPhoneController =
        TextEditingController(text: p.patientNextOfKinPhone ?? '');
    _hospitalController =
        TextEditingController(text: p.patientHospitalName ?? '');
    _gender = (p.patientGender?.isNotEmpty ?? false) &&
            _genders.contains(p.patientGender)
        ? p.patientGender
        : null;
    _dateOfBirth = p.patientDateOfBirth != null
        ? DateTime.tryParse(p.patientDateOfBirth!)
        : null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nextOfKinNameController.dispose();
    _nextOfKinPhoneController.dispose();
    _hospitalController.dispose();
    super.dispose();
  }

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: AppLocalizations.of(context)!.dateOfBirthHelpText,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _ageController.text = _calculateAge(picked).toString();
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final age = int.tryParse(_ageController.text.trim());
    final weight = double.tryParse(_weightController.text.trim());
    final height = double.tryParse(_heightController.text.trim());
    if (age == null || _gender == null || weight == null || height == null) {
      setState(() => _error =
          AppLocalizations.of(context)!.ageGenderWeightHeightRequiredError);
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await OfflineRepository.instance.updatePatientDemographics(
        widget.anonymousCode,
        PatientProfile(
          age: age,
          gender: _gender!,
          weight: weight,
          height: height,
          fullName: _nameController.text.trim(),
          dateOfBirth: _dateOfBirth,
          phone: _phoneController.text.trim(),
          address: _addressController.text.trim(),
          nextOfKinName: _nextOfKinNameController.text.trim(),
          nextOfKinPhone: _nextOfKinPhoneController.text.trim(),
          hospitalName: _hospitalController.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not save: $e';
          _isSaving = false;
        });
      }
    }
  }

  InputDecoration _decoration(BuildContext context, String label) =>
      InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: AppPalette.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        labelStyle: TextStyle(color: AppPalette.textMuted(context)),
        hintStyle: TextStyle(color: AppPalette.textDisabled(context)),
      );

  String _genderDisplayLabel(AppLocalizations t, String value) {
    switch (value) {
      case 'Female':
        return t.genderFemale;
      case 'Male':
        return t.genderMale;
      default:
        return t.genderOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.editPatientDemographicsTitle,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppPalette.textPrimary(context)),
                  ),
                  const SizedBox(height: 4),
                  Text(widget.anonymousCode,
                      style: TextStyle(
                          fontSize: 12,
                          color: AppAccent.info(context),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppAccent.danger(context).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(_error!,
                          style: TextStyle(
                              color: AppAccent.danger(context), fontSize: 13)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                      controller: _nameController,
                      decoration: _decoration(context, t.fullNameLabel)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _ageController,
                          keyboardType: TextInputType.number,
                          decoration: _decoration(context, t.ageLabel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: _decoration(context, t.genderLabel),
                          items: _genders
                              .map((g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(_genderDisplayLabel(t, g))))
                              .toList(),
                          onChanged: (value) => setState(() => _gender = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _decoration(context, t.weightKgLabel),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _heightController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: _decoration(context, t.heightCmLabel),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickDateOfBirth,
                    child: InputDecorator(
                      decoration: _decoration(context, t.ageLabel),
                      child: Text(
                        _dateOfBirth == null
                            ? t.notSetLabel
                            : '${_calculateAge(_dateOfBirth!)} ${t.yearsSuffix}',
                        style: TextStyle(
                            color: _dateOfBirth == null
                                ? AppPalette.textDisabled(context)
                                : AppPalette.textPrimary(context)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _decoration(context, t.phoneLabel)),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _addressController,
                      decoration: _decoration(context, t.addressLabel)),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _nextOfKinNameController,
                      decoration: _decoration(context, t.nextOfKinNameLabel)),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nextOfKinPhoneController,
                    keyboardType: TextInputType.phone,
                    decoration: _decoration(context, t.nextOfKinPhoneLabel),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                      controller: _hospitalController,
                      decoration:
                          _decoration(context, t.hospitalFacilityLabel)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppPalette.textPrimary(context),
                          foregroundColor: Colors.white),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(t.saveChangesButton,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
