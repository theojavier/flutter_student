import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;
import 'dart:html' show IFrameElement;
// ignore: undefined_prefixed_name
import 'dart:ui_web' as ui;

class ExamHtmlPage extends StatefulWidget {
  final String examId;
  final String studentId;

  const ExamHtmlPage({
    super.key,
    required this.examId,
    required this.studentId,
  });

  @override
  State<ExamHtmlPage> createState() => _ExamHtmlPageState();
}

class _ExamHtmlPageState extends State<ExamHtmlPage> {
  /// Generate a unique viewType string per exam/student
  String get _viewType => 'exam-html-view-${widget.examId}-${widget.studentId}';

  void _registerIframe() {
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = IFrameElement()
        ..src =
            'assets/exam.html?examId=${widget.examId}&studentId=${widget.studentId}&t=${DateTime.now().millisecondsSinceEpoch}'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';

      iframe.onLoad.listen((_) {
        iframe.contentWindow?.postMessage({
          'examId': widget.examId,
          'studentId': widget.studentId,
        }, '*');
      });

      print("ExamHtmlPage iframe src: ${iframe.src}");
      return iframe;
    });
  }

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // --- RELOAD DETECTION ---
      final nav = html.window.performance?.getEntriesByType("navigation");
      final isReload =
          nav != null &&
          nav.isNotEmpty &&
          (nav.first as html.PerformanceNavigationTiming).type == "reload";

      if (isReload) {
        html.window.sessionStorage['isReloading'] = 'true';
      } else {
        html.window.sessionStorage.remove('isReloading');
        print("NOT a reload");
      }

      print("Reload detected? $isReload");
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
      html.window.sessionStorage.remove('isReloading');
      print("Post-frame: reload flag cleared");
      });

      // Listen for finishExam postMessage
      html.window.onMessage.listen((event) {
        final data = event.data;
        if (data is Map && data['action'] == 'finishExam') {
          final examId = data['examId'];
          final studentId = data['studentId'];
          context.go('/exam-result/$examId/$studentId');
        }
      });

      _registerIframe();
    }
  }

  @override
  void didUpdateWidget(covariant ExamHtmlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.examId != widget.examId ||
        oldWidget.studentId != widget.studentId) {
      _registerIframe();
      setState(() {}); // trigger rebuild with new viewType
      print(
        "ExamHtmlPage updated iframe src for examId=${widget.examId}, studentId=${widget.studentId}",
      );
    }
  }

  Future<bool> validateStudentId(String urlStudentId) async {
    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString("studentId");

    if (storedId == null) {
      debugPrint("No studentId stored in prefs");
      return false;
    }

    if (storedId != urlStudentId) {
      debugPrint("Mismatch! URL studentId=$urlStudentId, stored=$storedId");
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    super.dispose();

    if (kIsWeb) {
      // --- CHECK IF PAGE WAS RELOADED ---
      final wasReload = html.window.sessionStorage['isReloading'] == 'true';

      if (wasReload) {
        debugPrint("Page reload detected → skip marking incomplete");
        return;
      }

      // Continue normal incomplete marking
      final examId = widget.examId;
      final studentId = widget.studentId;

      final resultRef = FirebaseFirestore.instance
          .collection("examResults")
          .doc(examId)
          .collection(studentId)
          .doc("result");

      resultRef
          .get()
          .then((doc) async {
            if (doc.exists && doc.data()?['status'] == 'completed') {
              debugPrint("Exam already completed → skip marking incomplete");
              return;
            }
            await resultRef.set({
              "status": "incomplete",
              "submittedAt": FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            debugPrint(
              "ExamHtmlPage disposed → exam marked incomplete in Firestore",
            );
          })
          .catchError((err) {
            debugPrint("Failed to mark incomplete on dispose: $err");
          });
    }
    html.window.sessionStorage.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const Scaffold(
        body: Center(child: Text("Exam only available on Web.")),
      );
    }

    return Scaffold(
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
