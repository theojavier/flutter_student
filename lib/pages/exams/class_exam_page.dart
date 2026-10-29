import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/exam_model.dart';

class ClassExamPage extends StatefulWidget {
  const ClassExamPage({super.key, required this.classId});

  final String classId;

  @override
  State<ClassExamPage> createState() => _ClassExamPageState();
}

// ============================================================
// HELPERS
// ============================================================

String _text(dynamic v, [String fallback = '']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

int? _intOf(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

/// "08:30" -> 510
int? _parseHm(dynamic v) {
  final parts = _text(v).split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return h * 60 + m;
}

String _minutesLabel(int minutes) {
  final m = minutes % (24 * 60);
  return DateFormat('h:mm a').format(DateTime(2000, 1, 1, m ~/ 60, m % 60));
}

String _daysLabel(Map<String, dynamic> c) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final raw = c['days'] ?? c['day'];
  if (raw is List) {
    return raw
        .map((d) {
          if (d is num && d >= 1 && d <= 7) return names[d.toInt() - 1];
          return d.toString().trim();
        })
        .where((s) => s.isNotEmpty)
        .join(', ');
  }
  return _text(raw);
}

String _scheduleLabel(Map<String, dynamic> c) {
  final s = _intOf(c['startMinutes']) ?? _parseHm(c['startLabel']);
  final e = _intOf(c['endMinutes']) ?? _parseHm(c['endLabel']);
  final days = _daysLabel(c);
  if (s == null || e == null) return days.isEmpty ? '—' : days;
  final time = '${_minutesLabel(s)} – ${_minutesLabel(e)}';
  return days.isEmpty ? time : '$days · $time';
}

String _initials(String name) {
  final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts[1][0]).toUpperCase();
}

// ============================================================
// PAGE
// ============================================================

class _ClassExamPageState extends State<ClassExamPage> {
  // FOTS editorial palette (green)
  static const Color _bg = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _accent = Color(0xFF087B4F);
  static const Color _accentDark = Color(0xFF075C3C);
  static const Color _accentSoft = Color(0xFFE8F5EB);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _muted2 = Color(0xFF8A8D91);
  static const String _mono = 'monospace';

  late Future<Map<String, dynamic>> _classDetails;
  String? _takenExamIdsKey;
  Future<Map<String, String>>? _takenExamIdsFuture;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _examStream;

  @override
  void initState() {
    super.initState();
    _setupForClass();
  }

