import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// FOTS editorial palette (same as the other student pages)
const Color _nInk = Color(0xFF111217);
const Color _nAccent = Color(0xFF087B4F);
const Color _nLine = Color(0xFFDFE2DF);
const Color _nMuted = Color(0xFF6F7276);
const String _nMono = 'monospace';

class NotificationSummary {
  final String id;
  final String title; // exam subject
  final String message; // fallback text (e.g. a formatted date)
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

String notifTimeAgo(DateTime? t) {
  if (t == null) return '';
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat('MMM d, yyyy').format(t);
}

// ---------------------------------------------------------------------------
// One notification row (used by the bubble AND the full page).
// Material + InkWell (no ListTile, no colored Container above the ink), so
// the splash is visible and Flutter doesn't throw the ink warning.
// ---------------------------------------------------------------------------
class NotificationTile extends StatelessWidget {
  final String subject;
  final DateTime? createdAt;
  final String? fallbackTime;
  final bool isRead;
  final VoidCallback onTap;

  const NotificationTile({
    super.key,
    required this.subject,
    required this.isRead,
    required this.onTap,
    this.createdAt,
    this.fallbackTime,
  });

  @override
  Widget build(BuildContext context) {
    final color = isRead ? _nMuted : _nAccent;
    final time = createdAt != null ? notifTimeAgo(createdAt) : fallbackTime;

    return Material(
      color: isRead ? Colors.transparent : _nAccent.withValues(alpha: 0.05),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.assignment_outlined, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'New exam',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _nInk,
                              fontSize: 13.5,
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: _nAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _nInk,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    if (time != null && time.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        time,
                        style: const TextStyle(
                          fontFamily: _nMono,
                          fontSize: 10,
                          color: _nMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pointer triangle: white fill, outlined only on the two slanted edges so it
// blends into the card's border.
// ---------------------------------------------------------------------------
class _BubbleTrianglePainter extends CustomPainter {
  const _BubbleTrianglePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height);

    canvas.drawPath(
      Path.from(path)..close(),
      Paint()..color = Colors.white,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _nLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BubbleTrianglePainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// The bubble
// ---------------------------------------------------------------------------
class NotificationBubbleSheet extends StatelessWidget {
  /// Kept for compatibility with the caller; the unread count shown in the
  /// header is computed from [notifications].
  final int itemCount;
  final List<NotificationSummary> notifications;
  final VoidCallback onViewAll;
  final ValueChanged<NotificationSummary> onTapItem;

  /// Distance from the RIGHT edge of the bubble box to the center of the
  /// triangle pointer.
  final double pointerOffsetFromRight;

  static const double _pointerWidth = 20;
  static const int _maxVisible = 3;

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
    final screenW = MediaQuery.sizeOf(context).width;
    // The Dialog leaves ~110px of horizontal inset (40 left + 70 right).
    final boxWidth = math.max(240.0, math.min(360.0, screenW - 110));
    final unread = notifications.where((n) => !n.isRead).length;
    final visible = notifications.take(_maxVisible).toList();

    final pointerRight = (pointerOffsetFromRight - _pointerWidth / 2)
        .clamp(12.0, boxWidth - _pointerWidth - 12)
        .toDouble();

    final box = Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _nLine),
      ),
      child: SizedBox(
        width: boxWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // HEADER
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _nLine)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      color: _nInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  if (unread > 0) _pill('$unread new'),
                ],
              ),
            ),

            // LIST
            if (visible.isEmpty)
              _message(Icons.notifications_off_outlined, 'No notifications yet')
            else
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: _nLine),
                NotificationTile(
                  subject: visible[i].title,
                  createdAt: visible[i].createdAt,
                  fallbackTime: visible[i].message,
                  isRead: visible[i].isRead,
                  onTap: () => onTapItem(visible[i]),
                ),
              ],

            // FOOTER
            const Divider(height: 1, color: _nLine),
            InkWell(
              onTap: onViewAll,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'View all notifications',
                      style: TextStyle(
                        color: _nAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, size: 16, color: _nAccent),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // verticalDirection.up: the first child sits at the bottom and is painted
    // first, so the pointer (second child) appears above the box and is drawn
    // on top of it. It is nudged down 1px to cover the box's top border.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      verticalDirection: VerticalDirection.up,
      children: [
        box,
        Padding(
          padding: EdgeInsets.only(right: pointerRight),
          child: Transform.translate(
            offset: const Offset(0, 1),
            child: const CustomPaint(
              size: Size(_pointerWidth, 10),
              painter: _BubbleTrianglePainter(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: _nAccent.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: _nAccent.withValues(alpha: 0.35)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: _nAccent,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _message(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _nMuted, size: 28),
        const SizedBox(height: 8),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _nMuted, fontSize: 13),
        ),
      ],
    ),
  );
}