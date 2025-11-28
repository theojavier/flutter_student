import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';

class ExamWebPage extends StatefulWidget {
  const ExamWebPage({super.key});

  @override
  State<ExamWebPage> createState() => _ExamWebPageState();
}

class _ExamWebPageState extends State<ExamWebPage> {
  late WebViewController controller;

  @override
  void initState() {
    super.initState();
    _loadWebContent();
  }

  Future<void> _loadWebContent() async {
    final prefs = await SharedPreferences.getInstance();
    final examId = prefs.getString("examId") ?? "";
    final studentId = prefs.getString("studentId") ?? "";
    final answers = <String, dynamic>{};

    for (var key in prefs.getKeys()) {
      if (key.startsWith("answer_")) {
        answers[key] = prefs.getString(key);
      }
    }

    final html = await rootBundle.loadString('assets/exam.html');

    // Inject SharedPreferences data into the HTML
    final injectedHtml = html.replaceFirst(
      '</head>',
      '''
      <script>
        window.flutterExamData = ${jsonEncode({
        "examId": examId,
        "studentId": studentId,
        "answers": answers,
      })};
      </script>
      </head>
      ''',
    );

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(injectedHtml);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exam Portal')),
      body: WebViewWidget(controller: controller),
    );
  }
}
