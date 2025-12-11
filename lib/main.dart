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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  usePathUrlStrategy();
  await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);

  //  Check if user is logged in with FirebaseAuth
  final currentUser = FirebaseAuth.instance.currentUser;
  final isLoggedIn = currentUser != null;

  runApp(MyApp(isLoggedIn: isLoggedIn));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  const MyApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      initialLocation: '/login',
      redirect: (BuildContext context, GoRouterState state) {
        final user = FirebaseAuth.instance.currentUser;

        final loggingIn =
            state.uri.path == '/login' || state.uri.path == '/forgot';

        if (user == null && !loggingIn) return '/login'; // not logged in
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

            if (location.startsWith('/home'))
              selectedIndex = 0;
            else if (location.startsWith('/exam-list'))
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
              name: 'examResult',
              path: '/exam-result/:examId',
              pageBuilder: (context, state) {
                final examId = state.pathParameters['examId']!;
                return NoTransitionPage(
                  child: ExamResultPage(examId: examId, 
                  ),
                );
              },
            ),
            GoRoute(
              name: 'examhtml',
              path: '/examhtml/:examId',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ExamHtmlPage(
                  examId: state.pathParameters['examId']!,
                  studentId:
                      '',
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Student TOT',
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
