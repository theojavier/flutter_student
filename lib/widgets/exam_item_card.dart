// lib/widgets/exam_item_card.dart
import 'package:flutter/material.dart';
import '../models/exam_model.dart';
import 'package:go_router/go_router.dart';

class ExamItemCard extends StatelessWidget {
  final ExamModel exam;

  const ExamItemCard({super.key, required this.exam});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.tealAccent.withOpacity(0.2), // subtle ripple
        highlightColor: Colors.transparent,
        onTap: () {
          context.go(
            '/take-exam/${exam.id}',
            extra: {
              'examId': exam.id,
              'subject': exam.subject,
              'teacherId': exam.teacherId,
              'startMillis': exam.startTime?.toDate().millisecondsSinceEpoch,
              'endMillis': exam.endTime?.toDate().millisecondsSinceEpoch,
            },
          );
        },
        child: Card(
          color: const Color(0xFF0F2B45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject + Status row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        exam.subject ?? 'Untitled',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE6F0F8)
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Login time
                Text(
                  "LOGIN TIME: ${exam.getFormattedLoginTime()}",
                  style: const TextStyle(
                    color: Colors.tealAccent, // <-- accent color
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),

                // Posted date
                Text(
                  "Posted ${exam.getFormattedPostedDate()}",
                  style: const TextStyle(
                    color: Colors.grey, // softer secondary text
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
