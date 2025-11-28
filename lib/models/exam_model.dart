// lib/models/exam_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ExamModel {
  final String id;
  final String? subject;
  final String? program;
  final String? yearBlock;
  final String? status;
  final String? teacherId;
  final Timestamp? startTime;
  final Timestamp? endTime;
  final Timestamp? createdAt;

  ExamModel({
    required this.id,
    this.subject,
    this.program,
    this.yearBlock,
    this.status,
    this.teacherId,
    this.startTime,
    this.endTime,
    this.createdAt,
  });

  factory ExamModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ExamModel(
      id: doc.id,
      subject: data['subject'],
      program: data['program'],
      yearBlock: data['yearBlock'],
      status: data['status'],
      teacherId: data['teacherId'],
      startTime: data['startTime'],
      endTime: data['endTime'],
      createdAt: data['createdAt'],
    );
  }

  String getFormattedLoginTime() {
    if (startTime == null || endTime == null) return "No time";
    final start = startTime!.toDate();
    final end = endTime!.toDate();
    final day = DateFormat('EEEE, d MMMM yyyy').format(start);
    final startTimeStr = DateFormat('h:mm a').format(start);
    final endTimeStr = DateFormat('h:mm a').format(end);
    return "$day / $startTimeStr - $endTimeStr";
  }

  String getFormattedPostedDate() {
    if (createdAt == null) return "Unknown";
    final date = createdAt!.toDate();
    return DateFormat("MMMM d, yyyy 'at' h:mm a").format(date);
  }
}

