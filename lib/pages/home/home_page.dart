import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

/// convert Firestore field to DateTime safely
DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

class _HomePageState extends State<HomePage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  String? studentId;
  String? program;
  String? yearBlock;
  String? _authUid;

  @override
  void initState() {
    super.initState();

    _authUid = FirebaseAuth.instance.currentUser?.uid;
    if (_authUid == null) return;

    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      program = prefs.getString("program");
      yearBlock = prefs.getString("yearBlock");
    });
  }

  Future<Map<String, dynamic>> _processExamsAndResults() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    //Exams schedule
    final examsSnap = await db
        .collection("exams")
        .where("program", isEqualTo: program)
        .where("yearBlock", isEqualTo: yearBlock)
        .get();

    List<QueryDocumentSnapshot> todaysSchedule = [];
    int todayExamCount = 0;

    for (final examDoc in examsSnap.docs) {
      final data = examDoc.data();
      final startTime = _toDate(data["startTime"]);

      if (startTime != null) {
        final examDay = DateTime(
          startTime.year,
          startTime.month,
          startTime.day,
        );
        if (examDay == today) {
          todayExamCount++;
          todaysSchedule.add(examDoc);
        }
      }
    }

    //Student results 
    final examResultsSnap = await db
        .collection("examResults")
        .where("program", isEqualTo: program)
        .where("yearBlock", isEqualTo: yearBlock)
        .get();

    List<Map<String, dynamic>> results = [];
    int completedCount = 0;

    for (final examResultDoc in examResultsSnap.docs) {
      final studentSnap = await examResultDoc.reference
          .collection("students")
          .doc(_authUid!)
          .get();

      if (studentSnap.exists) {
        final rData = studentSnap.data() as Map<String, dynamic>;
        final status = rData["status"] ?? "incomplete";
        final score = rData["score"] ?? "—";
        final submittedAt = _toDate(rData["submittedAt"]);

        if (status == "completed") {
          completedCount++;
        }

        results.add({
          "subject":
              rData["subject"] ?? "—", // subject stored in student result
          "score": score,
          "status": status,
          "submittedAt": submittedAt,
        });
      }
    }

    // Sort results by submittedAt (newest first)
    results.sort((a, b) {
      final aTime = a["submittedAt"] ?? DateTime(1970);
      final bTime = b["submittedAt"] ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });

    return {
      "todayExamCount": todayExamCount,
      "completedCount": completedCount,
      "schedule": todaysSchedule, // sorted by startTime 
      "results": results, // sorted by submittedAt 
    };
  }

  @override
  Widget build(BuildContext context) {
    // still show spin while prefs load
    if (_authUid == null || program == null || yearBlock == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection("exams")
            .where("program", isEqualTo: program)
            .where("yearBlock", isEqualTo: yearBlock)
            .snapshots(),
        builder: (context, examsSnapshot) {
          // show skeleton while exams list loads
          if (!examsSnapshot.hasData) {
            return _buildSkeletonUI();
          }
          // Now fetch per-exam student results in 
          return FutureBuilder<Map<String, dynamic>>(
            future: _processExamsAndResults(),
            builder: (context, processedSnapshot) {
              if (processedSnapshot.connectionState ==
                  ConnectionState.waiting) {
                // show skeleton while per-exam reads are happening
                return _buildSkeletonUI();
              }
              if (processedSnapshot.hasError) {
                return Scaffold(
                  body: Center(
                    child: Text('Error: ${processedSnapshot.error}'),
                  ),
                );
              }

              final data = processedSnapshot.data!;
              final schedule = data["schedule"] as List<QueryDocumentSnapshot>;
              final results = data["results"] as List<Map<String, dynamic>>;
              final todayExamCount = data["todayExamCount"] as int;
              final completedCount = data["completedCount"] as int;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoCard(),
                    const SizedBox(height: 8),
                    const Text(
                      "Track,Monitor, and Eye opener",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Dashboard",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 150,
                            child: _dashboardCard(
                              title: "Today's Exams",
                              count: todayExamCount,
                              color: Colors.blue,
                              countColor: Color(0xFFE6F0F8),
                            ),
                          ),
                        ),
                        Expanded(
                          child: SizedBox(
                            height: 150,
                            child: _dashboardCard(
                              title: "Completed Exams",
                              count: completedCount,
                              color: Colors.green,
                              countColor: Color(0xFFE6F0F8),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      "Exam Schedule for today",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE6F0F8),
                      ),
                    ),
                    _buildScheduleTable(schedule),
                    const SizedBox(height: 16),
                    const Text(
                      "Results",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE6F0F8),
                      ),
                    ),
                    _buildResultsTable(results),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // UI helpers

  Widget _buildSkeletonUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 80,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 80,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 120, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Container(height: 120, color: Colors.grey[200]),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Card(
      color: Color(0xFF0F2B45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Image.asset(
              'assets/image/fots_student.png',
              height: 200,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                "Welcome to tot Student Application",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width < 360 ? 22 : 30,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE6F0F8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardCard({
    required String title,
    required int count,
    required Color color,
    required Color countColor,
    TextStyle? titleStyle, 
  }) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                double width = constraints.maxWidth;

                double fontSize = width < 150 ? 12 : 16;

                return Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      titleStyle ??
                      TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE6F0F8),
                      ),
                );
              },
            ),

            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: countColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleTable(List<QueryDocumentSnapshot> exams) {
    if (exams.isEmpty) {
      return Card(
        color: const Color(0xFF0F2B45),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.info_outline, color: Color(0xFFE6F0F8), size: 35),
              SizedBox(height: 12),
              Text(
                "No exam schedule found",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE6F0F8),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Sort by startTime (earliest first)
    exams.sort((a, b) {
      final aTime =
          _toDate((a.data() as Map<String, dynamic>)["startTime"]) ??
          DateTime(9999);
      final bTime =
          _toDate((b.data() as Map<String, dynamic>)["startTime"]) ??
          DateTime(9999);

      return aTime.compareTo(bTime);
    });

    return Card(
      color: Color(0xFF0F2B45),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 350),
        child: SingleChildScrollView(
          child: ClipRRect(
            child: Table(
              border: TableBorder.all(color: Color(0xFF0F2B45), width: 1),
              columnWidths: const {
                0: FlexColumnWidth(2), // Subject
                1: FlexColumnWidth(2), // Date
                2: FlexColumnWidth(2), // Time
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Colors.black12),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        "Subject",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE6F0F8),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        "Date",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE6F0F8),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        "Start",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE6F0F8),
                        ),
                      ),
                    ),
                  ],
                ),
                ...exams.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final startTime = _toDate(data["startTime"]);
                  String dateText = "—";
                  String timeText = "—";

                  if (startTime != null) {
                    dateText =
                        "${startTime.year}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}";
                    timeText =
                        "${startTime.hour % 12 == 0 ? 12 : startTime.hour % 12}:${startTime.minute.toString().padLeft(2, '0')} ${startTime.hour >= 12 ? 'PM' : 'AM'}";
                  }

                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          data["subject"] ?? "—",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE6F0F8)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          dateText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE6F0F8)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          timeText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE6F0F8)),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsTable(List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return Card(
        color: const Color(0xFF0F2B45),
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(8),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.assignment_turned_in_outlined,
                color: Color(0xFFE6F0F8),
                size: 35,
              ),
              SizedBox(height: 12),
              Text(
                "No results found",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFE6F0F8),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }


    return Card(
      color: const Color(0xFF0F2B45),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(8),
      child: ConstrainedBox(
        //  height for about 5 rows
        constraints: const BoxConstraints(maxHeight: 400),
        child: SingleChildScrollView(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Table(
              border: TableBorder.all(color: Color(0xFF0F2B45), width: 1),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
              },
              children: [
                const TableRow(
                  decoration: BoxDecoration(color: Colors.black12),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        "Subject",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE6F0F8),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        "Score",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE6F0F8),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        "Status",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE6F0F8),
                        ),
                      ),
                    ),
                  ],
                ),
                ...results.map((data) {
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          data["subject"] ?? "—",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE6F0F8)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          (data["score"] ?? "—").toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFE6F0F8)),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          data["status"] ?? "—",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: (data["status"] == "completed")
                                ? Colors.green
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
