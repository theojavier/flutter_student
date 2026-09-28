// lib/widgets/exam_item_card.dart
import 'package:flutter/material.dart';
import '../models/exam_model.dart';
import 'package:go_router/go_router.dart';

class ExamItemCard extends StatelessWidget {
  final ExamModel exam;

  const ExamItemCard({super.key, required this.exam});

  // Shared theme palette (same as ProfilePage / HomePage / ExamHistoryItem)
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
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
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            splashColor: _accentColor.withOpacity(0.15), // subtle ripple
            highlightColor: Colors.transparent,
            onTap: () {
              context.go(
                '/take-exam/${exam.id}',
                extra: {
                  'examId': exam.id,
                  'subject': exam.subject,
                  'teacherId': exam.teacherId,
                  'startMillis':
                      exam.startTime?.toDate().millisecondsSinceEpoch,
                  'endMillis': exam.endTime?.toDate().millisecondsSinceEpoch,
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Leading icon chip
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.edit_note_outlined,
                      size: 22,
                      color: _accentColor,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Subject + login time + posted date
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.subject ?? 'Untitled',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _textColor,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Login time (accent)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.schedule_outlined,
                                size: 14,
                                color: _accentColor.withOpacity(0.9),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "LOGIN TIME: ${exam.getFormattedLoginTime()}",
                                style: const TextStyle(
                                  color: _accentColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Posted date (muted)
                        Row(
                          children: [
                            const Icon(
                              Icons.event_note_outlined,
                              size: 14,
                              color: _mutedTextColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Posted ${exam.getFormattedPostedDate()}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _mutedTextColor,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Tap hint
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: _mutedTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}