  @override
  void didUpdateWidget(covariant ClassExamPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classId != widget.classId) {
      _setupForClass();
    }
  }

  void _setupForClass() {
    _classDetails = _loadClassDetails();
    _examStream = FirebaseFirestore.instance
        .collection('exams')
        .where('classId', isEqualTo: widget.classId)
        .snapshots();
    _takenExamIdsKey = null;
    _takenExamIdsFuture = null;
  }

  Future<Map<String, dynamic>> _loadClassDetails() async {
    final db = FirebaseFirestore.instance;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      throw StateError('Sign in to view this class.');
    }

    final userDoc = await db.collection('users').doc(userId).get();
    final userData = userDoc.data() ?? {};
    final classIds = <String>[
      if (userData['classIds'] is List)
        ...(userData['classIds'] as List).map((value) => value.toString()),
      if ((userData['classId'] ?? '').toString().isNotEmpty)
        userData['classId'].toString(),
    ];
    if (!classIds.contains(widget.classId)) {
      throw StateError('This class is not assigned to your account.');
    }

    final classDoc = await db.collection('classes').doc(widget.classId).get();
    if (!classDoc.exists) {
      throw StateError('This class is no longer available.');
    }

    final classData = classDoc.data()!;
    final programId = (classData['program'] ?? '').toString();
    var programName = programId;
    if (programId.isNotEmpty) {
      final programDoc = await db.collection('programs').doc(programId).get();
      if (programDoc.exists) {
        programName = (programDoc.data()?['name'] ?? programId).toString();
      }
    }

    return {...classData, 'programName': programName};
  }

  // ============================================================
  // STYLES
  // ============================================================

  TextStyle _monoStyle(double size, {Color color = _muted2}) => TextStyle(
    fontFamily: _mono,
    fontSize: size,
    color: color,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w500,
  );

  TextStyle _display(double size, {Color color = _ink, double h = 1.0}) =>
      TextStyle(
        fontSize: size,
        height: h,
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: -size * 0.05,
      );

  BoxDecoration _cardBox({Color color = Colors.white, double radius = 10}) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _line),
      );

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: FutureBuilder<Map<String, dynamic>>(
        future: _classDetails,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }
          if (snap.hasError) {
            return _stateBox(
              Icons.info_outline,
              'Class unavailable',
              snap.error.toString().replaceFirst('Bad state: ', ''),
            );
          }

          final c = snap.data!;

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1250),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _pageHead(_text(c['subject'], 'Class')),
                      const SizedBox(height: 22),
                      _overviewCard(c),
                      const SizedBox(height: 16),
                      _examsSection(c),
                    ],
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
  // PAGE HEAD
  // ============================================================

  Widget _pageHead(String subject) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("FOTS / CLASS", style: _monoStyle(11, color: _accent)),
        const SizedBox(height: 10),
        Text("$subject.", style: _display(38, h: 1.08)),
        const SizedBox(height: 7),
        const Text(
          "Your class overview, adviser and exams.",
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  // ============================================================
  // OVERVIEW CARD
  // ============================================================

  Widget _overviewCard(Map<String, dynamic> c) {
    final teacher = _text(c['adviserName'], 'Not assigned');
    final hasTeacher = _text(c['adviserName']).isNotEmpty;
    final yearBlock = _text(c['yearBlock'], '—');
    final semester = _text(c['semester']);
    final schoolYear = _text(c['schoolYear'], '—');
    final room = _text(c['roomDefault'], '—');
    final program = _text(c['programName'], '—');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(20, 17, 20, 15),
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
                        "Class overview",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Details about this class",
                        style: TextStyle(
                          color: _muted2,
                          fontFamily: _mono,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                _classStatusPill(_text(c['status'], 'active')),
              ],
            ),
          ),

          // TEACHER
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: hasTeacher ? _ink : _line,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasTeacher ? _initials(teacher) : '—',
                    style: _display(17, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("CLASS ADVISER", style: _monoStyle(9)),
                      const SizedBox(height: 5),
                      Text(
                        teacher,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: _line),

          // DETAILS GRID
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 900
                    ? 3
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;
                final width = (constraints.maxWidth - (cols - 1) * 10) / cols;

                Widget tile(String label, String value, IconData icon) =>
                    SizedBox(
                      width: width,
                      child: _detailTile(label, value, icon),
                    );

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    tile(
                      "Schedule",
                      _scheduleLabel(c),
                      Icons.schedule_outlined,
                    ),
                    tile("Room", room, Icons.meeting_room_outlined),
                    tile("Year / Block", yearBlock, Icons.groups_outlined),
                    tile(
                      "Semester",
                      semester.isEmpty ? '—' : '$semester semester',
                      Icons.calendar_view_week_outlined,
                    ),
                    tile("School year", schoolYear, Icons.event_note_outlined),
                    tile("Program", program, Icons.account_tree_outlined),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardBox(color: _bg, radius: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 17, color: _accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: _monoStyle(9)),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _classStatusPill(String status) {
    final active = status == 'active';
    final label = status.isEmpty
        ? '—'
        : status[0].toUpperCase() + status.substring(1);
    final color = active ? _accent : _muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: active ? _accentSoft : _bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EXAMS (stats + grouped list)
  // ============================================================

  Widget _examsSection(Map<String, dynamic> classData) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _examStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _card(
            _stateBox(
              Icons.error_outline,
              'Could not load exams',
              snapshot.error.toString(),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 50),
            child: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        final now = DateTime.now();
        final weekStart = DateTime(
          now.year,
          now.month,
          now.day - (now.weekday - DateTime.monday),
        );
        final weekEnd = weekStart.add(const Duration(days: 7));

        final weeklyExams =
            (snapshot.data?.docs ?? [])
                .where(
                  (doc) => _text(doc.data()['approvalStatus']) == 'approved',
                )
                .map(ExamModel.fromDoc)
                .where((exam) {
                  final start = exam.startTime?.toDate();
                  return start != null &&
                      !start.isBefore(weekStart) &&
                      start.isBefore(weekEnd);
                })
                .toList()
              ..sort((a, b) {
                final aStart = a.startTime!.toDate();
                final bStart = b.startTime!.toDate();
                return aStart.compareTo(bStart);
              });

        return FutureBuilder<Map<String, String>>(
          future: _takenExamIdsFor(weeklyExams),
          builder: (context, resultsSnapshot) {
            if (resultsSnapshot.hasError) {
              return _card(
                _stateBox(
                  Icons.error_outline,
                  'Could not load exam status',
                  resultsSnapshot.error.toString(),
                ),
              );
            }
            if (!resultsSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Center(child: CircularProgressIndicator(color: _accent)),
              );
            }

            final attemptStatuses = resultsSnapshot.data!;
            final entries =
                weeklyExams
                    .map(
                      (exam) => _ClassExamEntry(
                        exam: exam,
                        status: attemptStatuses[exam.id],
                      ),
                    )
                    .toList()
                  ..sort((a, b) {
                    if (a.taken != b.taken) return a.taken ? 1 : -1;
                    return a.exam.startTime!.compareTo(b.exam.startTime!);
                  });

            return _examsCard(entries, _text(classData['subject'], 'Class'));
          },
        );
      },
    );
  }

  Future<Map<String, String>> _takenExamIdsFor(List<ExamModel> exams) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Future.error(StateError('Sign in to view exam status.'));
    }

    final key = '$uid:${exams.map((exam) => exam.id).join(',')}';
    if (_takenExamIdsKey == key && _takenExamIdsFuture != null) {
      return _takenExamIdsFuture!;
    }

    _takenExamIdsKey = key;
    _takenExamIdsFuture =
        Future.wait(
          exams.map((exam) async {
            final result = await FirebaseFirestore.instance
                .collection('examResults')
                .doc(exam.id)
                .collection('students')
                .doc(uid)
                .get();
            if (!result.exists) return null;
            return MapEntry(
              exam.id,
              _text(result.data()?['status'], 'in-progress').toLowerCase(),
            );
          }),
        ).then(
          (entries) =>
              Map.fromEntries(entries.whereType<MapEntry<String, String>>()),
        );
    return _takenExamIdsFuture!;
  }

  Widget _examsCard(List<_ClassExamEntry> exams, String course) {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 17, 20, 15),
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
                        "This week's assessments",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "Quizzes and exams scheduled this week",
                        style: TextStyle(
                          color: _muted2,
                          fontFamily: _mono,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    exams.length == 1
                        ? '1 ASSESSMENT'
                        : '${exams.length} ASSESSMENTS',
                    style: _monoStyle(9, color: _accent),
                  ),
                ),
              ],
            ),
          ),
          if (exams.isEmpty)
            _stateBox(
              Icons.event_available_outlined,
              'No assessments this week',
              'Quizzes and exams scheduled for this week will appear here.',
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900
                      ? 3
                      : constraints.maxWidth >= 560
                      ? 2
                      : 1;
                  final spacing = 12.0;
                  final cardWidth =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (var index = 0; index < exams.length; index++)
                        SizedBox(
                          width: cardWidth,
                          child: _assessmentCard(exams[index], course, index),
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _assessmentCard(_ClassExamEntry entry, String course, int index) {
    final exam = entry.exam;
    final start = exam.startTime!.toDate();
    final end = exam.endTime?.toDate();
    final minutes = end?.difference(start).inMinutes;
    final durationLabel = (minutes ?? 0) <= 0 ? 'Not set' : '$minutes min';
    final title = exam.subject?.trim().isNotEmpty == true
        ? exam.subject!.trim()
        : 'Untitled assessment';
    final assessmentType =
        RegExp(r'\bquiz\b', caseSensitive: false).hasMatch(title)
        ? 'QUIZ'
        : 'EXAM';
    final dark = index.isOdd;
    final foreground = dark ? Colors.white : _ink;
    final secondary = dark ? const Color(0xFFD0D0D5) : _muted;
    final borderColor = dark
        ? const Color(0xFF34343B)
        : entry.taken
        ? _line
        : const Color(0xFFB8DCCB);

    void openAssessment() {
      _takenExamIdsKey = null;
      _takenExamIdsFuture = null;
      context.go(
        '/take-exam/${exam.id}',
        extra: {
          'examId': exam.id,
          'subject': exam.subject,
          'teacherId': exam.teacherId,
          'startMillis': start.millisecondsSinceEpoch,
          'endMillis': end?.millisecondsSinceEpoch,
        },
      );
    }

    return Material(
      color: dark ? _ink : Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: openAssessment,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: dark ? _ink : Colors.white,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                course,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _monoStyle(10, color: dark ? _accentSoft : _accent),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$assessmentType scheduled for this week.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: secondary, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _assessmentMeta(
                      'SCHEDULE',
                      DateFormat('EEE, MMM d · h:mm a').format(start),
                      dark: dark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _assessmentMeta(
                      'DURATION',
                      durationLabel,
                      dark: dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.status == 'completed'
                          ? 'COMPLETED'
                          : entry.taken
                          ? 'IN PROGRESS'
                          : 'NOT TAKEN',
                      style: _monoStyle(
                        9,
                        color: entry.taken
                            ? (dark ? _muted2 : _muted)
                            : _accent,
                      ),
                    ),
                  ),
                  Icon(
                    entry.status == 'completed'
                        ? Icons.assessment_outlined
                        : Icons.arrow_forward_rounded,
                    color: dark ? Colors.white : _accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    entry.status == 'completed'
                        ? 'View result'
                        : entry.taken
                        ? 'Continue exam'
                        : 'Enter exam',
                    style: TextStyle(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _assessmentMeta(String label, String value, {required bool dark}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF25252B) : _bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _monoStyle(8, color: dark ? _muted2 : _muted2)),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark ? Colors.white : _ink,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: _cardBox(),
    child: child,
  );

  // ============================================================
  // EMPTY / ERROR STATE
  // ============================================================

  Widget _stateBox(IconData icon, String title, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _accent, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassExamEntry {
  const _ClassExamEntry({required this.exam, required this.status});

  final ExamModel exam;
  final String? status;

  bool get taken => status != null;
}
