import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../helpers/ExamLockState.dart';
import '../../helpers/platform_utils.dart';
import 'exam_view.dart';

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
  bool _finishHandled = false;

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

    fetchStudentAndCheckEligibility().then((allowed) {
      if (!allowed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go('/home');
          }
        });
        return;
      }

      // Student is allowed - proceed with exam view
      if (!mounted || _resolvedStudentId == null) return;

      final isReload = isPageReload();
      if (isReload) {
        setReloadingFlag(true);
      } else {
        setReloadingFlag(false);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        clearReloadingFlag();
      });
    });
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

    if (studentId == null) return false;

    final examDoc = await FirebaseFirestore.instance
        .collection("exams")
        .doc(widget.examId)
        .get();
    if (!examDoc.exists) return false;

    final examData = examDoc.data()!;
    if (examData['monitoringEnabled'] != true) return false;

    final examClassId = examData['classId']?.toString().trim();
    final rawClassIds = studentData['classIds'];
    final studentClassIds = <String>{
      if (rawClassIds is Iterable)
        ...rawClassIds
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty),
      if ((studentData['classId'] ?? '').toString().trim().isNotEmpty)
        studentData['classId'].toString().trim(),
    };

    final bool isAllowed;
    if (examClassId != null && examClassId.isNotEmpty) {
      isAllowed = studentClassIds.contains(examClassId);
      if (!isAllowed) {
        debugPrint(
          'Student is not assigned to exam class $examClassId '
          '(assigned classes: $studentClassIds)',
        );
      }
    } else {
      // Older exams are program/year-block based. `program` may be either a
      // display name (e.g. BSCS) or the program code (e.g. 88888).
      final allowedProgram = examData['program']?.toString().trim();
      final allowedYearBlock = examData['yearBlock']?.toString().trim();
      final studentPrograms = {
        if ((studentData['program'] ?? '').toString().trim().isNotEmpty)
          studentData['program'].toString().trim().toLowerCase(),
        if ((studentData['programCode'] ?? '').toString().trim().isNotEmpty)
          studentData['programCode'].toString().trim().toLowerCase(),
      };
      final studentYearBlock = studentData['yearBlock']?.toString().trim();
      isAllowed =
          allowedProgram != null &&
          allowedProgram.isNotEmpty &&
          allowedYearBlock != null &&
          allowedYearBlock.isNotEmpty &&
          studentPrograms.contains(allowedProgram.toLowerCase()) &&
          studentYearBlock == allowedYearBlock;
      if (!isAllowed) {
        debugPrint(
          'Student does not match exam program/year block: '
          'exam=$allowedProgram/$allowedYearBlock, '
          'student=${studentData['program']}/${studentData['programCode']}/'
          '$studentYearBlock',
        );
      }
    }

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

    try {
      final resultRef = FirebaseFirestore.instance
          .collection("examResults")
          .doc(widget.examId)
          .collection("students")
          .doc(uid);

      final resultDoc = await resultRef.get();

      if (resultDoc.exists) {
        final status = resultDoc.data()?['status'];
        debugPrint('Exam status check: $status');

        if (status == 'completed') {
          debugPrint('Status is completed, navigating to result page');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) context.go('/exam-result/${widget.examId}');
          });
          return;
        }

        if (status == 'incomplete') {
          final isReload = isPageReload();

          if (isReload) {
            debugPrint(
              '🔄 Page reload detected, updating status to in-progress',
            );
            await resultRef.set({
              'status': 'in-progress',
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            return;
          }

          // Do not force the user home just because a previous session stored
          // "incomplete". That stale value is often created by a refresh or a
          // forced page close. The exam should continue unless it was truly completed.
          debugPrint('Status is incomplete but not blocking (not a reload)');
          return;
        }
      } else {
        debugPrint('No exam result document found yet');
      }
    } catch (e) {
      debugPrint('Error checking exam status: $e');
    }

    return;
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
        "ExamHtmlPage updated iframe src for examId=${widget.examId}, studentId=$_resolvedStudentId",
      );
    }
  }

  @override
  void dispose() {
    final isReload = isPageReload();

    if (!isReload && _authUid != null && _resolvedStudentId != null) {
      final resultRef = FirebaseFirestore.instance
          .collection('examResults')
          .doc(widget.examId)
          .collection('students')
          .doc(_authUid!);

      resultRef.get().then((doc) async {
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

  void _handleFinish(String examId) {
    if (_finishHandled || !mounted) return;
    _finishHandled = true;
    debugPrint('finishExam received, navigating to /exam-result/$examId');
    context.go('/exam-result/$examId');
  }

  void _handleNavigate(String path) {
    if (!mounted) return;
    debugPrint('navigate received: $path');
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedStudentId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F6),
      body: SafeArea(
        child: ExamView(
          key: ValueKey('exam-view-${widget.examId}-$_resolvedStudentId'),
          examId: widget.examId,
          studentId: _resolvedStudentId!,
          onFinish: _handleFinish,
          onNavigate: _handleNavigate,
        ),
      ),
    );
  }
}
