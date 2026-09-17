import 'package:flutter/material.dart';

import '../network/api_client.dart';

/// Renders one region's anatomy insight returned by /anatomy/ask.
///
/// Suggested questions are interactive: tapping a question opens a small
/// bottom sheet with quick-select chips (Yes / No / Sometimes / Not sure)
/// and a free-text field. Answers are stored locally and emitted through
/// [onAnswersChanged] so the parent can persist them with the triage payload.
class AnatomyInsightCard extends StatefulWidget {
  final String region;
  final Future<AnatomyInsight>? future;
  final Map<String, String>? initialAnswers;
  final ValueChanged<Map<String, String>>? onAnswersChanged;

  const AnatomyInsightCard({
    super.key,
    required this.region,
    required this.future,
    this.initialAnswers,
    this.onAnswersChanged,
  });

  @override
  State<AnatomyInsightCard> createState() => _AnatomyInsightCardState();
}

class _AnatomyInsightCardState extends State<AnatomyInsightCard> {
  late Map<String, String> _answers;

  @override
  void initState() {
    super.initState();
    _answers = Map.from(widget.initialAnswers ?? {});
  }

  void _emitAnswers() {
    widget.onAnswersChanged?.call(Map.unmodifiable(_answers));
  }

  Future<void> _answerQuestion(String question) async {
    final controller = TextEditingController();
    final selected = ValueNotifier<String?>(_answers[question]);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        question,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['Yes', 'No', 'Sometimes', 'Not sure'].map((option) {
                          final isSelected = selected.value == option;
                          return ChoiceChip(
                            label: Text(option, style: TextStyle(fontSize: 13)),
                            selected: isSelected,
                            selectedColor: const Color(0xFF6D28D9),
                            backgroundColor: const Color(0xFFF1F5F9),
                            onSelected: (picked) {
                              setSheetState(() {
                                selected.value = picked ? option : null;
                                if (picked) controller.clear();
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        decoration: InputDecoration(
                          hintText: 'Or type your own answer...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: const Color(0xFFE2E8F0)),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final text = controller.text.trim();
                            final answer = selected.value ?? (text.isNotEmpty ? text : null);
                            if (answer != null) {
                              setState(() => _answers[question] = answer);
                              _emitAnswers();
                            }
                            Navigator.of(sheetContext).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6D28D9),
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            _answers[question] != null ? 'Update answer' : 'Save answer',
                          ),
                        ),
                      ),
                      if (_answers[question] != null)
                        TextButton(
                          onPressed: () {
                            setState(() => _answers.remove(question));
                            _emitAnswers();
                            Navigator.of(sheetContext).pop();
                          },
                          child: const Text('Clear answer', style: TextStyle(color: Color(0xFFDC2626))),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            initiallyExpanded: false,
            leading: const Icon(Icons.medical_information_outlined, color: Color(0xFF1E293B)),
            title: Text(
              'Clinical Insight: ${widget.region}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF0F172A),
              ),
            ),
            subtitle: FutureBuilder<AnatomyInsight>(
              future: widget.future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF475569)),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Retrieving clinical context...',
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
                      'Clinical context unavailable',
                      style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                    ),
                  );
                }
                final insight = snap.data;
                if (insight == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _SourceBadge(insight: insight),
                );
              },
            ),
            children: [
              FutureBuilder<AnatomyInsight>(
                future: widget.future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const _ShimmerLines(lines: 4);
                  }
                  if (snap.hasError || snap.data == null) {
                    return const SizedBox.shrink();
                  }
                  return _InsightBody(
                    insight: snap.data!,
                    answers: _answers,
                    onQuestionTap: _answerQuestion,
                  );
                },
              ),
            ],
          ),
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
    final (label, textColor, bgColor) = insight.llmUsed
        ? (insight.cached
            ? ('Cached Reference', const Color(0xFF0284C7), const Color(0xFFE0F2FE))
            : ('Clinical Assistant (RAG)', const Color(0xFF0F766E), const Color(0xFFCCFBF1)))
        : ('Medical KB Reference', const Color(0xFF475569), const Color(0xFFF1F5F9));
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: textColor.withOpacity(0.3)),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: textColor),
          ),
        ),
        if (insight.sources.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sources: ${insight.sources.map((s) => s.region).take(2).join(", ")}'
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
  final Map<String, String> answers;
  final ValueChanged<String> onQuestionTap;

  const _InsightBody({
    required this.insight,
    required this.answers,
    required this.onQuestionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (insight.summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              insight.summary,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.45),
            ),
          ),
        if (insight.structures.isNotEmpty) ...[
          const _SectionLabel('Anatomical Structures'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: insight.structures
                .take(6)
                .map((s) => Chip(
                      label: Text(s, style: const TextStyle(fontSize: 11, color: Color(0xFF0F172A), fontWeight: FontWeight.w500)),
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
        ],
        if (insight.likelyConditions.isNotEmpty) ...[
          const _SectionLabel('Differential Conditions'),
          const SizedBox(height: 6),
          ...insight.likelyConditions.take(4).map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 6, right: 8),
                        child: Icon(Icons.circle, size: 5, color: Color(0xFF475569)),
                      ),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.35),
                            children: [
                              TextSpan(text: c.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
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
          const SizedBox(height: 12),
        ],
        if (insight.redFlags.isNotEmpty) ...[
          const _SectionLabel('Clinical Red Flags', color: Color(0xFF991B1B)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Text(
              insight.redFlags.join(' • '),
              style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B), fontWeight: FontWeight.w500, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (insight.suggestedQuestions.isNotEmpty) ...[
          const _SectionLabel('Patient Assessment Questions'),
          const SizedBox(height: 6),
          ...insight.suggestedQuestions.take(5).map(
                (q) {
                  final answer = answers[q];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => onQuestionTap(q),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: answer != null
                              ? const Color(0xFFF0F9FF)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: answer != null
                                ? const Color(0xFF0284C7)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              answer != null ? Icons.check_circle : Icons.help_outline,
                              size: 16,
                              color: answer != null ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    q,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: answer != null ? const Color(0xFF0F172A) : const Color(0xFF334155),
                                      fontWeight: answer != null ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                  if (answer != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        'Recorded answer: $answer',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF0284C7), fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          const SizedBox(height: 12),
        ],
        if (insight.disclaimer.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: 8),
                  child: Icon(Icons.info_outline, size: 14, color: Color(0xFF475569)),
                ),
                Expanded(
                  child: Text(
                    insight.disclaimer,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontStyle: FontStyle.italic, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        if (insight.citations.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _SectionLabel('Clinical Sources & Citations', color: Color(0xFF475569)),
          const SizedBox(height: 6),
          ...insight.citations.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.text,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155), height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '— Reference: ${c.region} (${c.system})',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontStyle: FontStyle.italic, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
