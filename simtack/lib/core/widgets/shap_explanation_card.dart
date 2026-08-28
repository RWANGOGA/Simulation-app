import 'dart:convert';
import 'package:flutter/material.dart';

/// Renders the backend's risk-score breakdown (the `shap_explanation` JSON
/// on a TriageResult) as a readable "why this score" list. Anatomical
/// connectivity factors from body_graph.py (e.g. "Connected to reported
/// Chest / Heart pain") are visually highlighted so they stand out from
/// ordinary single-region factors — those are the ones worth a second look.
///
/// Shared between the doctor's clinical report and the patient's success
/// screen so both see the exact same reasoning behind a score.
class ShapExplanationCard extends StatelessWidget {
  final String? shapExplanation;
  final String title;

  const ShapExplanationCard({
    super.key,
    required this.shapExplanation,
    this.title = 'WHY THIS SCORE',
  });

  @override
  Widget build(BuildContext context) {
    final raw = shapExplanation;
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    List<dynamic> factors;
    try {
      factors = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (factors.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B), letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          ...factors.map((f) {
            final factor = f as Map<String, dynamic>;
            final label = factor['factor'] as String? ?? '';
            final shap = (factor['shap'] as num?)?.toDouble() ?? 0.0;
            final isConnection = label.startsWith('Connected to reported');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isConnection ? Icons.link : Icons.circle,
                    size: isConnection ? 16 : 6,
                    color: isConnection ? const Color(0xFF6D28D9) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        color: isConnection ? const Color(0xFF6D28D9) : const Color(0xFF334155),
                        fontWeight: isConnection ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    '+${(shap * 100).toInt()}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
