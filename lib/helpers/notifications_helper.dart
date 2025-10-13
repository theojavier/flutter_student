import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> ensureUserNotifications({
  required String userId,
  int limit = 5,
}) async {
  final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

  final userSnap = await userRef.get();
  if (!userSnap.exists) return;

  final data = userSnap.data()!;
  final program = data['program'];
  final yearBlock = data['yearBlock'];
  if (program == null || yearBlock == null) return;

  final examsSnap = await FirebaseFirestore.instance
      .collection('exams')
      .where('program', isEqualTo: program)
      .where('yearBlock', isEqualTo: yearBlock)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .get();

  for (var examDoc in examsSnap.docs) {
    final notifRef = userRef.collection('notifications').doc(examDoc.id);
    final notifSnap = await notifRef.get();
    if (!notifSnap.exists) {
      await notifRef.set({
        'viewed': false,
        'title': examDoc['subject'] ?? 'New Exam',
        'message': 'A new exam for ${examDoc['subject'] ?? 'your subject'} has been posted.',
        'createdAt': examDoc['createdAt'],
      });
    }
  }
}
