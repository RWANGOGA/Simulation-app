import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:simtack/core/theme/app_tokens.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import '../../../../core/clinical/retired_factors.dart';
import '../../../../core/clinical/risk_engine.dart';
import '../../../../l10n/app_localizations.dart';

class ShapFactor {
  final String label;
  final double contribution;
  final String impact;

  const ShapFactor({
    required this.label,
    required this.contribution,
    required this.impact,
  });

  /// Pre-rename name for [contribution].
  @Deprecated('Use contribution')
  double get shap => contribution;

  bool get raisesRisk => impact == '+';

  /// A negative factor is the score being capped, not a protective finding.
  ///
  /// Every weight in the scoring model is non-negative - severity, region, pain
  /// type, heart rate, connectivity and BMI all only ever add - so nothing a
  /// patient reports can *lower* risk. The one factor that is ever negative is
  /// the arithmetic adjustment that keeps the breakdown summing to the reported
  /// score ("Score capped at 1.00 ..."). Painting that in the same green the
  /// interface uses for reassuring clinical findings told clinicians the opposite
  /// of what it meant: a cap is reached *because* findings stacked up.
  bool get isScoreAdjustment => impact == '-';
  double get magnitude => contribution.abs();
}

class ShapExplanationWidget extends StatelessWidget {
  final String? shapExplanation;
  final bool expandable;
  final bool initiallyExpanded;
  final Color? positiveColor;
  final Color? negativeColor;

  /// Colour of an arithmetic adjustment (the score being capped). Deliberately
  /// neither the red of a raising finding nor the green of a reassuring one: it is
  /// neither, it is the total being brought back into the 0..1 range the score
  /// occupies. Shared with the legend so the swatch always matches the row it names.
  static Color adjustmentColor(BuildContext context) =>
      AppPalette.textSecondary(context);

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

      return decoded
          .map((f) {
            final factor = f is Map<String, dynamic> ? f : <String, dynamic>{};
            final label = (factor['factor'] ?? t.unknownFactorLabel).toString();
            final weight = RiskContribution.valueOf(factor);
            final hasImpactKey = factor.containsKey('impact');
            final impact = hasImpactKey
                ? (factor['impact'] == '-' ? '-' : '+')
                : (weight < 0 ? '-' : '+');
            return ShapFactor(
                label: label, contribution: weight, impact: impact);
          })
          .where((f) => !isRetiredRiskFactor(f.label))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final factors = _parseFactors(context);

    if (factors.isEmpty) return const SizedBox.shrink();

    final maxShap =
        factors.fold<double>(0.0, (m, f) => f.magnitude > m ? f.magnitude : m);
    final posColor = positiveColor ?? AppAccent.danger(context);
    final negColor = negativeColor ?? AppAccent.success(context);

    if (!expandable) {
      return _buildFactorList(context, factors, maxShap, posColor, negColor);
    }

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          Icon(Icons.analytics_outlined,
              size: 20, color: AppAccent.info(context)),
          const SizedBox(width: 12),
          Text(
            t.whyThisScoreTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppPalette.textPrimary(context),
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
          child:
              _buildFactorList(context, factors, maxShap, posColor, negColor),
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
        _buildLegend(context, factors, posColor, negColor),
      ],
    );
  }

  Widget _buildLegend(
    BuildContext context,
    List<ShapFactor> factors,
    Color posColor,
    Color negColor,
  ) {
    final t = AppLocalizations.of(context)!;
    // Only advertise a colour the list actually draws. The legend used to show
    // "Lowers Risk" in green unconditionally, describing a state the scoring
    // model cannot produce - which taught clinicians to read green as meaningful
    // reassurance in a panel that would never honestly display it.
    final items = <Widget>[];
    if (factors.any((f) => f.raisesRisk)) {
      items.add(_legendItem(t.legendRaisesRiskLabel, posColor, context));
    }
    if (factors.any((f) => f.isScoreAdjustment && !f.raisesRisk)) {
      // Slate, matching the row it describes - never the green of a reassuring
      // finding. The sign on the value is what distinguishes it from a small
      // raising factor drawn in the same family of grey.
      items.add(_legendItem(
          t.legendLowersRiskLabel, adjustmentColor(context), context));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.inputFill(context),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 24),
            items[i],
          ],
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color, BuildContext context) {
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
          style:
              TextStyle(fontSize: 12, color: AppPalette.textSecondary(context)),
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
    final barColor = factor.isScoreAdjustment
        ? ShapExplanationWidget.adjustmentColor(context)
        : !raises
            ? negativeColor
            : magnitude >= 0.25
                ? positiveColor
                : magnitude >= 0.10
                    ? AppAccent.warning(context)
                    : AppPalette.textMuted(context);
    final fraction =
        maxShap > 0 ? (magnitude / maxShap).clamp(0.04, 1.0) : 0.04;
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
                  style: TextStyle(
                      fontSize: 13, color: AppPalette.textPrimary(context)),
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
                Container(height: 8, color: AppPalette.subtleFill(context)),
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

      return decoded
          .map((f) {
            final factor = f is Map<String, dynamic> ? f : <String, dynamic>{};
            final label = (factor['factor'] ?? t.unknownFactorLabel).toString();
            final weight = RiskContribution.valueOf(factor);
            final hasImpactKey = factor.containsKey('impact');
            final impact = hasImpactKey
                ? (factor['impact'] == '-' ? '-' : '+')
                : (weight < 0 ? '-' : '+');
            return ShapFactor(
                label: label, contribution: weight, impact: impact);
          })
          .where((f) => !isRetiredRiskFactor(f.label))
          .toList()
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
    final maxShap =
        factors.fold<double>(0.0, (m, f) => f.magnitude > m ? f.magnitude : m);
    final posColor = positiveColor ?? AppAccent.danger(context);
    final negColor = negativeColor ?? AppAccent.success(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined,
                  size: 16, color: AppAccent.info(context)),
              const SizedBox(width: 8),
              Text(
                t.whyThisScoreTitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppPalette.textMuted(context),
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
                style: TextStyle(
                  fontSize: 11,
                  color: AppPalette.textDisabled(context),
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
    final barColor = factor.isScoreAdjustment
        ? ShapExplanationWidget.adjustmentColor(context)
        : !raises
            ? negativeColor
            : magnitude >= 0.25
                ? positiveColor
                : magnitude >= 0.10
                    ? AppAccent.warning(context)
                    : AppPalette.textMuted(context);
    final fraction =
        maxShap > 0 ? (magnitude / maxShap).clamp(0.04, 1.0) : 0.04;
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
                  style: TextStyle(
                      fontSize: 11, color: AppPalette.textSecondary(context)),
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
                Container(height: 5, color: AppPalette.subtleFill(context)),
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
