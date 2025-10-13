import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studentId = prefs.getString("studentId");
      program = prefs.getString("program");
      yearBlock = prefs.getString("yearBlock");
    });
  }

  /// Given the exam documents, fetch the student's result for each exam in parallel,
  /// then compute schedule/results/completed/upcoming counts.
  Future<Map<String, dynamic>> _processExamsWithResults(
      List<QueryDocumentSnapshot> examDocs) async {
    final now = DateTime.now();

    // parallel fetch of result docs for this student
    final futures = examDocs.map((examDoc) async {
      final data = examDoc.data() as Map<String, dynamic>;
      final examId = examDoc.id;
      final startTime = _toDate(data["startTime"]);

      // read student's result (may not exist)
      final resultSnap = await db
          .collection("examResults")
          .doc(examId)
          .collection(studentId!)
          .doc("result")
          .get();

      final rData = resultSnap.exists ? resultSnap.data() as Map<String, dynamic> : null;

      return {
        "doc": examDoc,
        "data": data,
        "startTime": startTime,
        "rData": rData,
      };
    }).toList();

    final items = await Future.wait(futures);

    // process
    List<QueryDocumentSnapshot> schedule = [];
    List<Map<String, dynamic>> results = [];
    int completedCount = 0;
    int upcomingCount = 0;

    for (var item in items) {
      final data = item["data"] as Map<String, dynamic>;
      final startTime = item["startTime"] as DateTime?;
      final rData = item["rData"] as Map<String, dynamic>?;

      if (rData != null && rData["status"] == "completed") {
        completedCount++;
        results.add({
          "subject": data["subject"] ?? "—",
          "score": rData["score"] ?? "—",
          "status": rData["status"] ?? "completed",
        });
      } else {
        // either no student result yet, or not completed
        if (startTime != null && startTime.isAfter(now)) {
          upcomingCount++;
          schedule.add(item["doc"] as QueryDocumentSnapshot);
        }
      }
    }

    return {
      "upcomingCount": upcomingCount,
      "completedCount": completedCount,
      "schedule": schedule,
      "results": results,
    };
  }

  @override
  Widget build(BuildContext context) {
    // still show spinner while prefs load
    if (studentId == null || program == null || yearBlock == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
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

          final examDocs = examsSnapshot.data!.docs;

          // Now fetch per-exam student results in parallel and build UI after that completes
          return FutureBuilder<Map<String, dynamic>>(
            future: _processExamsWithResults(examDocs),
            builder: (context, processedSnapshot) {
              if (processedSnapshot.connectionState == ConnectionState.waiting) {
                // show skeleton while per-exam reads are happening
                return _buildSkeletonUI();
              }
              if (processedSnapshot.hasError) {
                return Scaffold(
                  body: Center(child: Text('Error: ${processedSnapshot.error}')),
                );
              }

              final data = processedSnapshot.data!;
              final schedule = data["schedule"] as List<QueryDocumentSnapshot>;
              final results = data["results"] as List<Map<String, dynamic>>;
              final upcomingCount = data["upcomingCount"] as int;
              final completedCount = data["completedCount"] as int;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _infoCard(),
                    const SizedBox(height: 8),
                    const Text(
                      "Track, Plan, and Achieve Your Goals",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.black54),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Dashboard",
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _dashboardCard(
                            title: "Upcoming Exams",
                            count: upcomingCount,
                            color: Colors.green,
                            countColor: Colors.blue,
                          ),
                        ),
                        Expanded(
                          child: _dashboardCard(
                            title: "Completed Exams",
                            count: completedCount,
                            color: Colors.blue,
                            countColor: Colors.green,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text("Exam Schedule",
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    _buildScheduleTable(schedule),
                    const SizedBox(height: 16),
                    const Text("Results",
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  // ---------------- UI helpers (same structure you used before) ----------------

  Widget _buildSkeletonUI() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.grey[300],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
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
        ]),
        const SizedBox(height: 16),
        Container(height: 120, color: Colors.grey[200]),
        const SizedBox(height: 16),
        Container(height: 120, color: Colors.grey[200]),
      ]),
    );
  }

  Widget _infoCard() {
    return Card(
      color: Colors.orange,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Image.asset(
            "assets/image/istockphoto_1401106927_612x612_removebg_preview.png",
            height: 120,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 8),
          const Text("Welcome to Progress",
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: Colors.black)),
        ]),
      ),
    );
  }

  Widget _dashboardCard({
    required String title,
    required int count,
    required Color color,
    required Color countColor,
  }) {
    return Card(
      color: color,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 4,
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
          const SizedBox(height: 8),
          Text(count.toString(),
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: countColor)),
        ]),
      ),
    );
  }

 Widget _buildScheduleTable(List<QueryDocumentSnapshot> exams) {
  if (exams.isEmpty) {
    return const Center(child: Text("No exam schedule found"));
  }

  // 🔹 Sort by startTime (newest first)
  exams.sort((a, b) {
    final aTime = _toDate((a.data() as Map<String, dynamic>)["startTime"]) ?? DateTime(0);
    final bTime = _toDate((b.data() as Map<String, dynamic>)["startTime"]) ?? DateTime(0);
    return bTime.compareTo(aTime);
  });

  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(8),
    child: ConstrainedBox(
      // 👈 height for about 5 rows
      constraints: const BoxConstraints(maxHeight: 400),
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.symmetric(inside: const BorderSide(color: Colors.grey)),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
            3: FlexColumnWidth(2),
          },
          children: [
            const TableRow(
              decoration: BoxDecoration(color: Colors.black12),
              children: [
                Padding(padding: EdgeInsets.all(8), child: Text("Subject", style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text("Date", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text("Time", style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text("Status", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...exams.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final startTime = _toDate(data["startTime"]);
              String dateText = "—";
              String timeText = "—";

              if (startTime != null) {
                dateText = "${startTime.year}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}";
                timeText = "${startTime.hour % 12 == 0 ? 12 : startTime.hour % 12}:${startTime.minute.toString().padLeft(2, '0')} ${startTime.hour >= 12 ? 'PM' : 'AM'}";
              }

              return TableRow(children: [
                Padding(padding: const EdgeInsets.all(8), child: Text(data["subject"] ?? "—")),
                Padding(padding: const EdgeInsets.all(8), child: Text(dateText, textAlign: TextAlign.center)),
                Padding(padding: const EdgeInsets.all(8), child: Text(timeText)),
                Padding(padding: const EdgeInsets.all(8), child: Text(data["status"] ?? "—", style: const TextStyle(color: Colors.blue))),
              ]);
            }),
          ],
        ),
      ),
    ),
  );
}

Widget _buildResultsTable(List<Map<String, dynamic>> results) {
  if (results.isEmpty) {
    return const Center(child: Text("No results found"));
  }

  // 🔹 Sort by examDate (newest first) if available
  results.sort((a, b) {
    final aTime = _toDate(a["examDate"]) ?? DateTime(0);
    final bTime = _toDate(b["examDate"]) ?? DateTime(0);
    return bTime.compareTo(aTime);
  });

  return Card(
    elevation: 2,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    margin: const EdgeInsets.all(8),
    child: ConstrainedBox(
      // 👈 height for about 5 rows
      constraints: const BoxConstraints(maxHeight: 400),
      child: SingleChildScrollView(
        child: Table(
          border: TableBorder.symmetric(inside: const BorderSide(color: Colors.grey)),
          columnWidths: const {
            0: FlexColumnWidth(2),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(2),
          },
          children: [
            const TableRow(
              decoration: BoxDecoration(color: Colors.black12),
              children: [
                Padding(padding: EdgeInsets.all(8), child: Text("Subject", style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text("Score", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                Padding(padding: EdgeInsets.all(8), child: Text("Status", style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ...results.map((data) {
              return TableRow(children: [
                Padding(padding: const EdgeInsets.all(8), child: Text(data["subject"] ?? "—")),
                Padding(padding: const EdgeInsets.all(8), child: Text((data["score"] ?? "—").toString(), textAlign: TextAlign.center)),
                Padding(padding: const EdgeInsets.all(8), child: Text(data["status"] ?? "—", style: const TextStyle(color: Colors.green))),
              ]);
            }),
          ],
        ),
      ),
    ),
  );
  }
}
