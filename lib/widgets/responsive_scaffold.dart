// responsive_scaffold.dart  (STUDENT)
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../helpers/notifications_helper.dart';
import '../pages/notifications/notification_item.dart';
import 'dart:async';
import '../helpers/SecureStorageHelper.dart';
import '../helpers/class_short_code.dart';
import 'notification_bubble.dart';
import 'profile_menu.dart';
// Platform + Web detection
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

// ---------------------------------------------------------------------------
// Palette (same as the FOTS Admin shell)
// ---------------------------------------------------------------------------
const Color _kPaper = Color(0xFFF7F8F6);
const Color _kInk = Color(0xFF121217);
const Color _kRed = Color(0xFFDF2D45);
const Color _kRedDark = Color(0xFFB81935);
const Color _kNotificationGreen = Color(0xFF087B4F);
const Color _kPillBg = Color(0xFFFFF3F5);
const Color _kPillBorder = Color(0xFFEDCCD1);
const Color _kLine = Color(0xFFDFE0DE);
const Color _kMuted = Color(0xFF92939A);
const Color _kSbLine = Color(0xFF36363B);
const Color _kSbCard = Color(0xFF1D1D23);
const Color _kSbCardBorder = Color(0xFF37373D);
const Color _kSbHover = Color(0xFF28282F);
const Color _kNavIdle = Color(0xFFA5A4AD);
const Color _kNavCount = Color(0xFF888990);
const Color _kLabel = Color(0xFF9797A2);

// Page background behind the content. Your student pages are still dark navy,
// so this stays navy. If you restyle the pages to the light theme,
// change this to _kPaper.
const Color _kBodyBg = Color(0xFF0B1220);

