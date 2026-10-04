import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:super_overlay/super_overlay.dart';
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
  await FirebaseAuth.instance.authStateChanges().first.timeout(
    const Duration(seconds: 5),
    onTimeout: () => null,
  );

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
  // 1. FIXED: Observers must be declared inside GoRouter, not MaterialApp.router
  observers: [SuperOverlay.observer],
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (BuildContext context, GoRouterState state) async {
    final path = state.uri.path;
    final loggingIn = path == '/login' || path == '/forgot';
    final inExam =
        path.startsWith('/take-exam') ||
        path.startsWith('/examhtml') ||
        path.startsWith('/calibrating') ||
        path.startsWith('/exam-result');

    var user = FirebaseAuth.instance.currentUser;

    if (user == null && !loggingIn) {
      if (inExam) return null;

      for (var i = 0; i < 20 && user == null; i++) {
        await Future.delayed(const Duration(seconds: 1));
        user = FirebaseAuth.instance.currentUser;
      }
    }

    if (user == null && !loggingIn) {
      return '/login';
    }
    if (user != null && loggingIn) return '/home';

    return null;
  },
  routes: [
    /// Public Routes
    GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
    GoRoute(path: '/forgot', builder: (context, state) => const ForgotPage()),

    ShellRoute(
      builder: (context, state, child) {
        final location = state.uri.path;
        int selectedIndex = 0;

        if (location.startsWith('/home')) {
          selectedIndex = 0;
        } else if (location.startsWith('/exam-list')) {
          selectedIndex = 1;
        } else if (location.startsWith('/schedule')) {
          selectedIndex = 2;
        }

        return ResponsiveScaffold(selectedIndex: selectedIndex, child: child);
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
            return NoTransitionPage(child: ExamResultPage(examId: examId));
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

    // Calibration route - OUTSIDE ShellRoute (fullscreen, no sidebar)
    // URL persists across reloads: /calibrating/:examId
    GoRoute(
      name: 'calibration',
      path: '/calibrating/:examId',
      pageBuilder: (context, state) {
        final examId = state.pathParameters['examId']!;

        return NoTransitionPage(
          child: GazeCalibrationOverlay(
            examId: examId,
            onCalibrationComplete: () {
              context.goNamed('examhtml', pathParameters: {"examId": examId});
            },
          ),
        );
      },
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
          thumbColor: WidgetStateProperty.all(
            const Color.fromARGB(255, 24, 39, 68),
          ),
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
      // 2. FIXED: Use the global initializer hook method for package rendering
      builder: SuperOverlay.init(),
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
