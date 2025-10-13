// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'widgets/responsive_scaffold.dart';
import 'pages/home/home_page.dart';
import 'pages/exams/exam_list_page.dart';
import 'pages/home/schedule_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/personal_info/profile_page.dart';
import 'pages/exams/exam_history_page.dart';
import 'pages/exams/take_exam_page.dart';
import 'pages/exams/exam_page.dart';
import 'pages/exams/exam_result_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      initialLocation: '/login',

      // 🔹 Routes
      routes: [
        // Auth routes
        GoRoute(
          path: '/login',
          builder: (_, __) => const LoginPage(),
        ),
        GoRoute(
          path: '/forgot',
          builder: (_, __) => const ForgotPage(),
        ),

        // ShellRoute for persistent ResponsiveScaffold
        ShellRoute(
          builder: (context, state, child) {
            // 🔹 Determine initial tab index based on route
            final loc = state.uri.toString(); // ✅ use uri.toString()
            int initialIndex = 0;
            if (loc.startsWith('/exam-list')) initialIndex = 1;
            if (loc.startsWith('/schedule')) initialIndex = 2;

            return ResponsiveScaffold(
              initialIndex: initialIndex,
              homePage: const HomePage(),
              examPage: const ExamListPage(),
              schedulePage: const SchedulePage(),
              detailPage: child, // nested content renders here
            );
          },

          routes: [
            // Main tabs
            GoRoute(path: '/home', builder: (_, __) => const HomePage()),
            GoRoute(path: '/exam-list', builder: (_, __) => const ExamListPage()),
            GoRoute(path: '/schedule', builder: (_, __) => const SchedulePage()),
             GoRoute(
      path: '/profile',
      builder: (_, __) => const ProfilePage(),
    ),
    GoRoute(
      path: '/exam-history',
      builder: (context, state) {
        final studentId = (state.extra as Map<String, dynamic>?)?['studentId'] ?? '';
        return ExamHistoryPage(studentId: studentId);
      },
    ),
            GoRoute(
              path: '/take-exam',
              builder: (context, state) {
                final args = state.extra as Map<String, dynamic>?;
                return TakeExamPage(
                  examId: args?['examId'] ?? '',
                  startMillis: args?['startMillis'] as int?,
                  endMillis: args?['endMillis'] as int?,
                );
              },
            ),
            GoRoute(
              name: 'exam',
              path: '/exam/:examId/:studentId',
              builder: (context, state) {
                return ExamPage(
                  examId: state.pathParameters['examId'] ?? '',
                  studentId: state.pathParameters['studentId'] ?? '',
                );
              },
            ),
            GoRoute(
              name: 'examResult',
              path: '/exam-result/:examId/:studentId',
              builder: (context, state) {
                return ExamResultPage(
                  examId: state.pathParameters['examId'] ?? '',
                  studentId: state.pathParameters['studentId'] ?? '',
                );
              },
            ),
          ],
        ),
      ],

      // 🔹 Redirect based on auth
      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        final loggingIn = state.uri.toString() == '/login';

        if (user == null && !loggingIn) return '/login';
        if (user != null && loggingIn) return '/home';
        return null;
      },
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'A3rd',
      theme: ThemeData(primarySwatch: Colors.blue),
      routerConfig: router,
    );
  }
}
