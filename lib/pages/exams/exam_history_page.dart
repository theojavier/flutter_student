import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

import '../../models/exam_history_model.dart';
import '../../widgets/exam_history_item.dart';

class ExamHistoryPage extends StatelessWidget {
  final String studentId;
  const ExamHistoryPage({super.key, required this.studentId});

  @override
  Widget build(BuildContext context) {
    final examResultsRef = FirebaseFirestore.instance.collection("examResults");

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Exam History"),
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: examResultsRef.get(const GetOptions(source: Source.serverAndCache)),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
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

          final parentDocs = snapshot.data!.docs;

          // Collect all results into a list of futures
          return FutureBuilder<List<ExamHistoryModel>>(
            future: Future.wait(
              parentDocs.map((examDoc) async {
                final resultSnap = await examResultsRef
                    .doc(examDoc.id)
                    .collection(studentId)
                    .doc("result")
                    .get();

                if (!resultSnap.exists) return null;
                return ExamHistoryModel.fromDoc(resultSnap, examDoc.id);
              }).toList(),
            ).then((list) => list.whereType<ExamHistoryModel>().toList()),
            builder: (context, resultsSnap) {
              if (resultsSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (resultsSnap.hasError) {
                return Center(child: Text("Error: ${resultsSnap.error}"));
              }
              if (!resultsSnap.hasData || resultsSnap.data!.isEmpty) {
                return const Center(child: Text("No exam history found"));
              }

              final exams = resultsSnap.data!;

              // Sort newest first
              exams.sort((a, b) {
                final aTime = a.submittedAt?.toDate() ?? DateTime(1970);
                final bTime = b.submittedAt?.toDate() ?? DateTime(1970);
                return bTime.compareTo(aTime);
              });

              return ListView.builder(
                itemCount: exams.length,
                itemBuilder: (context, index) {
                  final exam = exams[index];

                  return ExamHistoryItem(
                    exam: exam,
                    onTap: () {
                      context.push(
                        '/take-exam',
                        extra: {
                          "examId": exam.id,
                          "subject": exam.subject,
                          "score": exam.score,
                          "total": exam.total,
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
