import 'package:cloud_firestore/cloud_firestore.dart';
class NotificationItem {
  final String examId;
  final String title;
  final DateTime createdAt;
  final bool viewed;

  final String? teacherId;
  final int? startMillis;
  final int? endMillis;

  NotificationItem({
    required this.examId,
    required this.title,
    required this.createdAt,
    required this.viewed,
    this.teacherId,
    this.startMillis,
    this.endMillis,
  });

  // Create from Firestore document
  factory NotificationItem.fromMap(Map<String, dynamic> map, String id) {
    return NotificationItem(
      examId: id,
      title: map['subject'] ?? 'New Exam',
      createdAt: (map['createdAt'] as Timestamp).toDate(), // convert Firestore Timestamp to DateTime
      viewed: map['viewed'] ?? false,
    );
  }

  // Convert to map for saving to Firestore
  Map<String, dynamic> toMap() {
    return {
      'subject': title,
      'createdAt': createdAt,
      'viewed': viewed,
    };
  }
}
