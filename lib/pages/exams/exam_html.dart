import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;
import 'package:firebase_auth/firebase_auth.dart';
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
  String? _resolvedStudentId;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      fetchStudentAndCheckEligibility().then((allowed) {
        if (!allowed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.go('/home');
            }
          });
          return;
        }

        // Student is allowed - proceed with iframe
        if (_resolvedStudentId != null) {
          final nav = html.window.performance?.getEntriesByType("navigation");
          final isReload =
              nav != null &&
              nav.isNotEmpty &&
              (nav.first as html.PerformanceNavigationTiming).type == "reload";

          if (isReload)
            html.window.sessionStorage['isReloading'] = 'true';
          else
            html.window.sessionStorage.remove('isReloading');

          WidgetsBinding.instance.addPostFrameCallback((_) {
            html.window.sessionStorage.remove('isReloading');
          });

          html.window.onMessage.listen((event) {
            if (!mounted) return; // prevent navigation after dispose
            final data = event.data;
            if (data is Map && data['action'] == 'finishExam') {
              final examId = data['examId'];
              context.go('/exam-result/$examId');
            }
          });

          _registerIframe(widget.examId, _resolvedStudentId!);
        }
      });
    }
  }

  Future<bool> fetchStudentAndCheckEligibility() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    final studentDoc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();
    if (!studentDoc.exists) return false;

    final studentData = studentDoc.data()!;
    final studentId = studentData['studentId'] as String?;
    final program = studentData['program'];
    final yearBlock = studentData['yearBlock'];

    if (studentId == null || program == null || yearBlock == null) return false;

    final examDoc = await FirebaseFirestore.instance
        .collection("exams")
        .doc(widget.examId)
        .get();
    if (!examDoc.exists) return false;

    final examData = examDoc.data()!;
    final allowedProgram = examData['program'];
    final allowedYearBlock = examData['yearBlock'];

    if (allowedProgram == null || allowedYearBlock == null) return false;

    //Check if student matches exam's allowed program and yearBlock
    final isAllowed =
        (program == allowedProgram) && (yearBlock == allowedYearBlock);

    if (!isAllowed) return false;

    //Check exam start/end times
    final Timestamp? startTs = examData['startTime'];
    final Timestamp? endTs = examData['endTime'];

    if (startTs == null || endTs == null) return false;

    final DateTime startTime = startTs.toDate();
    final DateTime endTime = endTs.toDate();
    final DateTime now = DateTime.now();

    // If exam not yet started or already ended - reject
    if (now.isBefore(startTime) || now.isAfter(endTime)) {
      return false;
    }

    // resolve studentId
    setState(() {
      _resolvedStudentId = studentId;
    });

    return true;
  }

  void _registerIframe(String examId, String studentId) {
    final viewType = 'exam-html-view-$examId-$studentId';
    ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = IFrameElement()
        ..src = '${html.window.location.origin}/assets/exam.html?examId=$examId'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow =
            'fullscreen; microphone; camera; clipboard-read; clipboard-write';

      iframe.onLoad.listen((_) {
        iframe.contentWindow?.postMessage({
          'examId': examId,
          'studentId': studentId,
        }, '*');
      });

      return iframe;
    });
  }

  @override
  void didUpdateWidget(covariant ExamHtmlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.examId != widget.examId ||
        oldWidget.studentId != widget.studentId) {
      if (_resolvedStudentId == null || _resolvedStudentId!.isEmpty) {
        debugPrint("StudentId not resolved yet, skipping Firestore call");
        return;
      }
      setState(() {});
      print(
        "ExamHtmlPage updated iframe src for examId=${widget.examId}, studentId=${_resolvedStudentId}",
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

      final wasReload = html.window.sessionStorage['isReloading'] == 'true';

      if (wasReload) {
        debugPrint("Page reload detected  skip marking incomplete");
        return;
      }

      // Continue normal incomplete marking
      //final examId = widget.examId;
      if (_resolvedStudentId != null && _resolvedStudentId!.isNotEmpty) {
        final resultRef = FirebaseFirestore.instance
            .collection("examResults")
            .doc(widget.examId)
            .collection("students")
            .doc(_resolvedStudentId!);

        resultRef
            .get()
            .then((doc) async {
              if (doc.exists && doc.data()?['status'] == 'completed') {
                debugPrint("Exam already completed  skip marking incomplete");
                return;
              }
              await resultRef.set({
                "status": "incomplete",
                "submittedAt": FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              debugPrint(
                "ExamHtmlPage disposed exam marked incomplete in Firestore",
              );
            })
            .catchError((err) {
              debugPrint("Failed to mark incomplete on dispose: $err");
            });
      }
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

    if (_resolvedStudentId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: HtmlElementView(
          viewType: 'exam-html-view-${widget.examId}-${_resolvedStudentId!}',
        ),
      ),
    );
  }
}
