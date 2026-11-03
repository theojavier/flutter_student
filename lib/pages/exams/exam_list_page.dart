import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/exam_model.dart';
import '../../helpers/SecureStorageHelper.dart';
import '../../utils/student_class_ids.dart';
import '../../widgets/pull_to_refresh_shell.dart';

class ExamListPage extends StatefulWidget {
  const ExamListPage({super.key});

  @override
  State<ExamListPage> createState() => _ExamListPageState();
}

// ============================================================
// HELPERS
// ============================================================

String _text(dynamic v, [String fallback = '']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

class _ExamEntry {
  const _ExamEntry({required this.exam, required this.status});

  final ExamModel exam;
  final String? status;

  bool get taken => status != null;
}

// ============================================================
// PAGE
// ============================================================

class _ExamListPageState extends State<ExamListPage> {
  // FOTS editorial palette (green) — same as ClassExamPage
  static const Color _bg = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _accent = Color(0xFF087B4F);
  static const Color _accentSoft = Color(0xFFE8F5EB);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _muted2 = Color(0xFF8A8D91);
  static const String _mono = 'monospace';

  String? _studentId;
  String? _program;
  String? _yearBlock;
  String? _profileError;
  bool _loading = true;

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _examStream;
  String? _takenExamIdsKey;
  Future<Map<String, String>>? _takenExamIdsFuture;

  @override
  void initState() {
    super.initState();
    AppRefresh.tick.addListener(_refreshExamList);
    _loadPrefs();
  }

  @override
  void dispose() {
    AppRefresh.tick.removeListener(_refreshExamList);
    super.dispose();
  }

  void _refreshExamList() => _loadPrefs();

  Future<void> _loadPrefs() async {
    final studentId = await SecureStorageHelper.read('studentId');
    final program = await SecureStorageHelper.read('program');
    final yearBlock = await SecureStorageHelper.read('yearBlock');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var classIds = <String>[];
    String? profileError;

    if (uid != null) {
      try {
        final profile = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        classIds = studentClassIdsFromProfile(profile.data());
      } on FirebaseException catch (error) {
        profileError = error.message ?? 'Unable to load your student profile.';
      }
    }

    if (!mounted) return;
    setState(() {
      _studentId = studentId;
      _program = program;
      _yearBlock = yearBlock;
      _profileError = profileError;
      _examStream = profileError == null ? _buildExamStream(classIds) : null;
      _takenExamIdsKey = null;
      _takenExamIdsFuture = null;
      _loading = false;
    });
  }

  Map<String, DateTime> _weekRange() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day, 0, 0, 0);
    final weekEnd = weekStart.add(
      const Duration(days: 6, hours: 23, minutes: 59, seconds: 59),
    );
    return {'start': weekStart, 'end': weekEnd};
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _buildExamStream(
    List<String> classIds,
  ) {
    if (classIds.isEmpty) {
      return Stream.value(<QueryDocumentSnapshot<Map<String, dynamic>>>[]);
    }
    final queries = <Stream<QuerySnapshot<Map<String, dynamic>>>>[];
    for (var start = 0; start < classIds.length; start += 30) {
      final classIdChunk = classIds.skip(start).take(30).toList();
      queries.add(
        FirebaseFirestore.instance
            .collection('exams')
            .where('classId', whereIn: classIdChunk)
            .snapshots(),
      );
    }
    return _combineExamStreams(queries);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _combineExamStreams(
    List<Stream<QuerySnapshot<Map<String, dynamic>>>> sources,
  ) {
    final latest =
        List<List<QueryDocumentSnapshot<Map<String, dynamic>>>?>.filled(
          sources.length,
          null,
        );
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    late final StreamController<
      List<QueryDocumentSnapshot<Map<String, dynamic>>>
    >
    controller;

    void emit() {
      if (latest.any((docs) => docs == null)) return;
      final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final docs in latest) {
        for (final doc in docs!) {
          docsById[doc.id] = doc;
        }
      }
      controller.add(docsById.values.toList());
    }

    controller =
        StreamController<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          onListen: () {
            for (var i = 0; i < sources.length; i++) {
              final index = i;
              subscriptions.add(
                sources[index].listen((snapshot) {
                  latest[index] = snapshot.docs;
                  emit();
                }, onError: controller.addError),
              );
            }
          },
          onCancel: () async {
            for (final subscription in subscriptions) {
              await subscription.cancel();
            }
            subscriptions.clear();
          },
        );
    return controller.stream;
  }

  /// examId -> result status ("completed" / "in-progress") for this student.
  Future<Map<String, String>> _takenExamIdsFor(List<ExamModel> exams) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Future.value(<String, String>{});

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
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    if (_studentId == null) {
      return _pageScaffold(
        _card(
          _stateBox(
            Icons.lock_outline,
            'Not logged in',
            'Please login to see your exams.',
          ),
        ),
      );
    }

    if (_profileError != null) {
      return _pageScaffold(
        _card(
          _stateBox(
            Icons.error_outline,
            'Could not load your classes',
            _profileError!,
          ),
        ),
      );
    }

    if (_examStream == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    return _pageScaffold(_examsSection());
  }

  Widget _pageScaffold(Widget body) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1250),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [_pageHead(), const SizedBox(height: 22), body],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // PAGE HEAD
  // ============================================================

  Widget _pageHead() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("FOTS / ALL EXAMS", style: _monoStyle(11, color: _accent)),
        const SizedBox(height: 10),
        Text("My exams.", style: _display(38, h: 1.08)),
        const SizedBox(height: 7),
        const Text(
          "Your quizzes and exams scheduled this week.",
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  // ============================================================
  // EXAMS
  // ============================================================

  Widget _examsSection() {
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
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

        final range = _weekRange();
        final exams =
            (snapshot.data ?? []).map(ExamModel.fromDoc).where((exam) {
              final startTime = exam.startTime?.toDate();
              final endTime = exam.endTime?.toDate();
              return startTime != null &&
                  endTime != null &&
                  !startTime.isBefore(range['start']!) &&
                  !endTime.isAfter(range['end']!);
            }).toList()..sort(
              (a, b) => a.startTime!.toDate().compareTo(b.startTime!.toDate()),
            );

        return FutureBuilder<Map<String, String>>(
          future: _takenExamIdsFor(exams),
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

            final statuses = resultsSnapshot.data!;
            final entries =
                exams
                    .map(
                      (exam) =>
                          _ExamEntry(exam: exam, status: statuses[exam.id]),
                    )
                    .toList()
                  ..sort((a, b) {
                    if (a.taken != b.taken) return a.taken ? 1 : -1;
                    return a.exam.startTime!.compareTo(b.exam.startTime!);
                  });

            return _examsCard(entries);
          },
        );
      },
    );
  }

  Widget _examsCard(List<_ExamEntry> exams) {
    final course = [
      _text(_program),
      _text(_yearBlock),
    ].where((s) => s.isNotEmpty).join(' · ');

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
              'No exams scheduled for this week',
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
                  const spacing = 12.0;
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

  // Even index = white, odd index = black (same as ClassExamPage)
  Widget _assessmentCard(_ExamEntry entry, String course, int index) {
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
                course.isEmpty ? assessmentType : course,
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
          Text(label, style: _monoStyle(8)),
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
