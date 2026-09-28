// responsive_scaffold.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'nav_header.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../helpers/notifications_helper.dart';
import '../pages/notifications/notification_item.dart';
import 'dart:async';
import '../../helpers/SecureStorageHelper.dart';
import '../../helpers/ExamLockState.dart';
import 'notification_bubble.dart';
import 'profile_menu.dart';
//  Platform + Web detection
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

class ResponsiveScaffold extends StatefulWidget {
  final int selectedIndex;
  final Widget child;
  final String? userId;

  const ResponsiveScaffold({
    super.key,
    required this.selectedIndex,
    required this.child,
    this.userId,
  });

  @override
  State<ResponsiveScaffold> createState() => ResponsiveScaffoldState();
}

class ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  // Shared theme palette (same as Home / Profile / History / Notifications)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);

  String? profileImageUrl;
  String headerName = "Loading...";
  String headerSection = "";
  String? _studentId;
  String? _userId;
  Map<String, dynamic>? _cachedProfile;
  bool _isDrawerOpen = false;
  // Key on the bell button so we can measure where it actually sits
  // on screen and aim the notification bubble's triangle pointer at it.
  final GlobalKey _notificationIconKey = GlobalKey();

  // late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 50));
    });
    _loadUserProfile();
  }

  StreamSubscription<DocumentSnapshot>? _profileSubscription;

  Future<void> _loadUserProfile() async {
    final userId = widget.userId ?? await _getUserIdFromPrefs();

    if (userId == null) {
      if (_cachedProfile == null && mounted) {
        setState(() {
          headerName = "No user found";
          headerSection = "";
          profileImageUrl = null;
        });
      }
      return;
    }

    //  silently assign without setState (prevents flicker on nav)
    _userId = userId;

    // fallback display ID until/unless the profile doc has its own
    _studentId = await SecureStorageHelper.read('studentId');

    //  show cache immediately, but only once
    if (_cachedProfile != null) {
      _updateProfileUI(_cachedProfile!);
    }
    _userId = userId;

    // cancel old subscription before listening
    await _profileSubscription?.cancel();

    _profileSubscription = FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .snapshots()
        .listen((doc) {
          if (!doc.exists) {
            if (_cachedProfile == null && mounted) {
              setState(() {
                headerName = "Profile not found";
                headerSection = "";
                profileImageUrl = null;
              });
            }
            return;
          }

          final data = doc.data()!;
          _updateProfileUI(data);
        });
  }

  void refreshUserProfile() {
    _loadUserProfile();
  }

  Future<String?> _getUserIdFromPrefs() async {
    return await SecureStorageHelper.read('userId');
  }

  void _refreshProfile() async {
    if (_userId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .get();
    if (doc.exists) {
      _updateProfileUI(doc.data()!);
    }
  }

  void _updateProfileUI(Map<String, dynamic> data) {
    if (!mounted) return;

    var url = (data['profileImage'] as String?) ?? '';
    if (url.isNotEmpty &&
        url.contains('imgur.com') &&
        !url.contains('i.imgur.com')) {
      url = '${url.replaceAll('imgur.com', 'i.imgur.com')}.jpg';
    }

    final newName = data['name'] ?? 'No Name';
    final newSection =
        '${data['program'] ?? ''} ${data['yearBlock'] ?? ''} (${data['semester'] ?? ''})'
            .trim();
    final newImageUrl = url.isNotEmpty ? url : null;
    // Prefer an explicit studentId field on the profile doc; fall back to
    // whatever was cached from secure storage at load time.
    final newStudentId = (data['studentId'] as String?) ?? _studentId;

    //  only update UI if something actually changed
    if (newName != headerName ||
        newSection != headerSection ||
        newImageUrl != profileImageUrl ||
        newStudentId != _studentId) {
      setState(() {
        headerName = newName;
        headerSection = newSection;
        profileImageUrl = newImageUrl;
        _studentId = newStudentId;
        _cachedProfile = Map<String, dynamic>.from(data);
      });
    } else {
      // still update cache silently, without rebuild
      _cachedProfile = Map<String, dynamic>.from(data);
    }
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  Future<void> _onSelectPage(int index) async {
    if (!_isDesktop(context)) {
      Navigator.of(context).pop();
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
    }

    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/exam-list');
        break;
      case 2:
        context.go('/schedule');
        break;
    }
  }

  //  Centralized desktop detection
  bool _isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (kIsWeb) return width >= 900;

    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  /// Measures where the bell icon currently sits on screen and returns how
  /// far its center is from the right edge of the notification bubble box
  /// (which itself sits 70px in from the screen's right edge — see the
  /// Dialog's insetPadding below). Falls back to a sane default if the
  /// icon hasn't been laid out yet for some reason.
  double _computeNotificationPointerOffset() {
    const dialogRightInset = 70.0;
    const fallback = 40.0;

    final renderObj = _notificationIconKey.currentContext?.findRenderObject();
    if (renderObj is RenderBox && renderObj.hasSize) {
      final topLeft = renderObj.localToGlobal(Offset.zero);
      final iconCenterX = topLeft.dx + renderObj.size.width / 2;
      final screenWidth = MediaQuery.of(context).size.width;
      final offsetFromRight = (screenWidth - iconCenterX) - dialogRightInset;
      return offsetFromRight.clamp(24.0, 320.0);
    }
    return fallback;
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      _cachedProfile = null;
      profileImageUrl = null;
      headerName = "Logged out";
      await Future.delayed(const Duration(milliseconds: 50));

      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    // Drives whether the drawer/burger menu is allowed to open. This comes
    // straight from ExamHtmlPage's own lifecycle (set true in its
    // initState(), false in its dispose()) instead of being guessed from
    // the current route's URL — a route rename or an alternate path into
    // the exam view (e.g. '/take-exam/:id') can no longer silently reopen
    // the drawer during an exam.
    return ValueListenableBuilder<bool>(
      valueListenable: ExamLockState.isInExam,
      builder: (context, isExamHtmlPage, _) {
        return Scaffold(
          backgroundColor: _bgColor,
          appBar: _buildAppBar(context, isDesktop, isExamHtmlPage),
          drawer: !isDesktop ? _buildDrawer(context) : null,
          // Keep the drawer available even while an exam/webview is on screen,
          // but still allow the app shell to stay draggable and clickable.
          drawerEnableOpenDragGesture: true,
          onDrawerChanged: (isOpen) {
            if (_isDrawerOpen == isOpen || !mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _isDrawerOpen = isOpen;
              });
            });
          },
          body: Row(
            children: [
              // Desktop sidebar (floating rounded panel)
              if (isDesktop)
                Container(
                  width: 276,
                  child: _sidebarSurface(
                    radius: BorderRadius.zero,
                    floating: false,
                    child: _sidebarContent(desktop: true),
                  ),
                ),

              // Main content
              Expanded(
                child: Stack(
                  children: [
                    IgnorePointer(
                      ignoring: _isDrawerOpen && !isDesktop,
                      child: widget.child,
                    ),

                    if (_isDrawerOpen && !isDesktop)
                      PointerInterceptor(
                        child: GestureDetector(
                          onTap: () {
                            final scaffold = Scaffold.maybeOf(context);
                            if (scaffold != null) {
                              scaffold.closeDrawer();
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- APP BAR ----------

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    bool isDesktop,
    bool isExamHtmlPage,
  ) {
    Widget? leading;
    if (!isDesktop) {
      leading = Builder(
        builder: (ctx) => Center(
          child: _barButton(
            icon: Icons.menu_rounded,
            onTap: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
      );
    }

    return AppBar(
      backgroundColor: _headerColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: false,
      // Gradient strip + thin bottom divider (same look as the page headers)
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_headerColorLight, _headerColor],
          ),
          border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
      ),
      title: GestureDetector(
        onTap: () => context.go('/home'),
        child: Image.asset('assets/image/Fots.png', height: 80, width: 120),
      ),
      leading: leading,
      actions: _buildActions(context),
    );
  }

  // Rounded "glass" icon button used in the app bar (menu, bell)
  Widget _barButton({
    Key? buttonKey,
    required IconData icon,
    VoidCallback? onTap,
    bool highlight = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: _accentColor.withOpacity(0.2),
        highlightColor: Colors.transparent,
        child: Container(
          key: buttonKey,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? _accentColor.withOpacity(0.5)
                  : Colors.white.withOpacity(0.10),
            ),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // Glowing unread badge on the bell
  Widget _unreadBadge(int unread) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _accentColor,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _headerColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.6),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Text(
        unread > 9 ? '9+' : unread.toString(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      if (_userId == null)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _barButton(
              icon: Icons.notifications_none_outlined,
              onTap: () {},
            ),
          ),
        )
      else
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .collection('notifications')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            final unread = snap.hasData
                ? snap.data!.docs.where((d) => !(d['viewed'] ?? false)).length
                : 0;

            // Optional: ensure notifications exist
            ensureUserNotifications(userId: _userId!);

            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _barButton(
                      buttonKey: _notificationIconKey,
                      icon: unread > 0
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none_outlined,
                      highlight: unread > 0,
                      onTap: () {
                        if (_userId != null) {
                          final notifications = snap.hasData
                              ? snap.data!.docs.map((doc) {
                                  final data =
                                      doc.data() as Map<String, dynamic>;

                                  return NotificationItem(
                                    examId: doc.id,
                                    title: data['subject'] ?? 'New Exam',
                                    createdAt: (data['createdAt'] as Timestamp)
                                        .toDate(),
                                    viewed: data['viewed'] ?? false,
                                  );
                                }).toList()
                              : <NotificationItem>[];

                          // Measure the bell position before opening the dialog.
                          final pointerOffset =
                              _computeNotificationPointerOffset();

                          showDialog(
                            context: context,
                            barrierColor: Colors.black12,
                            builder: (ctx) => Dialog(
                              insetPadding: const EdgeInsets.only(
                                top: 60,
                                right: 70,
                              ),
                              alignment: Alignment.topRight,
                              backgroundColor: Colors.transparent,
                              child: PointerInterceptor(
                                child: NotificationBubbleSheet(
                                  itemCount: notifications.length,
                                  pointerOffsetFromRight: pointerOffset,
                                  notifications: notifications
                                      .map(
                                        (item) => NotificationSummary(
                                          id: item.examId,
                                          title: item.title,
                                          message:
                                              '${item.createdAt.day.toString().padLeft(2, '0')}/${item.createdAt.month.toString().padLeft(2, '0')}/${item.createdAt.year}',
                                          isRead: item.viewed,
                                        ),
                                      )
                                      .toList(),
                                  onViewAll: () {
                                    Navigator.of(ctx).pop();
                                    context.go('/all-notifications');
                                  },
                                  onTapItem: (item) async {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(_userId)
                                        .collection('notifications')
                                        .doc(item.id)
                                        .update({'viewed': true});

                                    Navigator.of(ctx).pop();
                                    context.go('/take-exam/${item.id}');
                                  },
                                ),
                              ),
                            ),
                          );
                        }
                      },
                    ),
                    if (unread > 0)
                      Positioned(
                        right: -5,
                        top: -5,
                        child: IgnorePointer(child: _unreadBadge(unread)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      // Pill-shaped avatar + chevron trigger that drops down the profile
      // card (View Profile / Change Password / Logout).
      ProfileMenuTrigger(
        avatarUrl: profileImageUrl,
        name: headerName,
        idNumber: _studentId,
        onViewProfile: () {
          _refreshProfile();
          context.go('/profile');
        },
        onLogout: _handleLogout,
      ),
    ];
  }

  // ---------- SIDEBAR / DRAWER ----------

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
              : [
                  Colors.white.withOpacity(0.18),
                  Colors.white.withOpacity(0.05),
                ],
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

  Widget _menuLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Row(
        children: [
          Text(
            text,
            style: const TextStyle(
              color: _mutedTextColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
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

  int _activeIndex() {
    final path = GoRouterState.of(context).uri.path;

    if (path.startsWith('/home')) return 0;

    // My Exam stays lit on the exam list and while taking an exam
    if (path.startsWith('/exam-list') ||
        path.startsWith('/take-exam') ||
        path.contains('examhtml')) {
      return 1;
    }

    if (path.startsWith('/schedule')) return 2;

    // /profile, /change-password, /all-notifications, /exam-history, etc.
    return -1;
  }

  Widget _menuTile({
    required IconData icon,
    required String label,
    required String subtitle,
    required int index,
  }) {
    final selected = _activeIndex() == index;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _accentColor.withOpacity(0.28),
                    _accentColor.withOpacity(0.06),
                  ],
                )
              : null,
          border: Border.all(
            color: selected
                ? _accentColor.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onSelectPage(index),
            borderRadius: BorderRadius.circular(16),
            splashColor: _accentColor.withOpacity(0.15),
            hoverColor: Colors.white.withOpacity(0.04),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
              child: Row(
                children: [
                  // Glowing indicator bar on the left edge when selected
                  Container(
                    width: 4,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected ? _accentColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: _accentColor.withOpacity(0.7),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _glowChip(icon, active: selected),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: selected
                                ? _textColor
                                : _textColor.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: selected
                                ? _textColor.withOpacity(0.7)
                                : _mutedTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    Container(
                      width: 8,
                      height: 8,
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
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _mutedTextColor.withOpacity(0.6),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _menuTiles() => [
    _menuLabel("MENU"),
    _menuTile(
      icon: Icons.home_outlined,
      label: 'Home',
      subtitle: 'Overview',
      index: 0,
    ),
    _menuTile(
      icon: Icons.assignment_outlined,
      label: 'My Exam',
      subtitle: 'Your exams',
      index: 1,
    ),
    _menuTile(
      icon: Icons.calendar_month_outlined,
      label: 'My Schedule',
      subtitle: 'Exam schedule',
      index: 2,
    ),
    const SizedBox(height: 16),
  ];

  // Soft accent glow used as an ambient background blob
  Widget _glowBlob(double size, double opacity) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _accentColor.withOpacity(opacity),
              _accentColor.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }

  // Shared sidebar/drawer surface: gradient panel + border + ambient glow
  Widget _sidebarSurface({
    required Widget child,
    required BorderRadius radius,
    bool floating = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_headerColor, _bgColor],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: floating
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            Positioned(top: -70, right: -70, child: _glowBlob(220, 0.22)),
            Positioned(bottom: 90, left: -100, child: _glowBlob(240, 0.10)),
            Positioned.fill(child: child),
          ],
        ),
      ),
    );
  }

  // Header (profile card) + menu + brand footer
  Widget _sidebarContent({required bool desktop}) {
    return Column(
      children: [
        NavHeader(
          name: headerName,
          section: headerSection,
          profileImageUrl: profileImageUrl,
          onProfileTap: () {
            if (desktop) _refreshProfile();
            context.go('/profile');
          },
          onHistoryTap: () async {
            if (desktop) {
              final studentId = await SecureStorageHelper.read('studentId');
              if (!mounted) return;
              context.go('/exam-history', extra: {'studentId': studentId});
            } else {
              context.go('/exam-history');
            }
          },
        ),
        Expanded(
          child: ListView(padding: EdgeInsets.zero, children: _menuTiles()),
        ),
      ],
    );
  }

  Widget _buildDrawer(BuildContext context) {
    const radius = BorderRadius.only(
      topRight: Radius.circular(24),
      bottomRight: Radius.circular(24),
    );

    return Drawer(
      backgroundColor: _bgColor,
      shape: const RoundedRectangleBorder(borderRadius: radius),
      child: PointerInterceptor(
        child: _sidebarSurface(
          radius: radius,
          child: SafeArea(child: _sidebarContent(desktop: false)),
        ),
      ),
    );
  }
}
