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

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy-MM-dd hh:mm a');

    // Format submittedAt nicely (if available)
    final submitted = exam.submittedAt != null
        ? fmt.format(exam.submittedAt!.toDate())
        : "N/A";

    return InkWell(
      onTap: onTap,
      splashColor: Colors.tealAccent.withOpacity(0.2), // subtle ripple
      highlightColor: Colors.transparent,
      child: Card(
        color: const Color(0xFF0F3B61),
        margin: const EdgeInsets.all(8),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side: subject + date + score
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.subject,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE6F0F8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Submitted: $submitted",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Score: ${exam.score}/${exam.total}",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              // Right side: status
              Text(
                exam.status,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
