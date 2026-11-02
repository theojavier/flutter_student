import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/SecureStorageHelper.dart';
import '../../widgets/notification_bubble.dart';
import 'notification_item.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  // FOTS editorial palette
  static const Color _bg = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _accent = Color(0xFF087B4F);
  static const Color _accentSoft = Color(0xFFE8F5EB);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _muted2 = Color(0xFF8A8D91);
  static const String _mono = 'monospace';

  static const int _pageSize = 10;

  List<NotificationItem> _notifications = [];
  String? _userId;
  CollectionReference? _notifRef;
  StreamSubscription? _sub;
  bool _loading = true;
  bool _unreadOnly = false;
  int _page = 0;
  Object? _loadError;

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
        .limit(200)
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
                  createdAt: timestamp is Timestamp
                      ? timestamp.toDate()
                      : DateTime.now(),
                  viewed: data['read'] ?? data['viewed'] ?? false,
                ),
              );
            }
            if (mounted) {
              setState(() {
                _notifications = loaded;
                _loadError = null;
                _loading = false;
              });
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _loadError = error;
                _loading = false;
              });
            }
          },
        );
  }

  void _onNotificationClick(NotificationItem item) {
    context.go('/take-exam/${Uri.encodeComponent(item.examId)}');
  }

  Future<void> _markAllRead() async {
    final ref = _notifRef;
    if (ref == null) return;
    final unread = _notifications.where((n) => !n.viewed).toList();
    if (unread.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final n in unread) {
        batch.update(ref.doc(n.examId), {
          'read': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (e) {
      debugPrint('Could not mark notifications as read: $e');
    }
  }

  // ============================================================
  // STYLES
  // ============================================================

  TextStyle _monoStyle(double size, {Color color = _muted2}) => TextStyle(
    fontFamily: _mono,
    fontSize: size,
    color: color,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w500,
  );

  TextStyle _display(double size, {Color color = _ink, double h = 1.0}) =>
      TextStyle(
        fontSize: size,
        height: h,
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: -size * 0.05,
      );

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 24, compact ? 16 : 24, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _pageHead(compact),
                  const SizedBox(height: 20),
                  if (_loading)
                    _skeleton()
                  else if (_userId == null)
                    _card(
                      _stateBox(
                        Icons.person_off_outlined,
                        'Sign in to see your notifications.',
                      ),
                    )
                  else if (_loadError != null)
                    _card(
                      _stateBox(
                        Icons.error_outline,
                        'Could not load notifications. Check your connection and try again.',
                      ),
                    )
                  else
                    _inboxCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PAGE HEAD
  // ============================================================

  Widget _pageHead(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('FOTS / 04', style: _monoStyle(10, color: _accent)),
        const SizedBox(height: 10),
        Text('Notifications.', style: _display(compact ? 32 : 34, h: 1.08)),
        const SizedBox(height: 7),
        const Text(
          'New exams assigned to you',
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  // ============================================================
  // INBOX CARD
  // ============================================================

  Widget _inboxCard() {
    final all = _notifications;
    final unreadCount = all.where((n) => !n.viewed).length;
    final visible = _unreadOnly ? all.where((n) => !n.viewed).toList() : all;

    final pageCount = (visible.length / _pageSize).ceil();
    final page = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1).toInt();
    final items = visible.skip(page * _pageSize).take(_pageSize).toList();

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _inboxHeader(total: all.length, unread: unreadCount),
          if (items.isEmpty)
            _stateBox(
              _unreadOnly ? Icons.done_all : Icons.notifications_off_outlined,
              _unreadOnly
                  ? 'You are all caught up.'
                  : 'No notifications yet. New exams will show up here.',
            )
          else
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: _line),
              NotificationTile(
                subject: items[i].title,
                createdAt: items[i].createdAt,
                isRead: items[i].viewed,
                onTap: () => _onNotificationClick(items[i]),
              ),
            ],
          if (pageCount > 1) _pager(page, pageCount),
        ],
      ),
    );
  }

  Widget _inboxHeader({required int total, required int unread}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 14,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Inbox',
                style: TextStyle(
                  color: _ink,
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$unread unread · $total total',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterButton(
                'All',
                Icons.view_list_outlined,
                !_unreadOnly,
                () => setState(() {
                  _unreadOnly = false;
                  _page = 0;
                }),
              ),
              _filterButton(
                'Unread',
                Icons.mark_email_unread_outlined,
                _unreadOnly,
                () => setState(() {
                  _unreadOnly = true;
                  _page = 0;
                }),
              ),
              OutlinedButton.icon(
                onPressed: unread == 0 ? null : _markAllRead,
                icon: const Icon(Icons.done_all, size: 17),
                label: const Text('Mark all as read'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: _line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterButton(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : _ink,
        backgroundColor: selected ? _accent : Colors.white,
        side: BorderSide(color: selected ? _accent : _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _pager(int page, int pageCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _line)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            color: _ink,
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
          ),
          Text(
            'Page ${page + 1} of $pageCount',
            style: const TextStyle(color: _muted, fontSize: 12.5),
          ),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            color: _ink,
            onPressed: page < pageCount - 1
                ? () => setState(() => _page = page + 1)
                : null,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SHARED PIECES
  // ============================================================

  Widget _card(Widget child) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: _line),
    ),
    child: child,
  );

  Widget _stateBox(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _accent, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton() {
    Widget block(double height, {double radius = 10}) => Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9ECE9),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return Column(
      children: [
        block(70),
        const SizedBox(height: 12),
        block(64),
        const SizedBox(height: 12),
        block(64),
        const SizedBox(height: 12),
        block(64),
      ],
    );
  }
}