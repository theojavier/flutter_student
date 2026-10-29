import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'helpers/url_strategy.dart';
import 'firebase_options.dart';
import 'widgets/responsive_scaffold.dart';
import 'pages/home/home_page.dart';
import 'pages/exams/exam_list_page.dart';
import 'pages/exams/class_exam_page.dart';
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
  configureUrlStrategy();

  // Only supported on web; Android/iOS already keep the login automatically
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }

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
  refreshListenable: GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  ),
  redirect: (BuildContext context, GoRouterState state) async {
    final path = state.uri.path;
    final loggingIn = path == '/login' || path == '/forgot';
    final inExam =
        path.startsWith('/take-exam') ||
        path.startsWith('/examhtml') ||
        path.startsWith('/exam-result');

    var user = FirebaseAuth.instance.currentUser;

    if (user == null && !loggingIn) {
      if (inExam) return null;

      // Only wait on web; mobile login is already restored by authStateChanges()
      if (kIsWeb) {
        for (var i = 0; i < 20 && user == null; i++) {
          await Future.delayed(const Duration(seconds: 1));
          user = FirebaseAuth.instance.currentUser;
        }
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
        } else if (location.startsWith('/schedule')) {
          selectedIndex = 1;
        } else if (location.startsWith('/exam-history')) {
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
          path: '/student/class/:classId',
          pageBuilder: (context, state) {
            final classId = state.pathParameters['classId']!;
            return NoTransitionPage(
              child: ClassExamPage(key: ValueKey(classId), classId: classId),
            );
          },
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
          name: 'exam',
          path: '/examhtml/:examId',
          pageBuilder: (context, state) => NoTransitionPage(
            child: ExamHtmlPage(
              examId: state.pathParameters['examId']!,
              studentId: FirebaseAuth.instance.currentUser?.uid ?? '',
            ),
          ),
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
        scaffoldBackgroundColor: const Color.fromARGB(255, 255, 255, 255),
        canvasColor: const Color.fromARGB(255, 241, 241, 242),
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
          seedColor: const Color(0xFF179C68),
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
