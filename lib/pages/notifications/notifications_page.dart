import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../helpers/SecureStorageHelper.dart';
import 'notification_item.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // Shared theme palette (same as HomePage / ProfilePage / ExamHistoryPage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);

  List<NotificationItem> _notifications = [];
  String? _userId;
  CollectionReference? _notifRef;
  StreamSubscription? _sub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserIdAndNotifications();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadUserIdAndNotifications() async {
    final userId = await SecureStorageHelper.read('userId');
    if (!mounted) return;

    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _userId = userId);

    _notifRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications');

    _sub = _notifRef!
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snap) {
        final loaded = <NotificationItem>[];
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final timestamp = data['createdAt'];
          loaded.add(
            NotificationItem(
              examId: doc.id,
              title: data['subject'] ?? 'New Exam',
              createdAt:
                  timestamp is Timestamp ? timestamp.toDate() : DateTime.now(),
              viewed: data['viewed'] ?? false,
            ),
          );
        }
        if (mounted) {
          setState(() {
            _notifications = loaded;
            _loading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  void _onNotificationClick(NotificationItem item) {
    if (_userId != null && _notifRef != null) {
      _notifRef!.doc(item.examId).update({'viewed': true});
    }
    context.go('/take-exam/${item.examId}');
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final unreadCount = _notifications.where((item) => !item.viewed).length;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: _loading
            ? _buildSkeletonUI()
            // Hides scrollbars on this page (scrolling still works)
            : ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false, overscroll: false),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTitleBar(unreadCount),
                            const SizedBox(height: 22),
                            _sectionHeader(
                              Icons.inbox_outlined,
                              "Recent Notifications",
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_notifications.isEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverToBoxAdapter(
                          child: _emptyCard(
                            Icons.notifications_none_outlined,
                            "No notifications",
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _notificationCard(_notifications[index]),
                            childCount: _notifications.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  // ---------- UI helpers ----------

  BoxDecoration _cardDecoration({bool highlight = false}) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_cardColor.withOpacity(0.9), _cardColor.withOpacity(0.55)],
      ),
      border: Border.all(
        color: highlight
            ? _accentColor.withOpacity(0.35)
            : Colors.white.withOpacity(0.06),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  // Icon chip: gradient ring + soft glow when active, flat muted ring when not.
  // Fill is solid so the glow stays outside the chip.
  Widget _glowChip(
    IconData icon, {
    double iconSize = 18,
    double padding = 8,
    double ring = 2,
    double radius = 12,
    bool active = true,
  }) {
    return Container(
      padding: EdgeInsets.all(ring),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [_accentColor.withOpacity(0.9), _accentColor.withOpacity(0.25)]
              : [Colors.white.withOpacity(0.18), Colors.white.withOpacity(0.05)],
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: _accentColor.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - ring),
        child: Container(
          color: _cardColor,
          padding: EdgeInsets.all(padding),
          child: Icon(
            icon,
            size: iconSize,
            color: active ? Colors.white : _mutedTextColor,
          ),
        ),
      ),
    );
  }

  // Compact floating bar (same style as ProfilePage title bar)
  Widget _buildTitleBar(int unreadCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _glowChip(
            Icons.notifications_active_outlined,
            iconSize: 22,
            padding: 10,
            ring: 3,
            radius: 15,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Notifications",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "ALL NOTIFICATIONS",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (unreadCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _accentColor.withOpacity(0.4)),
              ),
              child: Text(
                "$unreadCount NEW",
                style: const TextStyle(
                  color: _accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Icon chip + title + divider line
  Widget _sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: _accentColor),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(NotificationItem item) {
    final unread = !item.viewed;
    final dateText = DateFormat('MMM d, yyyy • h:mm a').format(item.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: _cardDecoration(highlight: unread),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onNotificationClick(item),
            borderRadius: BorderRadius.circular(18),
            splashColor: _accentColor.withOpacity(0.15),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _glowChip(
                    Icons.notifications_active_outlined,
                    active: unread,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                unread ? FontWeight.bold : FontWeight.w500,
                            color: unread
                                ? _textColor
                                : _textColor.withOpacity(0.75),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 13,
                              color: _mutedTextColor,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                dateText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _mutedTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  unread
                      // Glowing unread dot
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _accentColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _accentColor.withOpacity(0.6),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        )
                      : const Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: _mutedTextColor,
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyCard(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _accentColor, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _mutedTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonUI() {
    Widget block(double height, {double radius = 18}) => Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          block(76),
          const SizedBox(height: 22),
          block(22, radius: 10),
          const SizedBox(height: 12),
          block(76),
          const SizedBox(height: 12),
          block(76),
          const SizedBox(height: 12),
          block(76),
        ],
      ),
    );
  }
}