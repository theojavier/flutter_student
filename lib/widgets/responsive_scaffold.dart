// responsive_scaffold.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'nav_header.dart';
import 'package:go_router/go_router.dart';
import '../helpers/notifications_helper.dart';
import '../widgets/notifications_list.dart';
import '../pages/notifications/notification_item.dart';
import 'dart:async';

//  Platform + Web detection
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

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

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialIndex; //  set from constructor
    _pages = [widget.homePage, widget.examPage, widget.schedulePage];
    _loadUserProfile();
  }

  StreamSubscription<DocumentSnapshot>? _profileSubscription;

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');

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
    if (!mounted) return; // 🔒 safeguard

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

    // close drawer on mobile
    if (!_isDesktop(context)) {
      Navigator.pop(context);
    }
  }

  //  Centralized desktop detection
  bool _isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (kIsWeb) {
      // Treat wide web browsers as desktop, narrow as mobile
      return width >= 900;
    }

    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    const topColor = Colors.blue;

    return Scaffold(
      appBar: isDesktop
          ? AppBar(
              backgroundColor: topColor,
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              title: GestureDetector(
                onTap: () => context.go('/home'),
                child: Image.asset(
                  'assets/image/istockphoto_1401106927_612x612_removebg_preview.png',
                  height: 50,
                  width: 90,
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
                  'assets/image/istockphoto_1401106927_612x612_removebg_preview.png',
                  height: 50,
                  width: 90,
                ),
              ),
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              actions: _buildActions(context),
            ),
      drawer: isDesktop ? null : _buildDrawer(context),

      body: Row(
        children: [
          if (isDesktop)
            Container(
              width: 260,
              color: Colors.white,
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
          Expanded(child: widget.detailPage ?? _pages[selectedIndex]),
        ],
      ),
    );
  }

  List<Widget> _menuTiles() => [
    ListTile(
      leading: const Icon(Icons.home),
      title: const Text('Home'),
      selected: selectedIndex == 0,
      onTap: () => _onSelectPage(0),
    ),
    ListTile(
      leading: const Icon(Icons.event),
      title: const Text('My Exam'),
      selected: selectedIndex == 1,
      onTap: () => _onSelectPage(1),
    ),
    ListTile(
      leading: const Icon(Icons.schedule),
      title: const Text('My Schedule'),
      selected: selectedIndex == 2,
      onTap: () async {
        final prefs = await SharedPreferences.getInstance();
        final studentId = prefs.getString('studentId');
        if (!mounted) return;
        _onSelectPage(2);
      },
    ),
  ];

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

            // Optional: ensure notifications exist
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
                                context.push(
                                  '/take-exam',
                                  extra: {
                                    'examId': item.examId,
                                    'subject': item.title,
                                    'teacherId': item.teacherId,
                                    'startMillis': item.startMillis,
                                    'endMillis': item.endMillis,
                                  },
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
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
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
        onSelected: (value) async {
          if (value == 'logout') {
            final prefs = await SharedPreferences.getInstance();
            await prefs.clear();
            _cachedProfile = null;
            if (mounted) context.go('/login');
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
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          NavHeader(
            name: headerName,
            section: headerSection,
            profileImageUrl: profileImageUrl,
            onProfileTap: () => context.push('/profile'),
            onHistoryTap: () async {
              context.push('/exam-history');
            },
          ),
          ..._menuTiles(),
        ],
      ),
    );
  }
}
