import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../helpers/notifications_helper.dart';
import '../widgets/notifications_list.dart';
import '../pages/notifications/notification_item.dart';
import 'nav_header.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ResponsiveScaffold extends StatefulWidget {
  final Widget homePage;
  final Widget examPage;
  final Widget schedulePage;
  final int initialIndex;
  final Widget? detailPage;

  const ResponsiveScaffold({
    super.key,
    required this.homePage,
    required this.examPage,
    required this.schedulePage,
    this.initialIndex = 0,
    this.detailPage,
  });

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  late int selectedIndex;
  String? profileImageUrl;
  String headerName = "Loading...";
  String headerSection = "";
  String? _userId;
  Map<String, dynamic>? _cachedProfile;

  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialIndex;
    _pages = [widget.homePage, widget.examPage, widget.schedulePage];
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    if (userId == null) {
      setState(() {
        headerName = "No user found";
        headerSection = "";
        profileImageUrl = null;
      });
      return;
    }
    _userId = userId;

    if (_cachedProfile != null) _updateProfileUI(_cachedProfile!);

    await _profileSubscription?.cancel();
    _profileSubscription = FirebaseFirestore.instance
        .collection("users")
        .doc(userId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) {
        setState(() {
          headerName = "Profile not found";
          headerSection = "";
          profileImageUrl = null;
        });
        return;
      }
      _updateProfileUI(doc.data()!);
    });
  }

  void _updateProfileUI(Map<String, dynamic> data) {
    if (!mounted) return;
    var url = (data['profileImage'] as String?) ?? '';
    if (url.isNotEmpty && url.contains('imgur.com') && !url.contains('i.imgur.com')) {
      url = '${url.replaceAll('imgur.com', 'i.imgur.com')}.jpg';
    }

    final newName = data['name'] ?? 'No Name';
    final newSection =
        '${data['program'] ?? ''} ${data['yearBlock'] ?? ''} (${data['semester'] ?? ''})'.trim();
    final newImageUrl = url.isNotEmpty ? url : null;

    if (newName != headerName || newSection != headerSection || newImageUrl != profileImageUrl) {
      setState(() {
        headerName = newName;
        headerSection = newSection;
        profileImageUrl = newImageUrl;
        _cachedProfile = Map<String, dynamic>.from(data);
      });
    } else {
      _cachedProfile = Map<String, dynamic>.from(data);
    }
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  bool _isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (kIsWeb) return width >= 900;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  void _closeDropdownsAndOverlays(BuildContext context) {
    FocusScope.of(context).unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _onSelectPage(int index) {
    setState(() => selectedIndex = index);
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
    if (!_isDesktop(context)) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    const topColor = Colors.blue;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: topColor,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !isDesktop,
        title: GestureDetector(
          onTap: () => context.go('/home'),
          child: Image.asset(
            'assets/image/istockphoto_1401106927_612x612_removebg_preview.png',
            height: 50,
            width: 90,
          ),
        ),
        leading: isDesktop
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: _buildActions(context),
      ),
      drawer: isDesktop ? null : _buildDrawer(context),
      body: isDesktop
    ? Row(
        children: [
          Container(
            width: 260,
            color: Colors.white,
            child: Column(
              children: [
                NavHeader(
                  name: headerName,
                  section: headerSection,
                  profileImageUrl: profileImageUrl,
                  onProfileTap: () async {
                    _navigateSafely(context, '/profile');
                  },
                  onHistoryTap: () async {
                    final prefs = await SharedPreferences.getInstance();
                    final studentId = prefs.getString('studentId');
                    _navigateSafely(context, '/exam-history',
                        extra: {'studentId': studentId});
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
          Expanded(child: widget.detailPage ?? _pages[selectedIndex]),
        ],
      )
    : widget.detailPage ?? _pages[selectedIndex],
    );
  }

  void _navigateSafely(BuildContext context, String route, {Map<String, dynamic>? extra}) async {
    _closeDropdownsAndOverlays(context);
    FocusScope.of(context).unfocus();

    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    final scaffoldState = Scaffold.maybeOf(context);
    if (scaffoldState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    final loc = GoRouter.of(context).routeInformationProvider.value.uri.toString();
    if (loc != route) {
      await Future.delayed(const Duration(milliseconds: 200));
      context.go(route, extra: extra);
    }
  }

  List<Widget> _menuTiles() => [
        _buildMenuItem(Icons.home, 'Home', 0, '/home'),
        _buildMenuItem(Icons.event, 'My Exam', 1, '/exam-list'),
        _buildMenuItem(Icons.schedule, 'My Schedule', 2, '/schedule'),
      ];

  Widget _buildMenuItem(IconData icon, String title, int index, String route) {
    return ListTile(
      leading: Icon(icon, color: Colors.black87),
      title: Text(title, style: const TextStyle(color: Colors.black87)),
      selected: false,
      selectedTileColor: Colors.transparent,
      hoverColor: Colors.grey.shade200,
      focusColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: () => _onSelectPage(index),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      if (_userId == null)
        IconButton(icon: const Icon(Icons.notifications), onPressed: () {})
      else
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_userId)
              .collection('notifications')
              .snapshots(),
          builder: (context, snap) {
            final unread = snap.hasData
                ? snap.data!.docs.where((d) => !(d['viewed'] ?? false)).length
                : 0;

            ensureUserNotifications(userId: _userId!);

            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications),
                  onPressed: () {
                    if (_userId != null) {
                      final notifications = snap.hasData
                          ? snap.data!.docs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return NotificationItem(
                                examId: doc.id,
                                title: data['subject'] ?? 'New Exam',
                                createdAt: (data['createdAt'] as Timestamp).toDate(),
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
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(_userId)
                                    .collection('notifications')
                                    .doc(item.examId)
                                    .update({'viewed': true});
                                Navigator.of(ctx).pop();
                                context.push('/take-exam', extra: {
                                  'examId': item.examId,
                                  'subject': item.title,
                                  'teacherId': item.teacherId,
                                  'startMillis': item.startMillis,
                                  'endMillis': item.endMillis,
                                });
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
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 4, minHeight: 1),
                      child: Text(
                        unread > 9 ? '9+' : unread.toString(),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'logout') {
            await _profileSubscription?.cancel();
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            await FirebaseAuth.instance.signOut();
            _cachedProfile = null;
            _userId = null;
            if (mounted) context.go('/login');
          }
        },
        itemBuilder: (ctx) => const [PopupMenuItem(value: 'logout', child: Text('Logout'))],
      ),
    ];
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          NavHeader(
            name: headerName,
            section: headerSection,
            profileImageUrl: profileImageUrl,
            onProfileTap: () => _navigateSafely(context, '/profile'),
            onHistoryTap: () async {
              final prefs = await SharedPreferences.getInstance();
              final studentId = prefs.getString('studentId');
              _navigateSafely(context, '/exam-history', extra: {'studentId': studentId});
            },
          ),
          ..._menuTiles(),
        ],
      ),
    );
  }
}
