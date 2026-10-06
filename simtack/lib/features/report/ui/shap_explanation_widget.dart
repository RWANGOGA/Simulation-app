import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';

class ShapFactor {
  final String label;
  final double shap;
  final String impact;

  const ShapFactor({
    required this.label,
    required this.shap,
    required this.impact,
  });

  bool get raisesRisk => impact == '+';
  double get magnitude => shap.abs();
}

class ShapExplanationWidget extends StatelessWidget {
  final String? shapExplanation;
  final bool expandable;
  final bool initiallyExpanded;
  final Color? positiveColor;
  final Color? negativeColor;

  const ShapExplanationWidget({
    super.key,
    required this.shapExplanation,
    this.expandable = true,
    this.initiallyExpanded = false,
    this.positiveColor,
    this.negativeColor,
  });

  List<ShapFactor> _parseFactors(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (shapExplanation == null || shapExplanation!.isEmpty) return [];

    try {
      final decoded = jsonDecode(shapExplanation!);
      if (decoded is! List || decoded.isEmpty) return [];

      return decoded.map((f) {
        final factor = f is Map<String, dynamic> ? f : <String, dynamic>{};
        final label = (factor['factor'] ?? t.unknownFactorLabel).toString();
        final shap = factor['shap'] is num ? (factor['shap'] as num).toDouble() : 0.0;
        final hasImpactKey = factor.containsKey('impact');
        final impact = hasImpactKey
            ? (factor['impact'] == '-' ? '-' : '+')
            : (shap < 0 ? '-' : '+');
        return ShapFactor(label: label, shap: shap, impact: impact);
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final factors = _parseFactors(context);

    if (factors.isEmpty) return const SizedBox.shrink();

    final maxShap = factors.fold<double>(0.0, (m, f) => f.magnitude > m ? f.magnitude : m);
    final posColor = positiveColor ?? const Color(0xFFDC2626);
    final negColor = negativeColor ?? const Color(0xFF16A34A);

    if (!expandable) {
      return _buildFactorList(context, factors, maxShap, posColor, negColor);
    }

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          const Icon(Icons.analytics_outlined, size: 20, color: Color(0xFF0284C7)),
          const SizedBox(width: 12),
          Text(
            t.whyThisScoreTitle,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: posColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              t.factorCountLabel(factors.length),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: posColor,
              ),
            ),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _buildFactorList(context, factors, maxShap, posColor, negColor),
        ),
      ],
    );
  }

  Widget _buildFactorList(
    BuildContext context,
    List<ShapFactor> factors,
    double maxShap,
    Color posColor,
    Color negColor,
  ) {
    return Column(
      children: [
        ...factors.map((f) => _ShapFactorRow(
              factor: f,
              maxShap: maxShap,
              positiveColor: posColor,
              negativeColor: negColor,
            )),
        const SizedBox(height: 8),
        _buildLegend(context, posColor, negColor),
      ],
    );
  }

  Widget _buildLegend(BuildContext context, Color posColor, Color negColor) {
    final t = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem(t.legendRaisesRiskLabel, posColor),
          const SizedBox(width: 24),
          _legendItem(t.legendLowersRiskLabel, negColor),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
        ),
      ],
    );
  }
}

class _ShapFactorRow extends StatelessWidget {
  final ShapFactor factor;
  final double maxShap;
  final Color positiveColor;
  final Color negativeColor;

  const _ShapFactorRow({
    required this.factor,
    required this.maxShap,
    required this.positiveColor,
    required this.negativeColor,
  });

  @override
  Widget build(BuildContext context) {
    final raises = factor.raisesRisk;
    final magnitude = factor.magnitude;
    final barColor = !raises
        ? negativeColor
        : magnitude >= 0.25
            ? positiveColor
            : magnitude >= 0.10
                ? const Color(0xFFF59E0B)
                : const Color(0xFF64748B);
    final fraction = maxShap > 0 ? (magnitude / maxShap).clamp(0.04, 1.0) : 0.04;
    final valueLabel = '${raises ? '+' : '-'}${(magnitude * 100).toInt()}%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  factor.label,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 8, color: const Color(0xFFF1F5F9)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CompactShapExplanationWidget extends StatelessWidget {
  final String? shapExplanation;
  final int maxFactors;
  final Color? positiveColor;
  final Color? negativeColor;

  const CompactShapExplanationWidget({
    super.key,
    required this.shapExplanation,
    this.maxFactors = 3,
    this.positiveColor,
    this.negativeColor,
  });

  List<ShapFactor> _parseFactors(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (shapExplanation == null || shapExplanation!.isEmpty) return [];

    try {
      final decoded = jsonDecode(shapExplanation!);
      if (decoded is! List || decoded.isEmpty) return [];

      return decoded.map((f) {
        final factor = f is Map<String, dynamic> ? f : <String, dynamic>{};
        final label = (factor['factor'] ?? t.unknownFactorLabel).toString();
        final shap = factor['shap'] is num ? (factor['shap'] as num).toDouble() : 0.0;
        final hasImpactKey = factor.containsKey('impact');
        final impact = hasImpactKey
            ? (factor['impact'] == '-' ? '-' : '+')
            : (shap < 0 ? '-' : '+');
        return ShapFactor(label: label, shap: shap, impact: impact);
      }).toList()
        ..sort((a, b) => b.magnitude.compareTo(a.magnitude));
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final factors = _parseFactors(context);

    if (factors.isEmpty) return const SizedBox.shrink();

    final displayFactors = factors.take(maxFactors).toList();
    final hasMore = factors.length > maxFactors;
    final maxShap = factors.fold<double>(0.0, (m, f) => f.magnitude > m ? f.magnitude : m);
    final posColor = positiveColor ?? const Color(0xFFDC2626);
    final negColor = negativeColor ?? const Color(0xFF16A34A);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics_outlined, size: 16, color: Color(0xFF0284C7)),
              const SizedBox(width: 8),
              Text(
                t.whyThisScoreTitle,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...displayFactors.map((f) => _CompactFactorRow(
                factor: f,
                maxShap: maxShap,
                positiveColor: posColor,
                negativeColor: negColor,
              )),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t.moreFactorsLabel(factors.length - maxFactors),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactFactorRow extends StatelessWidget {
  final ShapFactor factor;
  final double maxShap;
  final Color positiveColor;
  final Color negativeColor;

  const _CompactFactorRow({
    required this.factor,
    required this.maxShap,
    required this.positiveColor,
    required this.negativeColor,
  });

  @override
  Widget build(BuildContext context) {
    final raises = factor.raisesRisk;
    final magnitude = factor.magnitude;
    final barColor = !raises
        ? negativeColor
        : magnitude >= 0.25
            ? positiveColor
            : magnitude >= 0.10
                ? const Color(0xFFF59E0B)
                : const Color(0xFF64748B);
    final fraction = maxShap > 0 ? (magnitude / maxShap).clamp(0.04, 1.0) : 0.04;
    final valueLabel = '${raises ? '+' : '-'}${(magnitude * 100).toInt()}%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  factor.label,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: barColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(height: 5, color: const Color(0xFFF1F5F9)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}