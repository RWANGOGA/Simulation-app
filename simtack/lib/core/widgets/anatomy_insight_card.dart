import 'package:flutter/material.dart';

import '../network/api_client.dart';

/// Renders one region’s anatomy insight returned by /anatomy/ask.
///
/// Three visual states:
///   - loading: a small shimmer with a "Loading..." label
///   - error:   a faint hint that AI insights are unavailable; never blocks
///   - ready:   the full card with summary, likely conditions, red flags,
///              suggested questions, and a small "AI / KB / Cached" badge
class AnatomyInsightCard extends StatelessWidget {
  final String region;
  final Future<AnatomyInsight>? future;

  const AnatomyInsightCard({
    super.key,
    required this.region,
    required this.future,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F3FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.18)),
      ),
      child: Theme(
        // Strip the default ExpansionTile divider lines for a tighter look.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: true,
          leading: const Icon(Icons.psychology_outlined, color: Color(0xFF6D28D9)),
          title: Text(
            'AI insight: $region',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          subtitle: FutureBuilder<AnatomyInsight>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6D28D9)),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Loading...',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                );
              }
              if (snap.hasError) {
                return const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'AI insights unavailable',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                  ),
                );
              }
              final insight = snap.data;
              if (insight == null) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _SourceBadge(insight: insight),
              );
            },
          ),
          children: [
            FutureBuilder<AnatomyInsight>(
              future: future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _ShimmerLines(lines: 4);
                }
                if (snap.hasError || snap.data == null) {
                  return const SizedBox.shrink();
                }
                return _InsightBody(insight: snap.data!);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final AnatomyInsight insight;
  const _SourceBadge({required this.insight});

  @override
  Widget build(BuildContext context) {
    final (label, color) = insight.llmUsed
        ? (insight.cached ? ('Cached', const Color(0xFF0EA5E9)) : ('AI', const Color(0xFF16A34A)))
        : ('KB', const Color(0xFF64748B));
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
          ),
        ),
        if (insight.sources.isNotEmpty) ...[
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'based on: ${insight.sources.map((s) => s.region).take(2).join(", ")}'
              '${insight.sources.length > 2 ? "..." : ""}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _InsightBody extends StatelessWidget {
  final AnatomyInsight insight;
  const _InsightBody({required this.insight});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insight.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              insight.summary,
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
            ),
          ),
        if (insight.structures.isNotEmpty) ...[
          const _SectionLabel('Structures involved'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: insight.structures
                .take(6)
                .map((s) => Chip(
                      label: Text(s, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: const Color(0xFF6D28D9).withOpacity(0.2)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 10),
        ],
        if (insight.likelyConditions.isNotEmpty) ...[
          const _SectionLabel('Likely conditions'),
          const SizedBox(height: 4),
          ...insight.likelyConditions.take(4).map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 6),
                        child: Icon(Icons.circle, size: 5, color: Color(0xFF6D28D9)),
                      ),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.3),
                            children: [
                              TextSpan(text: c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              if (c.rationale.isNotEmpty)
                                TextSpan(text: ' — ${c.rationale}'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 10),
        ],
        if (insight.redFlags.isNotEmpty) ...[
          const _SectionLabel('Red flags', color: Color(0xFFDC2626)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Text(
              insight.redFlags.join(' • '),
              style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), height: 1.4),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (insight.suggestedQuestions.isNotEmpty) ...[
          const _SectionLabel('Suggested questions'),
          const SizedBox(height: 4),
          ...insight.suggestedQuestions.take(5).map(
                (q) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1, right: 6),
                        child: Icon(Icons.help_outline, size: 13, color: Color(0xFF6D28D9)),
                      ),
                      Expanded(
                        child: Text(q, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 10),
        ],
        if (insight.disclaimer.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: 6),
                  child: Icon(Icons.info_outline, size: 13, color: Color(0xFF64748B)),
                ),
                Expanded(
                  child: Text(
                    insight.disclaimer,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel(this.text, {this.color = const Color(0xFF6D28D9)});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
    );
  }
}

class _ShimmerLines extends StatelessWidget {
  final int lines;
  const _ShimmerLines({required this.lines});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        lines,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            height: 10,
            width: i == lines - 1 ? 180 : double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF6D28D9).withOpacity(0.10),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}
