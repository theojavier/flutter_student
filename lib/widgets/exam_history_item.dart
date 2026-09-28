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

  // Shared theme palette (same as HomePage / ProfilePage / LoginPage)
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _successColor = Color(0xFF4ADE80);
  static const Color _errorColor = Color(0xFFF87171);

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_cardColor.withOpacity(0.9), _cardColor.withOpacity(0.55)],
      ),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  Widget _statusChip(String status) {
    final completed = status.toLowerCase() == "completed";
    final color = completed ? _successColor : _errorColor;
    final label =
        status.isEmpty ? "—" : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy • h:mm a');

    final submitted = exam.submittedAt != null
        ? fmt.format(exam.submittedAt!.toDate())
        : "Not submitted";

    // Safe score ratio (score / total) for the progress bar
    final score = num.tryParse(exam.score.toString());
    final total = num.tryParse(exam.total.toString());
    final double? ratio = (score != null && total != null && total > 0)
        ? (score / total).clamp(0.0, 1.0).toDouble()
        : null;

    final Color barColor = ratio == null
        ? _mutedTextColor
        : ratio >= 0.75
            ? _successColor
            : ratio >= 0.5
                ? _accentColor
                : _errorColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: _cardDecoration(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            splashColor: _accentColor.withOpacity(0.15),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: icon chip + subject/date + status
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.assignment_outlined,
                          size: 20,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _textColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule,
                                  size: 13,
                                  color: _mutedTextColor,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    submitted,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
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
                  Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                  const SizedBox(height: 14),

                  // Score row
                  Row(
                    children: [
                      const Text(
                        "Score",
                        style: TextStyle(fontSize: 13, color: _mutedTextColor),
                      ),
                      const Spacer(),
                      Text(
                        "${exam.score}/${exam.total}",
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _textColor,
                        ),
                      ),
                      if (ratio != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          "${(ratio * 100).round()}%",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: barColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (ratio != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: Colors.white.withOpacity(0.08),
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