import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_item.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/notifications_container.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationItem> _notifications = [];
  String? _userId;
  late final CollectionReference _notifRef;

  @override
  void initState() {
    super.initState();
    _loadUserIdAndNotifications();
  }

  Future<void> _loadUserIdAndNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) return;

    setState(() => _userId = userId);

    _notifRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications');

    _notifRef.snapshots().listen((snap) {
  final List<NotificationItem> loaded = [];
  for (var doc in snap.docs) {
    final data = doc.data() as Map<String, dynamic>;
    loaded.add(
      NotificationItem(
        examId: doc.id,
        title: data['subject'] ?? 'New Exam', //  use 'subject'
        createdAt: (data['createdAt'] as Timestamp).toDate(), //  use createdAt
        viewed: data['viewed'] ?? false,
      ),
    );
  }
  setState(() => _notifications = loaded);
});
  }

  void _onNotificationClick(NotificationItem item) {
  // Mark as viewed
  if (_userId != null) {
    _notifRef.doc(item.examId).update({'viewed': true});
  }

  // Navigate to /take-exam
  context.go('/take-exam/${item.examId}');
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: NotificationsContainer(
          notifications: _notifications,
          onNotificationClick: _onNotificationClick,
        ),
      ),
    );
  }
}
