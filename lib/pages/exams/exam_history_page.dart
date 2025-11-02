import 'package:flutter/material.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/exam_history_model.dart';
import '../../widgets/exam_history_item.dart';

class ExamHistoryPage extends StatefulWidget {
  const ExamHistoryPage({super.key});

  @override
  State<ExamHistoryPage> createState() => _ExamHistoryPageState();
}

class _ExamHistoryPageState extends State<ExamHistoryPage> {
  String? studentId;

  @override
  void initState() {
    super.initState();
    _loadStudentId();
  }

  Future<void> _loadStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studentId = prefs.getString('studentId') ?? '';
    });
  }

  Stream<List<ExamHistoryModel>> getExamHistoryStream() {
    if (studentId == null || studentId!.isEmpty) {
      // return empty stream if no studentId yet
      return Stream.value([]);
    }

    final examResultsRef = FirebaseFirestore.instance.collection("examResults");

    return examResultsRef.snapshots().asyncMap((snapshot) async {
      final results = <ExamHistoryModel>[];
      for (var doc in snapshot.docs) {
        final resultSnap = await examResultsRef
            .doc(doc.id)
            .collection(studentId!)
            .doc("result")
            .get();
        if (resultSnap.exists) {
          results.add(ExamHistoryModel.fromDoc(resultSnap, doc.id));
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Column(
          children: [
            // Top block title
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade700,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
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
                          Text("No exam history found"),
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
