import 'package:flutter/material.dart';
import '../pages/notifications/notification_item.dart';

typedef OnNotificationClick = void Function(NotificationItem item);

class NotificationsList extends StatelessWidget {
  final List<NotificationItem> notifications;
  final OnNotificationClick onNotificationClick;

  const NotificationsList({
    super.key,
    required this.notifications,
    required this.onNotificationClick,
  });

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return const Center(child: Text('No notifications'));
    }

    return ListView.separated(
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = notifications[index];
        return ListTile(
          title: Text(
            item.title,
            style: TextStyle(
              fontWeight: item.viewed ? FontWeight.normal : FontWeight.bold,
            ),
          ),
          subtitle: Text(
            // Format createdAt as "dd/MM/yyyy HH:mm"
            "${item.createdAt.day.toString().padLeft(2,'0')}/"
            "${item.createdAt.month.toString().padLeft(2,'0')}/"
            "${item.createdAt.year} "
            "${item.createdAt.hour.toString().padLeft(2,'0')}:"
            "${item.createdAt.minute.toString().padLeft(2,'0')}",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          onTap: () => onNotificationClick(item),
        );
      },
    );
  }
}
