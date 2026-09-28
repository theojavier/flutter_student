import 'package:flutter/material.dart';

class NotificationSummary {
  final String id;
  final String title;
  final String message;
  final bool isRead;
  final DateTime? createdAt;

  const NotificationSummary({
    required this.id,
    required this.title,
    required this.message,
    required this.isRead,
    this.createdAt,
  });
}

/// Paints the small triangle "pointer" that makes the notification box
/// read as a chat/speech bubble, aimed up toward the bell icon.
class _BubbleTrianglePainter extends CustomPainter {
  final Color color;

  const _BubbleTrianglePainter({
    this.color = const Color(0xFF0F2B45),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(
        BlurStyle.normal,
        4,
      );

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();

    // Soft shadow first, then the bubble-colored triangle on top.
    canvas.drawPath(
      path.shift(const Offset(0, 2)),
      shadowPaint,
    );

    canvas.drawPath(
      path,
      fillPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _BubbleTrianglePainter oldDelegate,
  ) {
    return oldDelegate.color != color;
  }
}

class NotificationBubbleSheet extends StatelessWidget {
  final int itemCount;
  final List<NotificationSummary> notifications;
  final VoidCallback onViewAll;
  final ValueChanged<NotificationSummary> onTapItem;

  /// Distance, in logical pixels, from the RIGHT edge of the bubble box
  /// to the center of the triangle pointer.
  final double pointerOffsetFromRight;

  static const double _boxWidth = 320;
  static const double _pointerWidth = 20;

  const NotificationBubbleSheet({
    super.key,
    required this.itemCount,
    required this.notifications,
    required this.onViewAll,
    required this.onTapItem,
    this.pointerOffsetFromRight = 40,
  });

  @override
  Widget build(BuildContext context) {
    // Show ONLY the first 3 notifications.
    final visibleNotifications = notifications.take(3).toList();

    final titleText = itemCount == 1
        ? 'You have 1 new notification.'
        : 'You have $itemCount new notifications.';

    // Keep the triangle within the box bounds regardless of what
    // the caller passed in.
    final clampedOffset = pointerOffsetFromRight.clamp(
      _pointerWidth / 2 + 8,
      _boxWidth - _pointerWidth / 2 - 8,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: EdgeInsets.only(
            right: clampedOffset - (_pointerWidth / 2),
          ),
          child: const CustomPaint(
            size: Size(
              _pointerWidth,
              10,
            ),
            painter: _BubbleTrianglePainter(),
          ),
        ),

        Material(
          color: Colors.transparent,
          child: Container(
            width: _boxWidth,

            // IMPORTANT:
            // Removed the maxHeight constraint so the box can shrink
            // naturally around the 3 notifications.
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),

            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // =========================================================
                // HEADER
                // =========================================================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    18,
                    18,
                    18,
                    14,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0B2036),
                        Color(0xFF1E5B8C),
                      ],
                    ),
                  ),
                  child: Text(
                    titleText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),

                // =========================================================
                // NOTIFICATIONS
                // =========================================================
                if (visibleNotifications.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No notifications',
                      style: TextStyle(
                        color: Color(0xFF5D6D7A),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    // IMPORTANT:
                    // Makes the ListView use only the space required
                    // by the 1-3 notification items.
                    shrinkWrap: true,

                    // Prevents the ListView from trying to fill
                    // the remaining vertical space.
                    physics:
                        const NeverScrollableScrollPhysics(),

                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                    ),

                    // Already limited to 3 above.
                    itemCount: visibleNotifications.length,

                    separatorBuilder: (_, __) =>
                        const Divider(
                      height: 1,
                    ),

                    itemBuilder: (context, index) {
                      final item =
                          visibleNotifications[index];

                      return ListTile(
                        dense: true,

                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),

                        title: Text(
                          item.title,
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: item.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color:
                                const Color(0xFF102B45),
                            fontSize: 13.5,
                            height: 1.3,
                          ),
                        ),

                        subtitle: Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 4,
                          ),
                          child: Text(
                            item.message,
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style: const TextStyle(
                              color:
                                  Color(0xFF5D6D7A),
                              fontSize: 12,
                            ),
                          ),
                        ),

                        onTap: () =>
                            onTapItem(item),
                      );
                    },
                  ),

                // =========================================================
                // DIVIDER
                // =========================================================
                const Divider(
                  height: 1,
                ),

                // =========================================================
                // SEE ALL NOTIFICATIONS
                // =========================================================
                InkWell(
                  onTap: onViewAll,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'See all notifications',
                          style: TextStyle(
                            color: Color(0xFF5D6D7A),
                            fontWeight:
                                FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Color(0xFF0F2B45),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}