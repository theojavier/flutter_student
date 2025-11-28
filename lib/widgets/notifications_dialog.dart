import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsDialog extends StatefulWidget {
  const NotificationsDialog({super.key});

  @override
  State<NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<NotificationsDialog> {
  String? userId;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userId = prefs.getString('userId');
    });
  }

  Future<void> _markAllRead(QuerySnapshot snapshot) async {
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final ref = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(20);

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Notifications'),
          // A simple "mark all read" button (optional)
          StreamBuilder<QuerySnapshot>(
            stream: ref.snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => _markAllRead(snap.data!),
                child: const Text('Mark all as read'),
              );
            },
          )
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 300,
        child: StreamBuilder<QuerySnapshot>(
          stream: ref.snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(child: Text('No notifications'));
            }
            return ListView.separated(
              itemCount: docs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final d = docs[index].data() as Map<String, dynamic>;
                final title = d['title'] ?? 'Notification';
                final message = d['message'] ?? '';
                final isRead = d['isRead'] == true;
                return ListTile(
                  title: Text(title,
                      style: TextStyle(
                          fontWeight:
                              isRead ? FontWeight.normal : FontWeight.bold)),
                  subtitle: Text(message),
                  onTap: () async {
                    // mark read when tapped
                    await docs[index].reference.update({'isRead': true});
                  },
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'))
      ],
    );
  }
}

