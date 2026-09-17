import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/network/api_client.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_header_bar.dart';
import '../../../l10n/app_localizations.dart';
import 'practitioner_scaffold.dart';

import '../../../core/theme/app_page_route.dart';
import 'practitioner_dashboard_screen.dart';

const List<Color> _chartPalette = [
  Color(0xFF0F172A), // Slate Navy
  Color(0xFF0284C7), // Medical Cyan
  Color(0xFF059669), // Emerald Green
  Color(0xFFD97706), // Amber
  Color(0xFFDC2626), // Crimson
  Color(0xFF475569), // Muted Slate
  Color(0xFF2563EB), // Royal Blue
];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, dynamic>? _reports;
  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;
  String _period = 'all';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final reports = await ApiClient.getTriageReports(period: _period);
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setPeriod(String period) {
    if (period == _period) return;
    setState(() => _period = period);
    _loadReports();
  }

  String get _periodLabel {
    switch (_period) {
      case 'week':
        return 'This Week';
      case 'month':
        return 'This Month';
      default:
        return 'All Time';
    }
  }

  Future<void> _exportPdf() async {
    final reports = _reports;
    if (reports == null || _isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bytes = await _buildReportPdf(reports, _periodLabel);
      await Printing.sharePdf(
          bytes: bytes, filename: 'simtack_report_$_period.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not generate PDF: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return PractitionerScaffold(
      currentRoute: '/reports',
      contentBuilder: (context, openDrawer) => Column(
        children: [
          AppHeaderBar(
            title: t.reportsTitle,
            subtitle: t.reportsSubtitle,
            onMenuTap: openDrawer,
            actions: [
              if (_reports != null && (_reports!['total'] as int? ?? 0) > 0)
                AppHeaderIconButton(
                  icon: Icons.download_outlined,
                  tooltip: t.downloadPdfTooltip,
                  onPressed: _isExporting ? null : _exportPdf,
                  loadingChild: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : null,
                ),
              AppHeaderIconButton(
                icon: Icons.refresh,
                tooltip: t.refreshTooltip,
                onPressed: _loadReports,
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0F172A)))
                : _error != null
                    ? _buildError(_error!)
                    : _buildContent(_reports!),
          ),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text(message,
              style: const TextStyle(color: Colors.red, fontSize: 14),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
              onPressed: _loadReports,
              child: Text(AppLocalizations.of(context)!.retryButton)),
        ],
      ),
    );
  }

  Widget _periodSelector() {
    Widget button(String value, String label) {
      final selected = _period == value;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _setPeriod(value),
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFF0F172A)
                  : AppPalette.surface(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? const Color(0xFF0F172A)
                    : AppPalette.border(context),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : AppPalette.textSecondary(context),
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    final t = AppLocalizations.of(context)!;
    return Wrap(
      spacing: 8,
      children: [
        button('week', t.periodThisWeek),
        button('month', t.periodThisMonth),
        button('all', t.periodAllTime),
      ],
    );
  }

  Widget _buildContent(Map<String, dynamic> reports) {
    final t = AppLocalizations.of(context)!;
    final total = reports['total'] as int? ?? 0;
    final highRiskCount = reports['high_risk_count'] as int? ?? 0;
    final mediumRiskCount = reports['medium_risk_count'] as int? ?? 0;
    final lowRiskCount = reports['low_risk_count'] as int? ?? 0;
    final openCount = reports['open_count'] as int? ?? 0;
    final closedCount = reports['closed_count'] as int? ?? 0;
    final avgSeverity = (reports['avg_severity'] as num?)?.toDouble();
    final avgRiskScore = (reports['avg_risk_score'] as num?)?.toDouble();
    final byRegion = (reports['by_region'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    final byPainType = (reports['by_pain_type'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    if (total == 0) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _periodSelector(),
            const SizedBox(height: 80),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.inbox_outlined,
                        size: 32, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 12),
                  Text(t.noSessionsInPeriodMessage,
                      style: TextStyle(color: AppPalette.textMuted(context))),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReports,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _periodSelector(),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _statCard(
                  t.statTotalSessionsLabel,
                  '$total',
                  const Color(0xFF0F172A),
                  Icons.people,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute(builder: (_) => const SessionListScreen()),
                  ),
                ),
                _statCard(
                  t.statHighRiskLabel,
                  '$highRiskCount',
                  const Color(0xFFDC2626),
                  Icons.warning_amber,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute(
                        builder: (_) =>
                            const SessionListScreen(initialRiskLevel: 'HIGH')),
                  ),
                ),
                _statCard(
                  t.statMediumRiskLabel,
                  '$mediumRiskCount',
                  const Color(0xFFD97706),
                  Icons.trending_up,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute(
                        builder: (_) => const SessionListScreen(
                            initialRiskLevel: 'MEDIUM')),
                  ),
                ),
                _statCard(
                  t.statLowRiskLabel,
                  '$lowRiskCount',
                  const Color(0xFF059669),
                  Icons.check_circle,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute(
                        builder: (_) =>
                            const SessionListScreen(initialRiskLevel: 'LOW')),
                  ),
                ),
                _statCard(
                  t.statusOpenLabel,
                  '$openCount',
                  const Color(0xFF0284C7),
                  Icons.folder_open,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute(
                        builder: (_) =>
                            const SessionListScreen(initialStatus: 'open')),
                  ),
                ),
                _statCard(
                  t.statusClosedLabel,
                  '$closedCount',
                  const Color(0xFF059669),
                  Icons.check_circle_outline,
                  onTap: () => Navigator.of(context).push(
                    AppPageRoute(
                        builder: (_) =>
                            const SessionListScreen(initialStatus: 'closed')),
                  ),
                ),
                if (avgSeverity != null)
                  _statCard(
                    t.statAvgSeverityLabel,
                    '${avgSeverity.toStringAsFixed(1)}/10',
                    const Color(0xFFD97706),
                    Icons.speed,
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute(builder: (_) => const SessionListScreen()),
                    ),
                  ),
                if (avgRiskScore != null)
                  _statCard(
                    t.statAvgRiskScoreLabel,
                    avgRiskScore.toStringAsFixed(2),
                    const Color(0xFFDC2626),
                    Icons.warning_amber,
                    onTap: () => Navigator.of(context).push(
                      AppPageRoute(builder: (_) => const SessionListScreen()),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            if (openCount + closedCount > 0) ...[
              _sectionTitle(t.sessionStatusTitle),
              const SizedBox(height: 12),
              _donutWithLegend(
                [
                  {'label': t.statusOpenLabel, 'count': openCount},
                  {'label': t.statusClosedLabel, 'count': closedCount},
                ],
                colors: const [Color(0xFF0284C7), Color(0xFF059669)],
              ),
              const SizedBox(height: 32),
            ],
            if (byRegion.isNotEmpty) ...[
              _sectionTitle(t.mostReportedRegionsTitle),
              const SizedBox(height: 12),
              _donutWithLegend(
                byRegion
                    .map((r) => {
                          'label': r['region'] as String? ?? t.unknownLabel,
                          'count': r['count'] as int
                        })
                    .toList(),
                colors: _chartPalette,
              ),
              const SizedBox(height: 32),
            ],
            if (byPainType.isNotEmpty) ...[
              _sectionTitle(t.painTypeBreakdownTitle),
              const SizedBox(height: 12),
              _donutWithLegend(
                byPainType
                    .map((r) => {
                          'label': r['pain_type'] as String? ?? t.unknownLabel,
                          'count': r['count'] as int
                        })
                    .toList(),
                colors: _chartPalette,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppPalette.textPrimary(context)),
      );

  Widget _statCard(String label, String value, Color color, IconData icon,
      {VoidCallback? onTap}) {
    return SizedBox(
      width: 180,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border(context)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(value,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: color),
                          overflow: TextOverflow.ellipsis),
                      Text(label,
                          style: TextStyle(
                              fontSize: 11,
                              color: AppPalette.textMuted(context),
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Donut chart with a legend list beside/below it. Caps the pie at the
  /// top 6 slices (already sorted by count from the backend) plus an
  /// "Other" slice — a chart with 9+ thin slivers stops being readable,
  /// but the legend still lists every row with its exact count.
  Widget _donutWithLegend(List<Map<String, dynamic>> rows,
      {required List<Color> colors}) {
    final sliceRows = <Map<String, dynamic>>[];
    if (rows.length > 6) {
      sliceRows.addAll(rows.take(6));
      final otherCount =
          rows.skip(6).fold<int>(0, (sum, r) => sum + (r['count'] as int));
      sliceRows.add({
        'label': AppLocalizations.of(context)!.otherLabel,
        'count': otherCount
      });
    } else {
      sliceRows.addAll(rows);
    }
    final total = sliceRows.fold<int>(0, (sum, r) => sum + (r['count'] as int));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chart = SizedBox(
            height: 180,
            width: 180,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 44,
                sections: [
                  for (var i = 0; i < sliceRows.length; i++)
                    PieChartSectionData(
                      value: (sliceRows[i]['count'] as int).toDouble(),
                      color: colors[i % colors.length],
                      radius: 36,
                      showTitle: false,
                    ),
                ],
              ),
            ),
          );
          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < sliceRows.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: colors[i % colors.length],
                              shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sliceRows[i]['label'] as String,
                          style: TextStyle(
                              fontSize: 13,
                              color: AppPalette.textPrimary(context)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${sliceRows[i]['count']}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppPalette.textPrimary(context)),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        total == 0
                            ? ''
                            : '(${(((sliceRows[i]['count'] as int) / total) * 100).round()}%)',
                        style: TextStyle(
                            fontSize: 11, color: AppPalette.textMuted(context)),
                      ),
                    ],
                  ),
                ),
            ],
          );

          if (constraints.maxWidth < 480) {
            return Column(
              children: [
                Center(child: chart),
                const SizedBox(height: 16),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              chart,
              const SizedBox(width: 32),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }
}

Future<Uint8List> _buildReportPdf(
    Map<String, dynamic> reports, String periodLabel) async {
  final doc = pw.Document();
  final total = reports['total'] as int? ?? 0;
  final openCount = reports['open_count'] as int? ?? 0;
  final closedCount = reports['closed_count'] as int? ?? 0;
  final avgSeverity = (reports['avg_severity'] as num?)?.toDouble();
  final avgRiskScore = (reports['avg_risk_score'] as num?)?.toDouble();
  final byRegion = (reports['by_region'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();
  final byPainType = (reports['by_pain_type'] as List<dynamic>? ?? [])
      .cast<Map<String, dynamic>>();
  const navyColor = PdfColor.fromInt(0xFF0F172A);

  pw.Widget statBox(String label, String value) => pw.Container(
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: navyColor)),
            pw.SizedBox(height: 2),
            pw.Text(label,
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
      );

  pw.Widget breakdownTable(
      String title, List<Map<String, dynamic>> rows, String labelKey) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1)
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('Category',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 10))),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text('Count',
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 10))),
              ],
            ),
            for (final row in rows)
              pw.TableRow(
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('${row[labelKey] ?? 'Unknown'}',
                          style: const pw.TextStyle(fontSize: 10))),
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text('${row['count']}',
                          style: const pw.TextStyle(fontSize: 10))),
                ],
              ),
          ],
        ),
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text('Simtack Triage Report',
            style: pw.TextStyle(
                fontSize: 22, fontWeight: pw.FontWeight.bold, color: navyColor)),
        pw.SizedBox(height: 4),
        pw.Text(
            'Period: $periodLabel  •  Generated: ${DateTime.now().toString().split('.').first}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 20),
        pw.Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            statBox('Total Sessions', '$total'),
            statBox('Open', '$openCount'),
            statBox('Closed', '$closedCount'),
            if (avgSeverity != null)
              statBox('Avg. Severity', '${avgSeverity.toStringAsFixed(1)}/10'),
            if (avgRiskScore != null)
              statBox('Avg. Risk Score', avgRiskScore.toStringAsFixed(2)),
          ],
        ),
        pw.SizedBox(height: 24),
        if (byRegion.isNotEmpty) ...[
          breakdownTable('Most Reported Body Regions', byRegion, 'region'),
          pw.SizedBox(height: 20),
        ],
        if (byPainType.isNotEmpty)
          breakdownTable('Pain Type Breakdown', byPainType, 'pain_type'),
      ],
    ),
  );

  return doc.save();
}
