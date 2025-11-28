import 'package:flutter/material.dart';
import '../pages/notifications/notification_item.dart';
import 'notifications_list.dart';

class NotificationsContainer extends StatelessWidget {
  final List<NotificationItem> notifications;
  final void Function(NotificationItem) onNotificationClick;

  const NotificationsContainer({
    super.key,
    required this.notifications,
    required this.onNotificationClick,
  });

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          'No notifications',
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return SizedBox(
      height: 200, // matches RecyclerView height
      child: NotificationsList(
        notifications: notifications,
        onNotificationClick: onNotificationClick,
      ),
    );
  }
}
