import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'SecureStorageHelper.dart';

List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
watchApprovedExamNotifications({
  required String userId,
  required Map<String, dynamic> userData,
  required void Function(Object error) onError,
}) {
  final yearBlock = userData['yearBlock']?.toString().trim() ?? '';
  if (yearBlock.isEmpty) return [];

  final queries = <Query<Map<String, dynamic>>>[];
  final programs = <String>{
    for (final value in [userData['program'], userData['programCode']])
      if (value != null && value.toString().trim().isNotEmpty)
        value.toString().trim(),
  };

  for (final program in programs) {
    queries.add(
      FirebaseFirestore.instance
          .collection('exams')
          .where('approvalStatus', isEqualTo: 'approved')
          .where('program', isEqualTo: program)
          .where('yearBlock', isEqualTo: yearBlock),
    );
  }

  final classIds = <String>{
    if (userData['classIds'] is List)
      ...(userData['classIds'] as List)
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty),
    if (userData['classId'] != null &&
        userData['classId'].toString().trim().isNotEmpty)
      userData['classId'].toString().trim(),
  };

  for (final classId in classIds) {
    queries.add(
      FirebaseFirestore.instance
          .collection('exams')
          .where('approvalStatus', isEqualTo: 'approved')
          .where('classId', isEqualTo: classId)
          .where('yearBlock', isEqualTo: yearBlock),
    );
  }

  final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
  return queries
      .map(
        (query) => query.snapshots().listen((snapshot) {
          for (final exam in snapshot.docs) {
            unawaited(_createNotificationIfMissing(userRef, exam));
          }
        }, onError: (Object error) => onError(error)),
      )
      .toList();
}

Future<void> _createNotificationIfMissing(
  DocumentReference<Map<String, dynamic>> userRef,
  QueryDocumentSnapshot<Map<String, dynamic>> exam,
) async {
  try {
    final notificationRef = userRef.collection('notifications').doc(exam.id);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final notification = await transaction.get(notificationRef);
      if (notification.exists) return;

      final data = exam.data();
      transaction.set(notificationRef, {
        'read': false,
        'subject': data['subject'] ?? 'New Exam',
        'message':
            'A new exam for ${data['subject'] ?? 'your subject'} has been posted.',
        'createdAt': data['createdAt'] is Timestamp
            ? data['createdAt']
            : Timestamp.now(),
      });
    });
  } catch (error, stackTrace) {
    debugPrint('Could not create notification for exam ${exam.id}: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

Future<void> markExamNotificationViewed(String examId) async {
  if (examId.isEmpty) return;

  try {
    final userId = await SecureStorageHelper.read('userId');
    if (userId == null || userId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(examId)
        .update({'read': true, 'readAt': FieldValue.serverTimestamp()});
  } on FirebaseException catch (error) {
    if (error.code != 'not-found') {
      debugPrint('Could not mark notification $examId as viewed: $error');
    }
  } catch (error) {
    debugPrint('Could not mark notification $examId as viewed: $error');
  }
}
