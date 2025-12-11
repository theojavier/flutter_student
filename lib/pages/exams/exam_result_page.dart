import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
//import 'dart:html' as html;

class ExamResultPage extends StatefulWidget {
  final String examId;
  //final String studentId;
  //final bool fromExamPage;

  const ExamResultPage({
    super.key,
    required this.examId,
    //required this.studentId,
    //this.fromExamPage = false,
  });

  @override
  State<ExamResultPage> createState() => _ExamResultPageState();
}

class _ExamResultPageState extends State<ExamResultPage> {
  //StreamSubscription<html.PopStateEvent>? _popSub;
  Future<String?> fetchStudentId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .get();

    if (!doc.exists) return null;

    return doc.data()?["studentId"];
  }

  @override
  void initState() {
    super.initState();

    // if (kIsWeb && widget.fromExamPage) {
    //   // Push a new browser state so pressing back won't immediately navigate away
    //   html.window.history.replaceState(
    //     {'locked': true},
    //     "Result",
    //     html.window.location.href,
    //   );

    //   // Listen for browser back button
    //   _popSub = html.window.onPopState.listen((event) {
    //     final stateData = event.state;

    //     // Only block if our custom lock state exists
    //     if (stateData is Map && stateData['locked'] == true) {
    //       // Re-push same state to keep browser from leaving
    //       html.window.history.replaceState(
    //         {'locked': true},
    //         "Result",
    //         html.window.location.href,
    //       );

    //       // Show the snack message
    //       ScaffoldMessenger.of(context).showSnackBar(
    //         const SnackBar(
    //           content: Text(
    //             "Back navigation is disabled after submitting the exam.",
    //           ),
    //           duration: Duration(seconds: 2),
    //         ),
    //       );
    //     }
    //   });
    // }
  }

  @override
  void dispose() {
    //_popSub?.cancel();
    super.dispose();
  }

  //  Grading colors based on adjusted scale
  Color _getColor(double percent) {
    if (percent >= 80) return Colors.green;
    if (percent >= 75) return Colors.orange;
    return Colors.red;
  }

  String _getMark(double percent) {
    if (percent >= 75) return "Passed!";
    return "Failed!";
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return WillPopScope(
      onWillPop: () async => true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: FutureBuilder<String?>(
          future: fetchStudentId(),
          builder: (context, studentSnapshot) {
            if (!studentSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final studentId = studentSnapshot.data;
            if (studentId == null) {
              return const Center(child: Text("Student not found"));
            }

            return FutureBuilder<DocumentSnapshot>(
              future: db
                  .collection("examResults")
                  .doc(widget.examId)
                  .collection("students")
                  .doc(studentId)
                  .get(),

              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.data!.exists) {
                  return const Center(child: Text("Result not found"));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final score = (data["score"] ?? 0).toDouble();
                final total = (data["total"] ?? 0).toDouble();
                final studentIdFromResult =
                    data["studentId"] ?? "Unknown studentId";
                final subjectFromResult = data["subject"] ?? "Unknown Subject";

                // Adjusted percent
                double rawPercent = total > 0 ? (score / total) * 100 : 0;
                double adjustedPercent = 50 + (rawPercent / 2);
                adjustedPercent = adjustedPercent.clamp(0, 100);

                final color = _getColor(adjustedPercent);
                final mark = _getMark(adjustedPercent);

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Dynamic Header Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            "Exam Result",
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Exam Info
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F2B45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Subject: $subjectFromResult",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE6F0F8),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Student ID :  $studentIdFromResult",
                              style: const TextStyle(
                                fontSize: 15,
                                color: Color(0xFFE6F0F8),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Score Summary Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F2B45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "Your examination score is $score / $total",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE6F0F8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "${adjustedPercent.toStringAsFixed(2)} %",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              "Equivalent Grade",
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFFE6F0F8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Mark: $mark",
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
