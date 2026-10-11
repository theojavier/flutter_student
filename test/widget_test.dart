import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_flutter_app/widgets/notification_bubble.dart';

void main() {
  testWidgets('notification bubble shows count and view all action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationBubbleSheet(
            itemCount: 3,
            notifications: const [
              NotificationSummary(
                id: 'exam-1',
                title: 'New exam',
                message: 'Your first exam is ready.',
                isRead: false,
              ),
              NotificationSummary(
                id: 'schedule-1',
                title: 'Schedule update',
                message: 'Room changed for your lab session.',
                isRead: true,
              ),
            ],
            onViewAll: () {},
            onTapItem: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('You have 3 new notifications.'), findsOneWidget);
    expect(find.text('See all notifications'), findsOneWidget);
  });
}
