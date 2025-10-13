import 'package:flutter/material.dart';

import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/auth/reset_password_page.dart';
import 'pages/home/home_page.dart';
import 'pages/personal_info/profile_page.dart';
import 'pages/exams/exam_list_page.dart';
import 'pages/exams/exam_page.dart';
import 'pages/exams/take_exam_page.dart';
import 'pages/exams/exam_result_page.dart';
import 'pages/exams/exam_history_page.dart';
import 'pages/home/schedule_page.dart';
import 'widgets/responsive_scaffold.dart';

class AppRoutes {
  // 🔹 Named route constants
  static const String login = '/login';
  static const String forgot = '/forgot';
  static const String resetPassword = '/reset-password';
  static const String home = '/home';
  static const String examList = '/exam-list';
  static const String schedule = '/schedule';
  static const String profile = '/profile';
  static const String examHistory = '/exam-history';
  static const String takeExam = '/take-exam';
  static const String exam = '/exam';
  static const String examResult = '/exam-result';

  // 🔹 Route map for MaterialApp
  static Map<String, WidgetBuilder> routes = {
    login: (context) => const LoginPage(),
    forgot: (context) => const ForgotPage(),
    resetPassword: (context) => const ResetPasswordPage(),

    // Main entry point (with persistent nav)
    home: (context) => ResponsiveScaffold(
          homePage: const HomePage(),
          examPage: const ExamListPage(),
          schedulePage: const SchedulePage(),
          initialIndex: 0,
        ),

    // Profile tab
    profile: (context) => ResponsiveScaffold(
          homePage: const ProfilePage(),
          examPage: const ExamListPage(),
          schedulePage: const SchedulePage(),
          initialIndex: 0,
        ),

    // Exam list tab
    examList: (context) => ResponsiveScaffold(
          homePage: const HomePage(),
          examPage: const ExamListPage(),
          schedulePage: const SchedulePage(),
          initialIndex: 1,
        ),

    // Schedule tab
    schedule: (context) => ResponsiveScaffold(
          homePage: const HomePage(),
          examPage: const ExamListPage(),
          schedulePage: const SchedulePage(),
          initialIndex: 2,
        ),

    // Exam history (with arguments)
    examHistory: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      final studentId = args?['studentId'] ?? '';
      return ResponsiveScaffold(
        homePage: const HomePage(),
        examPage: ExamHistoryPage(studentId: studentId),
        schedulePage: const SchedulePage(),
        initialIndex: 1,
      );
    },

    // Taking exam
    takeExam: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      return ResponsiveScaffold(
        homePage: const HomePage(),
        examPage: TakeExamPage(
          examId: args?['examId'] ?? '',
          startMillis: args?['startMillis'] as int?,
          endMillis: args?['endMillis'] as int?,
        ),
        schedulePage: const SchedulePage(),
        initialIndex: 1,
      );
    },

    // Exam view page
    exam: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      return ResponsiveScaffold(
        homePage: const HomePage(),
        examPage: ExamPage(
          examId: args?['examId'] ?? '',
          studentId: args?['studentId'] ?? '',
        ),
        schedulePage: const SchedulePage(),
        initialIndex: 1,
      );
    },

    // Exam result page
    examResult: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      return ResponsiveScaffold(
        homePage: const HomePage(),
        examPage: ExamResultPage(
          examId: args?['examId'] ?? '',
          studentId: args?['studentId'] ?? '',
        ),
        schedulePage: const SchedulePage(),
        initialIndex: 1,
      );
    },
  };
}
