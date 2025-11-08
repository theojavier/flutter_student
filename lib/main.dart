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
import 'pages/exams/take_exam_page.dart';
import 'pages/personal_info/profile_page.dart';
import 'pages/exams/exam_history_page.dart';
import 'pages/exams/exam_page.dart';
import 'pages/exams/exam_result_page.dart';
import 'pages/auth/forgot_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

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
      initialLocation: isLoggedIn ? '/home' : '/login',
      routes: [
        /// Public Routes
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/forgot',
          builder: (context, state) => const ForgotPage(),
        ),

        ShellRoute(
          builder: (context, state, child) {
            return ResponsiveScaffold(
              detailPage: child,
              homePage: HomePage(),
              examPage: ExamListPage(),
              schedulePage: SchedulePage(),
            );
          },
          routes: [
            GoRoute(path: '/home', builder: (context, state) => HomePage()),
            GoRoute(
              path: '/exam-list',
              builder: (context, state) => ExamListPage(),
            ),
            GoRoute(
              path: '/schedule',
              builder: (context, state) => SchedulePage(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfilePage(),
            ),

            GoRoute(
              name: 'take-exam',
              path: '/take-exam/:examId',
              builder: (context, state) {
                final args = state.extra as Map<String, dynamic>?;
                return TakeExamPage(
                  examId: args?['examId'] ?? state.pathParameters['examId']!,
                  startMillis: args?['startMillis'],
                  endMillis: args?['endMillis'],
                );
              },
            ),
            GoRoute(
              path: '/exam-history',
              builder: (context, state) => const ExamHistoryPage(),
            ),
            GoRoute(
              name: 'exam',
              path: '/exam/:examId/:studentId',
              builder: (context, state) => ExamPage(
                examId: state.pathParameters['examId']!,
                studentId: state.pathParameters['studentId']!,
              ),
            ),
            GoRoute(
              name: 'examResult',
              path: '/exam-result/:examId/:studentId',
              builder: (context, state) {
                final examId = state.pathParameters['examId']!;
                final studentId = state.pathParameters['studentId']!;
                return ExamResultPage(
                  examId: examId,
                  studentId: studentId,
                );
              },
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'A3rd',
      theme: ThemeData(primarySwatch: Colors.blue),
      routerConfig: router,
    );
  }
}
