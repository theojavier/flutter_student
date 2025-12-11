import 'package:cloud_firestore/cloud_firestore.dart';

class ExamHistoryModel {
  final String id;
  final String examId;
  final String studentId;
  final String status;
  final String subject;
  final int score;
  final int total;
  final Timestamp? submittedAt;

  ExamHistoryModel({
    required this.id,
    required this.examId,
    required this.studentId,
    required this.status,
    required this.subject,
    required this.score,
    required this.total,
    this.submittedAt,
  });

  factory ExamHistoryModel.fromDoc(DocumentSnapshot doc, String examId) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    final num scoreNum = (data['score'] is num) ? data['score'] as num : (data['score'] ?? 0);
    final num totalNum = (data['total'] is num) ? data['total'] as num : (data['total'] ?? 0);

    return ExamHistoryModel(
      id: examId,
      examId: data['examId']?.toString() ?? examId,
      studentId: data['studentId']?.toString() ?? '',
      status: data['status']?.toString() ?? '',
      subject: data['subject']?.toString() ?? 'Untitled',
      score: scoreNum.toInt(),
      total: totalNum.toInt(),
      submittedAt: data['submittedAt'] is Timestamp ? data['submittedAt'] as Timestamp : null,
    );
  }
}
