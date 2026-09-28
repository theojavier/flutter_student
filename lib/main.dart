import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'firebase_options.dart';
import 'widgets/responsive_scaffold.dart';
import 'pages/home/home_page.dart';
import 'pages/exams/exam_list_page.dart';
import 'pages/home/schedule_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/exams/take_exam_page.dart';
import 'pages/personal_info/profile_page.dart';
import 'pages/exams/exam_history_page.dart';
import 'pages/exams/exam_result_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/exams/exam_html.dart';
import 'pages/notifications/notifications_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  usePathUrlStrategy();
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);

  // wait for Firebase to restore the saved login (max 5 seconds)
  await FirebaseAuth.instance
      .authStateChanges()
      .first
      .timeout(const Duration(seconds: 5), onTimeout: () => null);

  runApp(const MyApp());
}

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final GoRouter router = GoRouter(
  initialLocation: '/home',
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (BuildContext context, GoRouterState state) async {
    final path = state.uri.path;
    final loggingIn = path == '/login' || path == '/forgot';
    final inExam = path.startsWith('/take-exam') ||
        path.startsWith('/examhtml') ||
        path.startsWith('/exam-result');

    var user = FirebaseAuth.instance.currentUser;


    if (user == null && !loggingIn) {
      // Never yank a student out of an active exam over a transient auth
      // blip -- Firebase Auth's cross-tab sync can broadcast a spurious
      // null user during a brief network drop (confirmed: Firestore
      // logged a 10s "backend unreachable" timeout during this exact
      // scenario). The exam page has its own "auth not ready" handling
      // and will recover once the connection returns.
      if (inExam) return null;

      // Elsewhere, allow up to ~20s for a transient blip to resolve
      // before treating it as a real sign-out.
      for (var i = 0; i < 20 && user == null; i++) {
        await Future.delayed(const Duration(seconds: 1));
        user = FirebaseAuth.instance.currentUser;
        // debugPrint('[router.redirect] retry $i -> user=${user?.uid}');
      }
    }

    if (user == null && !loggingIn) {
      // debugPrint('[router.redirect] -> /login (user still null)');
      return '/login';
    }
    if (user != null && loggingIn) return '/home'; // already logged in

    return null;
  },
  routes: [
    /// Public Routes
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(
      path: '/forgot',
      builder: (context, state) => const ForgotPage(),
    ),

    ShellRoute(
      builder: (context, state, child) {
        final location = state.uri.path;
        int selectedIndex = 0;

        if (location.startsWith('/home')) {
          selectedIndex = 0;
        } else if (location.startsWith('/exam-list'))
          selectedIndex = 1;
        else if (location.startsWith('/schedule'))
          selectedIndex = 2;

        return ResponsiveScaffold(
          selectedIndex: selectedIndex,
          child: child,
        );
      },
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomePage()),
        ),
        GoRoute(
          path: '/exam-list',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ExamListPage()),
        ),
        GoRoute(
          path: '/schedule',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SchedulePage()),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ProfilePage()),
        ),

        GoRoute(
          name: 'take-exam',
          path: '/take-exam/:examId',
          pageBuilder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            return NoTransitionPage(
              child: TakeExamPage(
                examId: args?['examId'] ?? state.pathParameters['examId']!,
                startMillis: args?['startMillis'],
                endMillis: args?['endMillis'],
              ),
            );
          },
        ),
        GoRoute(
          path: '/exam-history',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ExamHistoryPage()),
        ),
        GoRoute(
          path: '/all-notifications',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: NotificationsPage()),
        ),
        GoRoute(
          name: 'examResult',
          path: '/exam-result/:examId',
          pageBuilder: (context, state) {
            final examId = state.pathParameters['examId']!;
            return NoTransitionPage(
              child: ExamResultPage(examId: examId),
            );
          },
        ),
        GoRoute(
          name: 'examhtml',
          path: '/examhtml/:examId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ExamHtmlPage(
              examId: state.pathParameters['examId']!,
              studentId: FirebaseAuth.instance.currentUser?.uid ?? '',
            ),
          ),
        ),
      ],
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Student FOT',
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        canvasColor: const Color(0xFF0B1220),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(Color.fromARGB(255, 24, 39, 68)),
          trackColor: WidgetStateProperty.all(Colors.black12),
          trackBorderColor: WidgetStateProperty.all(Colors.transparent),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(8),
        ),

        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          background: const Color(0xFF0B1220),
        ),
      ),
      scrollBehavior: MyScrollBehavior(),
      routerConfig: router,
    );
  }
}

class MyScrollBehavior extends MaterialScrollBehavior {
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(
      controller: details.controller,
      thumbVisibility: true,
      child: child,
    );
  }
}