import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/exam_history_model.dart';
import '../../widgets/exam_history_item.dart';

class ExamHistoryPage extends StatefulWidget {
  const ExamHistoryPage({super.key});

  @override
  State<ExamHistoryPage> createState() => _ExamHistoryPageState();
}

class _ExamHistoryPageState extends State<ExamHistoryPage> {
  String? studentId;
  String? program;
  String? yearBlock;
  String? _authUid;
  bool loading = true;

  @override
  void initState() {
    super.initState();

    _authUid = FirebaseAuth.instance.currentUser?.uid;
    if (_authUid == null) {
      setState(() => loading = false);
      return;
    }

    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    final uid = _authUid;
    if (uid == null) {
      setState(() => loading = false);
      return;
    }

    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (!userSnap.exists) {
      setState(() => loading = false);
      return;
    }

    setState(() {
      studentId = userSnap['studentId'];
      program = userSnap['program'];
      yearBlock = userSnap['yearBlock'];
      loading = false;
    });
  }

  Stream<List<ExamHistoryModel>> getExamHistoryStream() {
  if (loading || studentId == null || program == null || yearBlock == null) {
    return Stream.value([]);
  }

  final examResultsRef = FirebaseFirestore.instance
      .collection("examResults")
      .where("program", isEqualTo: program)
      .where("yearBlock", isEqualTo: yearBlock);

  return examResultsRef.snapshots().asyncMap((snapshot) async {
    final results = <ExamHistoryModel>[];

    for (final examDoc in snapshot.docs) {
      final studentSnap = await examDoc.reference
          .collection("students")
          .doc(_authUid)
          .get();

      if (studentSnap.exists) {
        results.add(ExamHistoryModel.fromDoc(studentSnap, examDoc.id));
      }
    }

    results.sort((a, b) {
      final aTime = a.submittedAt?.toDate() ?? DateTime(1970);
      final bTime = b.submittedAt?.toDate() ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    return results;
  });
}


  @override
  Widget build(BuildContext context) {
    if (studentId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: [
            // Top block title
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2B45),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text(
                  'Exam History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Exam list
            Expanded(
              child: StreamBuilder<List<ExamHistoryModel>>(
                stream: getExamHistoryStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text("Error: ${snapshot.error}"));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text(
                            "No exam history found",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final exams = snapshot.data!;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: exams.length,
                    itemBuilder: (context, index) {
                      final exam = exams[index];
                      return ExamHistoryItem(
                        exam: exam,
                        onTap: () {
                          context.go(
                            '/take-exam/${exam.id}',
                            extra: {
                              "examId": exam.id,
                              "subject": exam.subject,
                              "score": exam.score,
                              "total": exam.total,
                              'startMillis': null,
                              'endMillis': null,
                            },
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
