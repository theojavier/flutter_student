import 'package:flutter/material.dart';

import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
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
  // Route names
  static const String login = '/login';
  static const String home = '/home';
  static const String profile = '/profile';
  static const String examItem = '/exam-item';
  static const String examHistory = '/exam-history';
  static const String schedule = '/schedule';
  static const String forgot = '/forgot';
  static const String resetPassword = '/reset-password';
  static const String takeExam = '/take-exam';
  static const String exam = '/exam';
  static const String examResult = '/exam-result';

  // Route map (for Navigator or MaterialApp)
  static Map<String, WidgetBuilder> routes = {
    login: (context) => const LoginPage(),
    forgot: (context) => const ForgotPage(),

    home: (context) => ResponsiveScaffold(
          homePage: HomePage(),
          examPage: ExamListPage(),
          schedulePage: SchedulePage(),
        ),

    profile: (context) => ResponsiveScaffold(
          homePage: ProfilePage(),
          examPage: ExamListPage(),
          schedulePage: SchedulePage(),
        ),

    examItem: (context) => ResponsiveScaffold(
          homePage: ExamListPage(),
          examPage: SizedBox.shrink(),
          schedulePage: SizedBox.shrink(),
        ),

    

    schedule: (context) => ResponsiveScaffold(
          homePage: SchedulePage(),
          examPage: SizedBox.shrink(),
          schedulePage: SizedBox.shrink(),
        ),

    takeExam: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return ResponsiveScaffold(
        homePage: HomePage(),
        examPage: TakeExamPage(
          examId: args['examId'],
          startMillis: args['startMillis'],
          endMillis: args['endMillis'],
        ),
        schedulePage: SchedulePage(),
        initialIndex: 1,
      );
    },

    exam: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return ResponsiveScaffold(
        homePage: HomePage(),
        examPage: ExamPage(
          examId: args['examId'],
          studentId: args['studentId'],
        ),
        schedulePage:  SchedulePage(),
        initialIndex: 1,
      );
    },

    examResult: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return ResponsiveScaffold(
        homePage: HomePage(),
        examPage: ExamResultPage(
          examId: args['examId'],
          studentId: args['studentId'],
        ),
        schedulePage: SchedulePage(),
        initialIndex: 1,
      );
    },
  };
}