const TextStyle _kMono = TextStyle(fontFamily: 'monospace');

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
  String? profileImageUrl;
  String headerName = "Loading...";
  String headerSection = "";
  String? _studentId;
  String? _userId;
  Map<String, dynamic>? _cachedProfile;
  bool _isDrawerOpen = false;
  bool _classesExpanded = false;
  bool _loadingClasses = false;
  String? _classesError;
  List<String> _classIds = [];
  List<_StudentClass> _studentClasses = [];
  int _classLoadGeneration = 0;
  String? _activeClassId;
  final ScrollController _classListScrollController = ScrollController();
  // Key on the bell button so we can measure where it actually sits
  // on screen and aim the notification bubble's triangle pointer at it.
  final GlobalKey _notificationIconKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _examNotificationSubscriptions = [];
  String? _examNotificationWatchKey;

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

    // silently assign without setState (prevents flicker on nav)
    _userId = userId;

    // fallback display ID until/unless the profile doc has its own
    _studentId = await SecureStorageHelper.read('studentId');

    // show cache immediately, but only once
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

    final notificationWatchKey = [
      _userId ?? '',
      data['role'] ?? '',
      data['program'] ?? '',
      data['programCode'] ?? '',
      data['yearBlock'] ?? '',
      if (data['classIds'] is List)
        ...(data['classIds'] as List).map((value) => value.toString()),
      data['classId'] ?? '',
    ].join('\u0000');
    if (notificationWatchKey != _examNotificationWatchKey) {
      _examNotificationWatchKey = notificationWatchKey;
      for (final subscription in _examNotificationSubscriptions) {
        unawaited(subscription.cancel());
      }
      _examNotificationSubscriptions = [];
      if (data['role'] == 'student' && _userId != null) {
        _examNotificationSubscriptions = watchApprovedExamNotifications(
          userId: _userId!,
          userData: data,
          onError: (error) {
            debugPrint('Could not watch approved exams for notifications: $error');
          },
        );
      }
    }

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
    final classIds = <String>[
      if (data['classIds'] is List)
        ...(data['classIds'] as List)
            .map((value) => value.toString())
            .where((value) => value.isNotEmpty),
      if ((data['classId'] ?? '').toString().isNotEmpty)
        data['classId'].toString(),
    ].toSet().toList();
    if (classIds.join('\u0000') != _classIds.join('\u0000')) {
      _classIds = classIds;
      unawaited(_loadAssignedClasses(classIds));
    }

    // only update UI if something actually changed
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

  Future<void> _loadAssignedClasses(List<String> classIds) async {
    final generation = ++_classLoadGeneration;
    if (mounted) {
      setState(() {
        _loadingClasses = true;
        _classesError = null;
      });
    }

    try {
      final classes = await Future.wait(
        classIds.map((classId) async {
          final classDoc = await FirebaseFirestore.instance
              .collection('classes')
              .doc(classId)
              .get();
          if (!classDoc.exists) return null;

          final data = classDoc.data()!;
          final programId = (data['program'] ?? '').toString();
          var programName = programId;
          if (programId.isNotEmpty) {
            final programDoc = await FirebaseFirestore.instance
                .collection('programs')
                .doc(programId)
                .get();
            if (programDoc.exists) {
              programName = (programDoc.data()?['name'] ?? programId)
                  .toString();
            }
          }

          final subject = (data['subject'] ?? '').toString().trim();
          return _StudentClass(
            id: classDoc.id,
            subject: subject.isEmpty ? programName : subject,
          );
        }),
      );
      if (!mounted || generation != _classLoadGeneration) return;
      setState(() {
        _studentClasses = classes.whereType<_StudentClass>().toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        _loadingClasses = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load assigned student classes: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted || generation != _classLoadGeneration) return;
      setState(() {
        _studentClasses = [];
        _loadingClasses = false;
        _classesError = 'Could not load your assigned classes.';
      });
    }
  }

  @override
  void dispose() {
    _classLoadGeneration++;
    _profileSubscription?.cancel();
    for (final subscription in _examNotificationSubscriptions) {
      subscription.cancel();
    }
    _classListScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final path = GoRouterState.of(context).uri.path;
    if (path.startsWith('/student/class/')) {
      _classesExpanded = true;
      _activeClassId = GoRouterState.of(context).pathParameters['classId'];
    } else {
      _classesExpanded = false;
    }
  }

  Future<void> _onSelectPage(int index) async {
    _activeClassId = null;
    _classesExpanded = false;
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
        context.go('/schedule');
        break;
      case 2:
        context.go('/exam-history');
        break;
      case 4:
        context.go('/profile');
        break;
    }
  }

  Future<void> _onSelectClass(String classId) async {
    if (!_isDesktop(context)) {
      Navigator.of(context).pop();
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
    }
    _activeClassId = classId;
    context.go('/student/class/${Uri.encodeComponent(classId)}');
  }

  // Centralized desktop detection
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

  String get _initials {
    if (_cachedProfile == null) return 'ST';
    final parts = headerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'ST';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);

    return Scaffold(
      backgroundColor: _kBodyBg,
      appBar: isDesktop
          ? null
          : PreferredSize(
              preferredSize: Size.fromHeight(_topBarHeight(false)),
              child: _buildTopBar(desktop: false),
            ),
      drawer: isDesktop ? null : _buildDrawer(context),
      drawerEnableOpenDragGesture: true,
      onDrawerChanged: (isOpen) {
        if (_isDrawerOpen == isOpen || !mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _isDrawerOpen = isOpen);
        });
      },
      body: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 256,
                  child: Container(color: _kInk, child: _sidebarContent()),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _buildTopBar(desktop: true),
                      Expanded(child: _buildContent()),
                    ],
                  ),
                ),
              ],
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        IgnorePointer(ignoring: _isDrawerOpen, child: widget.child),
        if (_isDrawerOpen)
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
    );
  }

  // ---------- TOP BAR ----------

  double _topBarHeight(bool desktop) {
    final inset = desktop ? 0.0 : MediaQuery.of(context).padding.top;
    return (desktop ? 76.0 : 64.0) + inset;
  }

  Widget _buildTopBar({required bool desktop}) {
    final width = MediaQuery.of(context).size.width;
    final inset = desktop ? 0.0 : MediaQuery.of(context).padding.top;
    final path = GoRouterState.of(context).uri.path;
    final routeClassId = GoRouterState.of(context).pathParameters['classId'];
    final selectedClassId = routeClassId ?? _activeClassId;
    final activeClass = _studentClasses.where(
      (studentClass) => studentClass.id == selectedClassId,
    );
    final crumb = path.startsWith('/home')
        ? 'Home'
        : path.startsWith('/schedule')
        ? 'Schedule'
        : path.startsWith('/exam-history')
        ? 'Exam History'
        : path.startsWith('/student/class/') ||
              path.startsWith('/take-exam') ||
              path.startsWith('/examhtml') ||
              path.startsWith('/exam-result')
        ? activeClass.isEmpty
              ? 'Classes'
              : classShortCode(activeClass.first.id, activeClass.first.subject)
        : path.startsWith('/profile')
        ? 'Profile'
        : path.startsWith('/all-notifications')
        ? 'Notifications'
        : 'Workspace';

    final rolePill = Container(
      height: desktop ? 36 : 32,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kPillBg,
        border: Border.all(color: _kPillBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Student workspace',
        style: _kMono.copyWith(
          color: _kRedDark,
          fontSize: 10,
          letterSpacing: 0.4,
        ),
      ),
    );

    return Container(
      height: _topBarHeight(desktop),
      padding: EdgeInsets.fromLTRB(
        desktop ? 35 : 6,
        inset,
        desktop ? 35 : 12,
        0,
      ),
      decoration: BoxDecoration(
        color: _kPaper.withValues(alpha: 0.98),
        border: const Border(bottom: BorderSide(color: _kLine)),
      ),
      child: Row(
        children: [
          if (desktop)
            Text.rich(
              TextSpan(
                style: _kMono.copyWith(fontSize: 11, letterSpacing: 0.6),
                children: [
                  const TextSpan(
                    text: 'WORKSPACE / ',
                    style: TextStyle(color: _kMuted),
                  ),
                  TextSpan(
                    text: crumb.toUpperCase(),
                    style: const TextStyle(
                      color: _kInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            Builder(
              builder: (context) => IconButton(
                tooltip: 'Menu',
                icon: const Icon(Icons.menu_rounded, color: _kInk, size: 26),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: () => context.go('/home'),
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _LogoMark(size: 34, radius: 9),
                  const SizedBox(width: 9),
                  const Text(
                    'FOTS',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '/ STUDENT',
                    style: _kMono.copyWith(color: _kMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          if (desktop || width >= 560) ...[rolePill, const SizedBox(width: 12)],
          ..._buildActions(context),
        ],
      ),
    );
  }

  // Square white icon button used in the top bar (bell)
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
        borderRadius: BorderRadius.circular(9),
        splashColor: _kNotificationGreen.withValues(alpha: 0.12),
        highlightColor: Colors.transparent,
        child: Container(
          key: buttonKey,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: highlight ? _kNotificationGreen : _kLine),
          ),
          child: Icon(
            icon,
            color: highlight ? _kNotificationGreen : _kInk,
            size: 20,
          ),
        ),
      ),
    );
  }

  // Unread badge on the bell
  Widget _unreadBadge(int unread) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _kNotificationGreen,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _kPaper, width: 2),
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

  Widget _profileTrigger() {
    return ProfileMenuTrigger(
      avatarUrl: profileImageUrl,
      name: headerName,
      idNumber: _studentId,
      onViewProfile: () {
        _refreshProfile();
        _classesExpanded = false;
        context.go('/profile');
      },
      onLogout: _handleLogout,
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
                ? snap.data!.docs
                      .where((d) => !(d['read'] ?? d['viewed'] ?? false))
                      .length
                : 0;

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
                                    viewed:
                                        data['read'] ?? data['viewed'] ?? false,
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
                                  onTapItem: (item) {
                                    Navigator.of(ctx).pop();
                                    context.go(
                                      '/take-exam/${Uri.encodeComponent(item.id)}',
                                    );
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
      const SizedBox(width: 8),
      Center(child: _profileTrigger()),
    ];
  }

  // ---------- SIDEBAR / DRAWER ----------

  int _activeIndex() {
    final path = GoRouterState.of(context).uri.path;

    if (path.startsWith('/home')) return 0;
    if (path.startsWith('/schedule')) return 1;
    if (path.startsWith('/exam-history')) return 2;
    if (path.startsWith('/student/class/') ||
        (_activeClassId != null &&
            (path.startsWith('/take-exam') ||
                path.startsWith('/examhtml') ||
                path.startsWith('/exam-result')))) {
      return 3;
    }
    if (path.startsWith('/profile')) return 4;
    return -1;
  }

  Widget _sidebarContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand
          GestureDetector(
            onTap: () => _onSelectPage(0),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 20),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _kSbLine)),
              ),
              child: Row(
                children: [
                  const _LogoMark(size: 42, radius: 10),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FOTS',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.3,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        'STUDENT PORTAL',
                        style: _kMono.copyWith(
                          color: _kNavIdle,
                          fontSize: 9,
                          letterSpacing: 1.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Profile card
          _buildRoleCard(),

          // Section label
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'WORKSPACE',
                  style: _kMono.copyWith(
                    color: _kLabel,
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '01 — 05',
                  style: _kMono.copyWith(
                    color: const Color(0xFF6A6A75),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          // Nav
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: _buildNav(),
              ),
            ),
          ),

          // Footer stamp
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: _kSbLine)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 3, right: 8),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _kRed,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _kRed.withValues(alpha: 0.18),
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STUDENT ACCESS',
                        style: _kMono.copyWith(
                          color: Colors.white,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Exams · Schedule · History',
                        style: _kMono.copyWith(
                          color: const Color(0xFFA2A2AA),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleCard() {
    final hasImage = profileImageUrl != null && profileImageUrl!.isNotEmpty;
    final initialsAvatar = Text(
      _initials,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Container(
        decoration: BoxDecoration(
          color: _kSbCard,
          borderRadius: BorderRadius.circular(10),
          border: const Border.fromBorderSide(
            BorderSide(color: _kSbCardBorder),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              _refreshProfile();
              _classesExpanded = false;
              context.go('/profile');
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: _kRed,
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: hasImage
                        ? Image.network(
                            profileImageUrl!,
                            width: 38,
                            height: 38,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => initialsAvatar,
                          )
                        : initialsAvatar,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          headerSection.isEmpty ? 'Student' : headerSection,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFA1A1AA),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNav() {
    final routeIndex = _activeIndex();
    final classesActive = routeIndex == 3;

    return Column(
      children: [
        _SidebarButton(
          icon: Icons.home_outlined,
          label: 'Home',
          count: '01',
          selected: routeIndex == 0,
          onTap: () => _onSelectPage(0),
        ),

        // Classes (dropdown)
        _SidebarButton(
          icon: Icons.class_outlined,
          label: 'Classes',
          count: '02',
          selected: false,
          highlighted: classesActive,
          onTap: () => setState(() => _classesExpanded = !_classesExpanded),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _classesExpanded
              ? Padding(
                  padding: const EdgeInsets.only(left: 18, bottom: 2),
                  child: Container(
                    padding: const EdgeInsets.only(left: 8),
                    decoration: const BoxDecoration(
                      border: Border(left: BorderSide(color: _kSbLine)),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240),
                      child: Scrollbar(
                        controller: _classListScrollController,
                        thumbVisibility: _studentClasses.length > 5,
                        child: ListView(
                          controller: _classListScrollController,
                          shrinkWrap: true,
                          primary: false,
                          physics: const ClampingScrollPhysics(),
                          children: _classMenuItems(),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),

        _SidebarButton(
          icon: Icons.calendar_month_outlined,
          label: 'My Schedule',
          count: '03',
          selected: routeIndex == 1,
          onTap: () => _onSelectPage(1),
        ),
        _SidebarButton(
          icon: Icons.history_outlined,
          label: 'Exam History',
          count: '04',
          selected: routeIndex == 2,
          onTap: () => _onSelectPage(2),
        ),
        _SidebarButton(
          icon: Icons.person_outline,
          label: 'Profile',
          count: '05',
          selected: routeIndex == 4,
          onTap: () => _onSelectPage(4),
        ),
      ],
    );
  }

  List<Widget> _classMenuItems() {
    if (_loadingClasses) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kRed),
            ),
          ),
        ),
      ];
    }
    if (_classesError != null) {
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _classesError!,
              style: const TextStyle(color: Color(0xFFFF8A9B), fontSize: 11),
            ),
          ),
        ),
      ];
    }
    if (_studentClasses.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(10, 8, 10, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No classes assigned yet.',
              style: TextStyle(color: _kNavIdle, fontSize: 11),
            ),
          ),
        ),
      ];
    }

    final routeClassId = GoRouterState.of(context).pathParameters['classId'];
    final selectedClassId = routeClassId ?? _activeClassId;
    return [
      for (final studentClass in _studentClasses)
        _SidebarButton(
          icon: Icons.menu_book_outlined,
          label: classShortCode(studentClass.id, studentClass.subject),
          selected: selectedClassId == studentClass.id,
          compact: true,
          onTap: () => _onSelectClass(studentClass.id),
        ),
    ];
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      width: 284,
      backgroundColor: _kInk,
      shape: const RoundedRectangleBorder(),
      child: PointerInterceptor(
        child: Container(
          color: _kInk,
          child: SafeArea(child: _sidebarContent()),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable pieces
// ---------------------------------------------------------------------------
class _LogoMark extends StatelessWidget {
  final double size;
  final double radius;
  const _LogoMark({required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Image.asset(
        'assets/image/student_font-removebg-preview.png',
        fit: BoxFit.contain,
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? count;
  final bool selected;
  final bool highlighted;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.highlighted = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = selected
        ? _kInk
        : (highlighted ? Colors.white : _kNavIdle);
    final Color bg = selected
        ? Colors.white
        : (highlighted ? _kSbCard : Colors.transparent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Container(
        height: compact ? 38 : 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(7),
            hoverColor: selected ? Colors.transparent : _kSbHover,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
              child: Row(
                children: [
                  Icon(icon, size: compact ? 17 : 19, color: fg),
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontSize: compact ? 12.5 : 13,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (count != null)
                    Text(
                      count!,
                      style: _kMono.copyWith(
                        fontSize: 10,
                        color: selected ? const Color(0xFF555555) : _kNavCount,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentClass {
  const _StudentClass({required this.id, required this.subject});

  final String id;
  final String subject;
}
