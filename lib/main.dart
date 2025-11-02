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
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/forgot',
          builder: (context, state) => const ForgotPage(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => ResponsiveScaffold(
            initialIndex: 0,
            homePage: HomePage(),
            examPage: ExamListPage(),
            schedulePage: SchedulePage(),
          ),
        ),
        GoRoute(
          path: '/exam-list',
          builder: (context, state) => ResponsiveScaffold(
            initialIndex: 1,
            homePage: HomePage(),
            examPage: ExamListPage(),
            schedulePage: SchedulePage(),
          ),
        ),
        GoRoute(
          path: '/schedule',
          builder: (context, state) => ResponsiveScaffold(
            initialIndex: 2,
            homePage: HomePage(),
            examPage: ExamListPage(),
            schedulePage: SchedulePage(),
          ),
        ),
        GoRoute(
          name: 'take-exam',
          path: '/take-exam/:examId',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            return ResponsiveScaffold(
              initialIndex: 1,
              homePage: HomePage(),
              examPage: ExamListPage(),
              schedulePage: SchedulePage(),
              detailPage: TakeExamPage(
                examId: args?['examId'] ?? state.pathParameters['examId']!,
                startMillis: args?['startMillis'],
                endMillis: args?['endMillis'],
              ),
            );
          },
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => ResponsiveScaffold(
            homePage: ProfilePage(),
            examPage: ExamListPage(),
            schedulePage: SchedulePage(),
            detailPage: const ProfilePage(),
          ),
        ),
        GoRoute(
          path: '/exam-history',
          builder: (context, state) {
            final args = state.extra as Map<String, dynamic>?;
            return ResponsiveScaffold(
              homePage: HomePage(),
              examPage: ExamListPage(),
              schedulePage: SchedulePage(),
              detailPage: const ExamHistoryPage(),
            );
          },
        ),
        GoRoute(
          name: 'exam',
          path: '/exam/:examId/:studentId',
          builder: (context, state) {
            final examId = state.pathParameters['examId']!;
            final studentId = state.pathParameters['studentId']!;
            return ResponsiveScaffold(
              homePage: HomePage(),
              examPage: ExamListPage(),
              schedulePage: SchedulePage(),
              detailPage: ExamPage(examId: examId, studentId: studentId),
            );
          },
        ),
        GoRoute(
          name: 'examResult',
          path: '/exam-result/:examId/:studentId',
          builder: (context, state) {
            final examId = state.pathParameters['examId']!;
            final studentId = state.pathParameters['studentId']!;
            final extra = state.extra as Map<String, dynamic>?;
            final fromExamPage = extra?['fromExamPage'] ?? false;
            return ResponsiveScaffold(
              homePage: HomePage(),
              examPage: ExamListPage(),
              schedulePage: SchedulePage(),
              detailPage: ExamResultPage(
                examId: examId,
                studentId: studentId,
                fromExamPage: fromExamPage,
              ),
            );
          },
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
