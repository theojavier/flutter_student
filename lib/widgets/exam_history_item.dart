import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/exam_history_model.dart';

class ExamHistoryItem extends StatelessWidget {
  final ExamHistoryModel exam;
  final VoidCallback onTap;

  const ExamHistoryItem({
    super.key,
    required this.exam,
    required this.onTap,
  });

  // Light Secure Exam palette
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _textColor = Color(0xFF202321);
  static const Color _mutedTextColor = Color(0xFF777D79);
  static const Color _accentColor = Color(0xFF087B4F);
  static const Color _successColor = Color(0xFF168653);
  static const Color _errorColor = Color(0xFFCF4545);

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: _cardColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFDFE3DF)),
    );
  }

  Widget _statusChip(String status) {
    final completed = status.toLowerCase() == 'completed';
    final color = completed ? _successColor : _errorColor;
    final label =
        status.isEmpty ? '—' : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.09),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy • h:mm a');
    final submitted = exam.submittedAt != null
        ? fmt.format(exam.submittedAt!.toDate())
        : 'Not submitted';

    final score = num.tryParse(exam.score.toString());
    final total = num.tryParse(exam.total.toString());
    final double? ratio = (score != null && total != null && total > 0)
        ? (score / total).clamp(0.0, 1.0).toDouble()
        : null;

    final Color barColor = ratio == null
        ? _mutedTextColor
        : ratio >= .75
            ? _successColor
            : ratio >= .5
                ? const Color(0xFF3478C8)
                : _errorColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: _cardDecoration(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            splashColor: _accentColor.withOpacity(.08),
            highlightColor: const Color(0xFFF7F9F7),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5EE),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          Icons.assignment_outlined,
                          size: 21,
                          color: _accentColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exam.subject,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.3,
                                fontWeight: FontWeight.w700,
                                color: _textColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 13,
                                  color: _mutedTextColor,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    submitted,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.3,
                                      color: _mutedTextColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusChip(exam.status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFE5E8E5)),
                  const SizedBox(height: 13),
                  Row(
                    children: [
                      const Text(
                        'Score',
                        style: TextStyle(
                          fontSize: 12,
                          color: _mutedTextColor,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${exam.score}/${exam.total}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textColor,
                        ),
                      ),
                      if (ratio != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${(ratio * 100).round()}%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: barColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (ratio != null) ...[
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 5,
                        backgroundColor: const Color(0xFFE8EBE8),
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
