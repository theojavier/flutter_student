import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:html' show IFrameElement;
// ignore: undefined_prefixed_name
import 'dart:ui_web' as ui;
import '../../helpers/SecureStorageHelper.dart';
import '../../helpers/ExamLockState.dart';

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
  String? _authUid;
  StreamSubscription<html.MessageEvent>? _msgSub;
  bool _finishHandled = false;

  bool _isPageReload() {
    if (!kIsWeb) return false;

    final nav = html.window.performance.getEntriesByType('navigation');
    return nav.isNotEmpty &&
        (nav.first as html.PerformanceNavigationTiming).type == 'reload';
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ExamLockState.isInExam.value = true;
    });

    _authUid = FirebaseAuth.instance.currentUser?.uid;
    if (_authUid == null) {
      debugPrint("No authenticated user — blocking exam");
      return;
    }
    checkExamStatusAndNavigate();

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
          final nav = html.window.performance.getEntriesByType("navigation");
          final isReload =
              nav.isNotEmpty &&
              (nav.first as html.PerformanceNavigationTiming).type == "reload";

          if (isReload)
            html.window.sessionStorage['isReloading'] = 'true';
          else
            html.window.sessionStorage.remove('isReloading');

          WidgetsBinding.instance.addPostFrameCallback((_) {
            html.window.sessionStorage.remove('isReloading');
          });

          if (!mounted) return;
          _msgSub?.cancel();
          _msgSub = html.window.onMessage.listen((event) {
            if (!mounted) return;
            final data = event.data;
            if (data is! Map) return;

            final action = data['action'];
            if (action == 'finishExam') {
              if (_finishHandled) return;
              _finishHandled = true;
              final examId = '${data['examId'] ?? widget.examId}';
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.go('/exam-result/$examId');
              });
            } else if (action == 'navigate') {
              final path = data['path'];
              if (path is String && path.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) context.go(path);
                });
              }
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
    if (!mounted) return false;
    setState(() {
      _resolvedStudentId = studentId;
    });

    return true;
  }

  Future<void> checkExamStatusAndNavigate() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final resultRef = FirebaseFirestore.instance
        .collection("examResults")
        .doc(widget.examId)
        .collection("students")
        .doc(uid);

    final resultDoc = await resultRef.get();

    if (resultDoc.exists) {
      final status = resultDoc.data()?['status'];

      if (status == 'completed') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/exam-result/${widget.examId}');
        });
        return;
      }

      if (status == 'incomplete') {
        final nav = html.window.performance.getEntriesByType('navigation');
        final isReload =
            nav.isNotEmpty &&
            (nav.first as html.PerformanceNavigationTiming).type == 'reload';

        if (isReload) {
          await resultRef.set({
            'status': 'in-progress',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          return;
        }

        // Do not force the user home just because a previous session stored
        // "incomplete". That stale value is often created by a refresh or a
        // forced page close. The exam should continue unless it was truly completed.
        return;
      }
    }

    return;
  }

  bool _iframeRegistered = false;

  void _registerIframe(String examId, String studentId) {
    if (_iframeRegistered) return;
    _iframeRegistered = true;
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
    final storedId = await SecureStorageHelper.read("studentId");

    if (storedId == null) {
      debugPrint("No studentId stored");
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
    _msgSub?.cancel();
    final isReload = _isPageReload();

    if (kIsWeb && !isReload && _authUid != null && _resolvedStudentId != null) {
      final resultRef = FirebaseFirestore.instance
          .collection('examResults')
          .doc(widget.examId)
          .collection('students')
          .doc(_authUid!);

      resultRef.get().then((doc) async {
        if (!mounted) return;
        if (doc.exists && doc.data()?['status'] == 'completed') return;

        await resultRef.set({
          'status': 'incomplete',
          'submittedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ExamLockState.isInExam.value = false;
    });
    super.dispose();
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
          key: ValueKey(
            'exam-html-view-${widget.examId}-${_resolvedStudentId!}',
          ),
          viewType: 'exam-html-view-${widget.examId}-${_resolvedStudentId!}',
        ),
      ),
    );
  }
}
