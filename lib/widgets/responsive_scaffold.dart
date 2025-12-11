// responsive_scaffold.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'nav_header.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../helpers/notifications_helper.dart';
import '../widgets/notifications_list.dart';
import '../pages/exams/exam_html.dart';
import '../pages/notifications/notification_item.dart';
import 'dart:async';

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

class ResponsiveScaffoldState extends State<ResponsiveScaffold>  {
  String? profileImageUrl;
  String headerName = "Loading...";
  String headerSection = "";
  String? _userId;
  Map<String, dynamic>? _cachedProfile;
  bool _isDrawerOpen = false;

  late final List<Widget> _pages;

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
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('userId');
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

    //  only update UI if something actually changed
    if (newName != headerName ||
        newSection != headerSection ||
        newImageUrl != profileImageUrl) {
      setState(() {
        headerName = newName;
        headerSection = newSection;
        profileImageUrl = newImageUrl;
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
      await Future.delayed(Duration(milliseconds: 200));
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    bool isExamHtmlPage = GoRouterState.of(
      context,
    ).uri.path.contains('examhtml');
    const topColor = Color(0xFF0F2B45);

    return Scaffold(
      backgroundColor: Color(0xFF0F2B45),
      appBar: isDesktop
          ? AppBar(
              backgroundColor: topColor,
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              title: GestureDetector(
                onTap: () => context.go('/home'),
                child: Image.asset(
                  'assets/image/fots_student.png',
                  height: 80,
                  width: 120,
                ),
              ),
              actions: _buildActions(context),
            )
          : AppBar(
              backgroundColor: topColor,
              centerTitle: true,
              automaticallyImplyLeading: false,
              title: GestureDetector(
                onTap: () => context.go('/home'),
                child: Image.asset(
                  'assets/image/fots_student.png',
                  height: 80,
                  width: 120,
                ),
              ),
              leading: (!isDesktop && isExamHtmlPage)
                  ? IgnorePointer(
                      child: IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () {},
                      ),
                    )
                  : Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),

              actions: _buildActions(context),
            ),
      drawer: (!isDesktop && !isExamHtmlPage) ? _buildDrawer(context) : null,
      //drawer: isDesktop ? null : _buildDrawer(context),
      onDrawerChanged: (isOpen) {
        setState(() {
          _isDrawerOpen = isOpen;
        });
      },
      body: Row(
        children: [
          // Desktop sidebar
          if (isDesktop)
            Container(
              width: 260,
              color: Color.fromARGB(255, 17, 50, 80),
              child: Column(
                children: [
                  NavHeader(
                    name: headerName,
                    section: headerSection,
                    profileImageUrl: profileImageUrl,
                    onProfileTap: () {
                      _refreshProfile();
                      context.go('/profile');
                    },
                    onHistoryTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final studentId = prefs.getString('studentId');
                      context.go(
                        '/exam-history',
                        extra: {'studentId': studentId},
                      );
                    },
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: _menuTiles(),
                    ),
                  ),
                ],
              ),
            ),

          // Main content
          Expanded(
            child: Stack(
              children: [
                // Your content/iframe
                widget.child,

                // Only block interaction when drawer is open (mobile)
                if (_isDrawerOpen && !isDesktop)
                  IgnorePointer(
                    ignoring: false, // blocks taps below
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).maybePop(); // closes drawer
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
  }

  List<Widget> _menuTiles() => [
    ListTile(
      tileColor: Color(0xFF0F2B45),
      leading: const Icon(Icons.home, color: Colors.white),
      title: const Text('Home', style: TextStyle(color: Color(0xFFE6F0F8))),
      onTap: () => _onSelectPage(0),
    ),
    ListTile(
      tileColor: Color(0xFF0F2B45),
      leading: const Icon(Icons.event, color: Colors.white),
      title: const Text('My Exam', style: TextStyle(color: Color(0xFFE6F0F8))),
      onTap: () => _onSelectPage(1),
    ),
    ListTile(
      tileColor: Color(0xFF0F2B45),
      leading: const Icon(Icons.schedule, color: Colors.white),
      title: const Text(
        'My Schedule',
        style: TextStyle(color: Color(0xFFE6F0F8)),
      ),
      onTap: () async {
        if (!mounted) return;
        _onSelectPage(2);
      },
    ),
  ];

  List<Widget> _buildActions(BuildContext context) {
    return [
      if (_userId == null)
        IconButton(
          icon: const Icon(Icons.notifications, color: Colors.white),
          onPressed: () {},
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

            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications, color: Colors.white),
                  onPressed: () {
                    if (_userId != null) {
                      final notifications = snap.hasData
                          ? snap.data!.docs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return NotificationItem(
                                examId: doc.id,
                                title: data['subject'] ?? 'New Exam',
                                createdAt: (data['createdAt'] as Timestamp)
                                    .toDate(),
                                viewed: data['viewed'] ?? false,
                              );
                            }).toList()
                          : <NotificationItem>[];

                      showDialog(
                        context: context,
                        builder: (ctx) => Dialog(
                          child: SizedBox(
                            height: 400,
                            width: 300,
                            child: NotificationsList(
                              notifications: notifications,
                              onNotificationClick: (item) async {
                                // mark as viewed
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(_userId)
                                    .collection('notifications')
                                    .doc(item.examId)
                                    .update({'viewed': true});

                                Navigator.of(ctx).pop();
                                context.go('/take-exam/${item.examId}');
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
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Color(0xFF0F2B45),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 4,
                        minHeight: 1,
                      ),
                      child: Text(
                        unread > 9 ? '9+' : unread.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.white),
      onSelected: (value) async {
        if (value == 'logout') {
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Logout failed: $e')),
            );
          }
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'logout', child: Text('Logout')),
      ],
    ),
    ];
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Color(0xFF0F2B45),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          NavHeader(
            name: headerName,
            section: headerSection,
            profileImageUrl: profileImageUrl,
            onProfileTap: () => context.go('/profile'),
            onHistoryTap: () async {
              context.go('/exam-history');
            },
          ),
          ..._menuTiles(),
        ],
      ),
    );
  }
}
