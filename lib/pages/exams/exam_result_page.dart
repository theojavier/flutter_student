import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExamResultPage extends StatelessWidget {
  final String examId;
  final String studentId;
  final bool fromExamPage; // optional flag

  const ExamResultPage({
    super.key,
    required this.examId,
    required this.studentId,
    this.fromExamPage = false,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return WillPopScope(
      onWillPop: () async {
        // allow navigation back if from exam page, otherwise block
        return fromExamPage;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: fromExamPage, // show back only if coming from exam
          title: const Text("Exam Result"),
        ),
        body: FutureBuilder<DocumentSnapshot>(
          future: db
              .collection("examResults")
              .doc(examId)
              .collection(studentId)
              .doc("result")
              .get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.data!.exists) {
              return const Center(child: Text("Result not found"));
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final score = data["score"] ?? 0;
            final total = data["total"] ?? 0;

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Score: $score / $total",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Scrollable answers list
                  Expanded(
                    child: FutureBuilder<QuerySnapshot>(
                      future: db
                          .collection("examResults")
                          .doc(examId)
                          .collection(studentId)
                          .doc("result")
                          .collection("answers")
                          .get(),
                      builder: (context, ansSnap) {
                        if (!ansSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final answers = ansSnap.data!.docs;

                        if (answers.isEmpty) {
                          return const Center(child: Text("No answers found"));
                        }

                        // Sort by displayIndex to match exam order
                        answers.sort((a, b) {
                          final aData = a.data() as Map<String, dynamic>;
                          final bData = b.data() as Map<String, dynamic>;
                          final aIndex = aData["displayIndex"] ?? 0;
                          final bIndex = bData["displayIndex"] ?? 0;
                          return aIndex.compareTo(bIndex);
                        });

                        return ListView.builder(
                          itemCount: answers.length,
                          itemBuilder: (context, index) {
                            final a = answers[index];
                            final aData = a.data() as Map<String, dynamic>;

                            final question = aData["question"] ?? "Question";
                            final answer = aData["answer"] ?? "";
                            final correct = aData["correctAnswer"];

                            // Determine color
                            Color color;
                            if (correct != null) {
                              if (correct is List) {
                                color = correct
                                        .map((c) => c.toString().toLowerCase())
                                        .contains(answer.toLowerCase())
                                    ? Colors.green
                                    : Colors.red;
                              } else {
                                color = (answer.toLowerCase() ==
                                        correct.toString().toLowerCase())
                                    ? Colors.green
                                    : Colors.red;
                              }
                            } else {
                              color = Colors.black;
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "Q: $question\nYour Answer: $answer\nCorrect Answer: $correct",
                                style: TextStyle(fontSize: 16, color: color),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
