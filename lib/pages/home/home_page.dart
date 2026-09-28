import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../helpers/SecureStorageHelper.dart';

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
  // Shared theme palette (same as ProfilePage / LoginPage / SchedulePage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _successColor = Color(0xFF4ADE80);
  static const Color _errorColor = Color(0xFFF87171);

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
    final storedStudentId = await SecureStorageHelper.read('studentId');
    final storedProgram = await SecureStorageHelper.read('program');
    final storedYearBlock = await SecureStorageHelper.read('yearBlock');

    if (!mounted) return;
    setState(() {
      studentId = storedStudentId;
      program = storedProgram;
      yearBlock = storedYearBlock;
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

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    // still show spin while prefs load
    if (_authUid == null || program == null || yearBlock == null) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
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
          // Now fetch per-exam student results
          return FutureBuilder<Map<String, dynamic>>(
            future: _processExamsAndResults(),
            builder: (context, processedSnapshot) {
              if (processedSnapshot.connectionState ==
                  ConnectionState.waiting) {
                // show skeleton while per-exam reads are happening
                return _buildSkeletonUI();
              }
              if (processedSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error: ${processedSnapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _errorColor),
                    ),
                  ),
                );
              }

              final data = processedSnapshot.data!;
              final schedule = data["schedule"] as List<QueryDocumentSnapshot>;
              final results = data["results"] as List<Map<String, dynamic>>;
              final todayExamCount = data["todayExamCount"] as int;
              final completedCount = data["completedCount"] as int;

              // Hides scrollbars everywhere on this page (scrolling still works)
              return ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(
                  scrollbars: false,
                  overscroll: false,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _infoCard(),
                      const SizedBox(height: 22),

                      _sectionHeader(Icons.dashboard_outlined, "Dashboard"),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              icon: Icons.event_available_outlined,
                              title: "Today's Exams",
                              count: todayExamCount,
                              color: _accentColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _statCard(
                              icon: Icons.check_circle_outline,
                              title: "Completed Exams",
                              count: completedCount,
                              color: _successColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      _sectionHeader(
                        Icons.event_note_outlined,
                        "Exam Schedule for Today",
                      ),
                      _buildScheduleTable(schedule),
                      const SizedBox(height: 22),

                      _sectionHeader(
                        Icons.assignment_turned_in_outlined,
                        "Results",
                      ),
                      _buildResultsTable(results),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ---------- UI helpers ----------

  // Same card look as the Profile page's standalone cards
  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_cardColor.withOpacity(0.9), _cardColor.withOpacity(0.55)],
      ),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  // Icon chip + title + divider line (same as Profile section headers)
  Widget _sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: _accentColor),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: _textColor,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonUI() {
    Widget block(double height, {double radius = 18}) => Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        children: [
          block(230, radius: 24),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: block(120)),
              const SizedBox(width: 12),
              Expanded(child: block(120)),
            ],
          ),
          const SizedBox(height: 22),
          block(140),
          const SizedBox(height: 22),
          block(140),
        ],
      ),
    );
  }

  // Hero card: framed logo + welcome text (like the Profile avatar zone)
  Widget _infoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accentColor.withOpacity(0.9),
                  _accentColor.withOpacity(0.25),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(23),
              child: Container(
                color: _cardColor,
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/image/Fots.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            "Welcome to tot Student Application",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: MediaQuery.of(context).size.width < 360 ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              "TRACK, MONITOR, AND EYE OPENER",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: _mutedTextColor),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _accentColor, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _mutedTextColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, {Color color = _textColor, FontWeight? weight}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontSize: 13, fontWeight: weight),
      ),
    );
  }

  // Shared table card: dark header strip, subtly shaded alternate rows
  Widget _tableCard({
    required List<String> headers,
    required List<List<Widget>> rows,
    required Map<int, TableColumnWidth> columnWidths,
    required double maxHeight,
  }) {
    return Container(
      decoration: _cardDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: columnWidths,
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: Colors.white.withOpacity(0.06),
                ),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.22),
                  ),
                  children: [
                    for (final h in headers)
                      _cell(h, weight: FontWeight.bold),
                  ],
                ),
                for (int i = 0; i < rows.length; i++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: i.isOdd
                          ? Colors.white.withOpacity(0.03)
                          : Colors.transparent,
                    ),
                    children: rows[i],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleTable(List<QueryDocumentSnapshot> exams) {
    if (exams.isEmpty) {
      return _emptyCard(Icons.info_outline, "No exam schedule found");
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

    final rows = exams.map((doc) {
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

      return <Widget>[
        _cell((data["subject"] ?? "—").toString()),
        _cell(dateText, color: _mutedTextColor),
        _cell(timeText, weight: FontWeight.w600),
      ];
    }).toList();

    return _tableCard(
      headers: const ["Subject", "Date", "Start"],
      rows: rows,
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(2.2),
        2: FlexColumnWidth(2),
      },
      maxHeight: 350,
    );
  }

  Widget _statusChip(String status) {
    final completed = status == "completed";
    final color = completed ? _successColor : _errorColor;
    final label = status.isEmpty
        ? "—"
        : status[0].toUpperCase() + status.substring(1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsTable(List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return _emptyCard(
        Icons.assignment_turned_in_outlined,
        "No results found",
      );
    }

    final rows = results.map((data) {
      return <Widget>[
        _cell((data["subject"] ?? "—").toString()),
        _cell((data["score"] ?? "—").toString(), weight: FontWeight.w600),
        _statusChip((data["status"] ?? "—").toString()),
      ];
    }).toList();

    return _tableCard(
      headers: const ["Subject", "Score", "Status"],
      rows: rows,
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(1.6),
        2: FlexColumnWidth(2.2),
      },
      maxHeight: 400,
    );
  }
}