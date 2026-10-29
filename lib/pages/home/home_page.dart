import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../../helpers/SecureStorageHelper.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

class _HomePageState extends State<HomePage> {
  // ============================================================
  // FOTS EDITORIAL PALETTE
  // ============================================================

  static const Color _bg = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _accent = Color(0xFF087B4F);
  static const Color _accentDark = Color(0xFF075C3C);
  static const Color _accentSoft = Color(0xFFE8F5EB);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _muted2 = Color(0xFF8A8D91);
  static const Color _danger = Color(0xFFCB354B);
  static const Color _dangerSoft = Color(0xFFFFF1F3);
  static const String _mono = 'monospace';

  final FirebaseFirestore db = FirebaseFirestore.instance;

  String? studentId;
  String? program;
  String? programCode;
  String? yearBlock;
  String? _authUid;
  String? _prefsError;

  @override
  void initState() {
    super.initState();

    _authUid = FirebaseAuth.instance.currentUser?.uid;

    if (_authUid != null) {
      _loadPrefs();
    }
  }

  Future<void> _loadPrefs() async {
    final authUid = _authUid;
    if (authUid == null) {
      throw StateError(
        'A signed-in student is required to load the dashboard.',
      );
    }

    final storedStudentId = await SecureStorageHelper.read('studentId');

    final storedProgram = await SecureStorageHelper.read('program');

    final storedProgramCode = await SecureStorageHelper.read('programCode');

    final storedYearBlock = await SecureStorageHelper.read('yearBlock');

    DocumentSnapshot<Map<String, dynamic>> profile;
    try {
      profile = await db.collection('users').doc(authUid).get();
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _prefsError = error.message ?? 'Unable to load your student profile.';
      });
      return;
    }

    final profileProgramCode = (profile.data()?['programCode'] ?? '')
        .toString()
        .trim();
    final savedProgramCode = (storedProgramCode ?? '').trim();

    if (!mounted) return;

    setState(() {
      studentId = storedStudentId;
      program = storedProgram;
      programCode = profileProgramCode.isNotEmpty
          ? profileProgramCode
          : savedProgramCode.isNotEmpty
          ? savedProgramCode
          : null;
      yearBlock = storedYearBlock;
    });
  }

  // ============================================================
  // FIRESTORE DATA
  // ============================================================

  Future<Map<String, dynamic>> _loadDashboardData() async {
    final now = DateTime.now();

    // ------------------------------------------------------------
    // EXAMS
    // ------------------------------------------------------------

    final examsSnap = await db
        .collection("exams")
        .where(
          "program",
          isEqualTo: programCode?.isNotEmpty == true ? programCode : program,
        )
        .where("yearBlock", isEqualTo: yearBlock)
        .get();

    final List<QueryDocumentSnapshot> upcomingExams = [];

    for (final examDoc in examsSnap.docs) {
      final data = examDoc.data();

      final startTime = _toDate(data["startTime"]);
      final endTime = _toDate(data["endTime"]);
      final notEnded = endTime == null || endTime.isAfter(now);

      if (startTime != null && startTime.isAfter(now) && notEnded) {
        upcomingExams.add(examDoc);
      }
    }

    upcomingExams.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>;
      final bData = b.data() as Map<String, dynamic>;

      final aTime = _toDate(aData["startTime"]) ?? DateTime(9999);

      final bTime = _toDate(bData["startTime"]) ?? DateTime(9999);

      return aTime.compareTo(bTime);
    });

    // ------------------------------------------------------------
    // RESULTS
    // ------------------------------------------------------------

    final examResultsSnap = await db.collection("examResults").get();

    final List<Map<String, dynamic>> results = [];

    int completedCount = 0;

    final authUid = _authUid;
    if (authUid == null) {
      throw StateError('A signed-in student is required to load exam results.');
    }

    for (final examResultDoc in examResultsSnap.docs) {
      final studentSnap = await examResultDoc.reference
          .collection("students")
          .doc(authUid)
          .get();

      if (!studentSnap.exists) continue;

      final data = studentSnap.data() as Map<String, dynamic>;

      final status = (data["status"] ?? "incomplete").toString();

      final score = data["score"] ?? "—";

      final submittedAt = _toDate(data["submittedAt"]);

      if (status == "completed") {
        completedCount++;
      }

      results.add({
        "subject": data["subject"] ?? "—",
        "score": score,
        "status": status,
        "submittedAt": submittedAt,
        "total": data["total"] ?? "—",
        "examId": data["examId"] ?? examResultDoc.id,
      });
    }

    results.sort((a, b) {
      final aTime = a["submittedAt"] ?? DateTime(1970);

      final bTime = b["submittedAt"] ?? DateTime(1970);

      return bTime.compareTo(aTime);
    });

    // ------------------------------------------------------------
    // READINESS
    // ------------------------------------------------------------

    final bool accountReady =
        _authUid != null &&
        studentId?.isNotEmpty == true &&
        (program?.isNotEmpty == true || programCode?.isNotEmpty == true) &&
        yearBlock?.isNotEmpty == true;

    final int readiness = accountReady ? 100 : 0;

    return {
      "availableExams": upcomingExams.length,
      "completedCount": completedCount,
      "upcomingExams": upcomingExams,
      "results": results,
      "readiness": readiness,
      "strikes": 0,
      "ready": accountReady,
    };
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_prefsError != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Text(
            'Error: $_prefsError',
            style: const TextStyle(color: _danger),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_authUid == null ||
        (program?.isNotEmpty != true && programCode?.isNotEmpty != true) ||
        yearBlock?.isNotEmpty != true) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    return Scaffold(
      backgroundColor: _bg,

      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadDashboardData(),

        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildSkeletonUI();
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error: ${snapshot.error}",
                style: const TextStyle(color: _danger),
              ),
            );
          }

          final data = snapshot.data!;

          final int availableExams = data["availableExams"] as int;

          final int completedCount = data["completedCount"] as int;

          final int readiness = data["readiness"] as int;

          final int strikes = data["strikes"] as int;

          final bool ready = data["ready"] as bool;

          final List<QueryDocumentSnapshot> upcomingExams =
              data["upcomingExams"] as List<QueryDocumentSnapshot>;

          final List<Map<String, dynamic>> results =
              data["results"] as List<Map<String, dynamic>>;

          return SafeArea(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false, overscroll: false),

              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),

                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1250),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,

                      children: [
                        // ==================================================
                        // HEADER
                        // ==================================================

                        _pageHead(),

                        const SizedBox(height: 22),

                        // ==================================================
                        // HERO
                        // ==================================================
                        _hero(),

                        const SizedBox(height: 16),

                        // ==================================================
                        // FOUR STAT CARDS
                        // ==================================================
                        _statsGrid(
                          availableExams,
                          completedCount,
                          readiness,
                          strikes,
                        ),

                        const SizedBox(height: 16),

                        // ==================================================
                        // UPCOMING + READINESS
                        // ==================================================
                        _dashboardGrid(upcomingExams, readiness, ready),

                        const SizedBox(height: 30),

                        // ==================================================
                        // RESULTS
                        // ==================================================
                        _sectionHeader(
                          Icons.assignment_turned_in_outlined,
                          "Results",
                          "SECTION 02",
                        ),

                        _buildResultsTable(results),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================
  // TEXT STYLES
  // ============================================================

  TextStyle _monoStyle(double size, {Color color = _muted2}) {
    return TextStyle(
      fontFamily: _mono,
      fontSize: size,
      color: color,
      letterSpacing: 0.8,
      fontWeight: FontWeight.w500,
    );
  }

  TextStyle _display(double size, {Color color = _ink, double h = 1.0}) {
    return TextStyle(
      fontSize: size,
      height: h,
      color: color,
      fontWeight: FontWeight.w700,
      letterSpacing: -size * 0.05,
    );
  }

  BoxDecoration _cardBox({Color color = Colors.white, double radius = 10}) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _line),
    );
  }

  // ============================================================
  // PAGE HEADER
  // ============================================================

  Widget _pageHead() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text("FOTS / STUDENT WORKSPACE", style: _monoStyle(11, color: _accent)),

        const SizedBox(height: 10),

        Text("Overview.", style: _display(38, h: 1.08)),

        const SizedBox(height: 7),

        const Text(
          "See your upcoming exams, track your readiness and review your results.",
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  // ============================================================
  // HERO
  // ============================================================

  Widget _hero() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool wide = constraints.maxWidth >= 700;

        return Container(
          decoration: _cardBox(radius: 12),

          clipBehavior: Clip.antiAlias,

          child: wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,

                    children: [
                      Expanded(flex: 58, child: _heroCopy(wide)),

                      Expanded(flex: 42, child: _heroArt(wide)),
                    ],
                  ),
                )
              : Column(children: [_heroCopy(false), _heroArt(false)]),
        );
      },
    );
  }

  Widget _heroCopy(bool wide) {
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 30 : 22, 25, wide ? 30 : 22, 25),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: _accent),

              const SizedBox(width: 9),

              Expanded(
                child: Text(
                  "FOTS PLATFORM",
                  style: _monoStyle(10, color: _ink),
                ),
              ),

              Text("EDITION / 2026", style: _monoStyle(10)),
            ],
          ),

          const SizedBox(height: 15),

          const Divider(height: 1, color: _ink),

          SizedBox(height: wide ? 35 : 24),

          Text(
            "A BETTER WAY TO EXAMINE",
            style: _monoStyle(10, color: _accent),
          ),

          const SizedBox(height: 12),

          RichText(
            text: TextSpan(
              style: _display(wide ? 52 : 40, h: .98),

              children: const [
                TextSpan(text: "Stay focused.\n"),
                TextSpan(
                  text: "Students.",
                  style: TextStyle(color: _accent),
                ),
              ],
            ),
          ),

          const SizedBox(height: 15),

          const Text(
            "Your examination space, redesigned around clarity and confidence.",
            style: TextStyle(color: _muted, fontSize: 13, height: 1.65),
          ),

          const SizedBox(height: 24),

          const Divider(height: 1, color: _line),

          const SizedBox(height: 12),

          Row(
            children: [
              Text("01 / FOCUS ENGINE", style: _monoStyle(9, color: _ink)),

              const Spacer(),

              Text("STUDENT // HOME", style: _monoStyle(9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroArt(bool wide) {
    return Container(
      color: _ink,

      padding: const EdgeInsets.all(22),

      constraints: BoxConstraints(minHeight: wide ? 300 : 240),

      child: Column(
        children: [
          Row(
            children: [
              Text(
                "FOTS / STUDENT SPACE",
                style: _monoStyle(10, color: Colors.white70),
              ),

              const Spacer(),

              Text("[ LIVE ]", style: _monoStyle(10, color: Colors.white70)),
            ],
          ),

          const SizedBox(height: 14),

          const Divider(height: 1, color: Color(0xFF3A3C44)),

          SizedBox(height: wide ? 65 : 35),

          Align(
            alignment: Alignment.centerRight,

            child: Transform.rotate(
              angle: .08,

              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),

                color: _accent,

                child: Text(
                  "FACE ON\nTHE SCREEN.",
                  style: _display(wide ? 27 : 22, color: Colors.white, h: 1.05),
                ),
              ),
            ),
          ),

          SizedBox(height: wide ? 65 : 35),

          const Divider(height: 1, color: Color(0xFF3A3C44)),

          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,

            children: [
              Text(
                "FOCUS.",
                style: _display(wide ? 42 : 36, color: Colors.white, h: .9),
              ),

              const Spacer(),

              Text(
                "WITHOUT\nDISTRACTIONS.",
                textAlign: TextAlign.right,
                style: _monoStyle(9, color: Colors.white70),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // FOUR CARDS
  // ============================================================

  Widget _statsGrid(int available, int completed, int readiness, int strikes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool small = constraints.maxWidth < 700;

        final bool medium = constraints.maxWidth < 1000;

        final int columns = small
            ? 1
            : medium
            ? 2
            : 4;

        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: small ? 2.6 : 1.55,

          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),

          children: [
            _statCard(
              title: "Available exams",
              value: "$available",
              caption: "Upcoming sessions",
              icon: Icons.assignment_outlined,
              background: Colors.white,
            ),

            _statCard(
              title: "Completed",
              value: "$completed",
              caption: "This semester",
              icon: Icons.check_circle_outline,
              background: _ink,
              dark: true,
            ),

            _statCard(
              title: "Tracking readiness",
              value: "$readiness%",
              caption: "Account + session check",
              icon: Icons.track_changes_outlined,
              background: const Color(0xFFEFFBF5),
            ),

            _statCard(
              title: "Current strikes",
              value: "$strikes",
              caption: strikes == 0
                  ? "No active secure session"
                  : "Monitoring strikes",
              icon: Icons.priority_high_outlined,
              background: Colors.white,
              danger: strikes > 0,
            ),
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required String caption,
    required IconData icon,
    required Color background,
    bool dark = false,
    bool danger = false,
  }) {
    final Color foreground = dark ? Colors.white : _ink;

    final Color secondary = dark ? const Color(0xFFB0B1B7) : _muted2;

    final Color iconColor = danger ? _danger : _accent;

    return Container(
      padding: const EdgeInsets.all(18),

      decoration: _cardBox(
        color: background,
        radius: 9,
      ).copyWith(border: Border.all(color: dark ? _ink : _line)),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        mainAxisAlignment: MainAxisAlignment.spaceBetween,

        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _monoStyle(10, color: secondary),
                ),
              ),

              Container(
                width: 32,
                height: 32,

                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF333640) : _accentSoft,

                  borderRadius: BorderRadius.circular(6),
                ),

                child: Icon(icon, size: 17, color: iconColor),
              ),
            ],
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(value, style: _display(38, color: foreground, h: .95)),

              const SizedBox(height: 7),

              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // UPCOMING EXAMS + READINESS
  // ============================================================

  Widget _dashboardGrid(
    List<QueryDocumentSnapshot> exams,
    int readiness,
    bool ready,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 850) {
          return Column(
            children: [
              _upcomingExamsCard(exams),

              const SizedBox(height: 14),

              _readinessCard(readiness, ready),
            ],
          );
        }

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 7, child: _upcomingExamsCard(exams)),
              const SizedBox(width: 15),
              Expanded(flex: 3, child: _readinessCard(readiness, ready)),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // UPCOMING EXAMS
  // ============================================================

  Widget _upcomingExamsCard(List<QueryDocumentSnapshot> exams) {
    // Soonest 5 upcoming exams (list is already sorted by startTime)
    final visibleExams = exams.take(5).toList();

    return Container(
      clipBehavior: Clip.antiAlias,
      // White background: any space the rows don't use stays white
      decoration: _cardBox(color: Colors.white, radius: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(19, 17, 19, 15),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: _line)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Upcoming exams",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Closest deadlines and available sessions",
                        style: _monoStyle(9),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: _accentSoft,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: () => context.go('/exam-list'),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Text(
                        "VIEW ALL",
                        style: _monoStyle(9, color: _accent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ROWS
          for (final exam in visibleExams) _upcomingExamRow(exam),

          // Empty state (dark text now, since the background is white)
          if (visibleExams.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  "NO UPCOMING EXAMS",
                  style: _monoStyle(10, color: _muted2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _upcomingExamRow(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final String subject = (data["subject"] ?? "Untitled Exam").toString();

    final String course = (data["course"] ?? "Student Examination").toString();
    final classId = (data['classId'] ?? '').toString().trim();

    final DateTime? startTime = _toDate(data["startTime"]);

    final String dateText = startTime == null ? "—" : _formatDate(startTime);

    final String timeText = startTime == null ? "—" : _formatTime(startTime);

    final String duration = (data["duration"] ?? data["durationMinutes"] ?? "—")
        .toString();

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openUpcomingExam(doc),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      course,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _monoStyle(9),
                    ),
                    if (classId.isNotEmpty)
                      InkWell(
                        onTap: () => _openClass(classId),
                        child: Padding(
                          padding: const EdgeInsets.only(top: 5, right: 8),
                          child: Text(
                            'OPEN CLASS',
                            style: _monoStyle(8, color: _accent),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(timeText, maxLines: 1, style: _monoStyle(8)),
                  ],
                ),
              ),
              _statusPill("Available", Icons.circle),
              const SizedBox(width: 12),
              SizedBox(
                width: 55,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      duration == "—" ? "—" : "$duration min",
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text("Secure", style: _monoStyle(8)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // READINESS
  // ============================================================

  Widget _readinessCard(int readiness, bool ready) {
    return Container(
      decoration: _cardBox(radius: 9),

      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(19, 17, 19, 15),

            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _line)),
            ),

            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        "Readiness",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),

                      SizedBox(height: 4),

                      Text(
                        "Secure-exam environment",
                        style: TextStyle(
                          color: _muted2,
                          fontFamily: _mono,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),

                _statusPill(ready ? "Ready" : "Check", Icons.circle),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(22),

            child: Column(
              children: [
                _readinessRing(readiness),

                const SizedBox(height: 14),

                Text(
                  ready
                      ? "Account and required student information are ready."
                      : "Some student information is missing.",
                  textAlign: TextAlign.center,

                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 18),

                _readinessCheck("Authentication", _authUid != null),

                _readinessCheck(
                  "Student ID",
                  studentId != null && studentId!.isNotEmpty,
                ),

                _readinessCheck(
                  "Program",
                  program != null && program!.isNotEmpty,
                ),

                _readinessCheck(
                  "Year / Block",
                  yearBlock != null && yearBlock!.isNotEmpty,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readinessRing(int percentage) {
    return SizedBox(
      width: 118,
      height: 118,

      child: Stack(
        alignment: Alignment.center,

        children: [
          SizedBox(
            width: 118,
            height: 118,

            child: CircularProgressIndicator(
              value: percentage / 100,

              strokeWidth: 9,

              backgroundColor: const Color(0xFFE8ECE9),

              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            ),
          ),

          Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              Text("$percentage%", style: _display(25, color: _ink)),

              Text("READY", style: _monoStyle(8, color: _accent)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _readinessCheck(String title, bool good) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),

      child: Row(
        children: [
          Icon(
            good ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: good ? _accent : _danger,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _ink,
              ),
            ),
          ),

          Text(
            good ? "OK" : "CHECK",
            style: _monoStyle(8, color: good ? _accent : _danger),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  Widget _statusPill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),

      decoration: BoxDecoration(
        color: _accentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _accent.withOpacity(.22)),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Icon(icon, size: 6, color: _accent),

          const SizedBox(width: 6),

          Text(
            text,
            style: const TextStyle(
              color: _accent,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      "JAN",
      "FEB",
      "MAR",
      "APR",
      "MAY",
      "JUN",
      "JUL",
      "AUG",
      "SEP",
      "OCT",
      "NOV",
      "DEC",
    ];

    return "${months[date.month - 1]} ${date.day}, ${date.year}";
  }

  String _formatTime(DateTime date) {
    final int hour = date.hour % 12 == 0 ? 12 : date.hour % 12;

    final String minute = date.minute.toString().padLeft(2, "0");

    final String period = date.hour >= 12 ? "PM" : "AM";

    return "$hour:$minute $period";
  }

  void _openUpcomingExam(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final startTime = _toDate(data['startTime']);
    final endTime = _toDate(data['endTime']);

    context.go(
      '/take-exam/${Uri.encodeComponent(doc.id)}',
      extra: {
        'examId': doc.id,
        'startMillis': startTime?.millisecondsSinceEpoch,
        'endMillis': endTime?.millisecondsSinceEpoch,
      },
    );
  }

  void _openClass(String classId) {
    context.go('/student/class/${Uri.encodeComponent(classId)}');
  }

  // ============================================================
  // SECTION HEADER
  // ============================================================

  Widget _sectionHeader(IconData icon, String title, String tag) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),

      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),

            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(6),
            ),

            child: Icon(icon, size: 16, color: _accent),
          ),

          const SizedBox(width: 10),

          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(width: 12),

          const Expanded(child: Divider(height: 1, color: _line)),

          const SizedBox(width: 12),

          Text(tag, style: _monoStyle(9)),
        ],
      ),
    );
  }

  // ============================================================
  // RESULTS
  // ============================================================

  Widget _buildResultsTable(List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return _emptyCard(
        Icons.assignment_turned_in_outlined,
        "No results found",
      );
    }

    return Container(
      decoration: _cardBox(),

      clipBehavior: Clip.antiAlias,

      child: Column(
        children: [
          Container(
            color: _ink,

            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 10),

            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    "SUBJECT",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: _mono,
                      fontSize: 9,
                    ),
                  ),
                ),

                Expanded(
                  flex: 2,
                  child: Text(
                    "SCORE",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: _mono,
                      fontSize: 9,
                    ),
                  ),
                ),

                Expanded(
                  flex: 2,
                  child: Text(
                    "STATUS",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: _mono,
                      fontSize: 9,
                    ),
                  ),
                ),
              ],
            ),
          ),

          ...List.generate(results.length, (index) {
            final result = results[index];

            final examId = (result['examId'] ?? '').toString();
            final status = (result['status'] ?? '').toString().toLowerCase();

            return Material(
              color: index.isOdd ? _bg : Colors.white,
              child: InkWell(
                onTap: examId.isEmpty
                    ? null
                    : () {
                        if (status == 'completed') {
                          context.go(
                            '/exam-result/${Uri.encodeComponent(examId)}',
                          );
                        } else {
                          context.go(
                            '/take-exam/${Uri.encodeComponent(examId)}',
                          );
                        }
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          (result["subject"] ?? "—").toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),

                      Expanded(
                        flex: 2,
                        child: Text(
                          (result["score"] ?? "—").toString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),

                      Expanded(
                        flex: 2,
                        child: Center(
                          child: _statusChip(
                            (result["status"] ?? "—").toString(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    final bool completed = status == "completed";

    final Color color = completed ? _accent : _danger;

    final Color bg = completed ? _accentSoft : _dangerSoft;

    final String label = status.isEmpty
        ? "—"
        : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),

      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(.25)),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          Container(
            width: 6,
            height: 6,

            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),

          const SizedBox(width: 7),

          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY
  // ============================================================

  Widget _emptyCard(IconData icon, String message) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),

      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),

            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),

            child: Icon(icon, color: _accent, size: 26),
          ),

          const SizedBox(height: 12),

          Text(
            message,
            textAlign: TextAlign.center,

            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SKELETON
  // ============================================================

  Widget _buildSkeletonUI() {
    Widget block(double height, {double radius = 10}) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFECEEEB),
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          children: [
            block(75),

            const SizedBox(height: 20),

            block(350, radius: 12),

            const SizedBox(height: 14),

            GridView.count(
              crossAxisCount: 4,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.55,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),

              children: [block(155), block(155), block(155), block(155)],
            ),

            const SizedBox(height: 16),

            block(300),

            const SizedBox(height: 16),

            block(250),
          ],
        ),
      ),
    );
  }
}
