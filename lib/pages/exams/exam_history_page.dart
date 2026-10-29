import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/exam_history_model.dart';

String _text(dynamic v, [String fallback = '']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

class ExamHistoryPage extends StatefulWidget {
  const ExamHistoryPage({super.key});

  @override
  State<ExamHistoryPage> createState() => _ExamHistoryPageState();
}

class _ExamHistoryPageState extends State<ExamHistoryPage> {
  // FOTS editorial palette (same as the class exam page)
  static const Color _bg = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _accent = Color(0xFF087B4F);
  static const Color _accentSoft = Color(0xFFE8F5EB);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _muted2 = Color(0xFF8A8D91);
  static const Color _warn = Color(0xFFB88826);
  static const Color _error = Color(0xFFBD2942);
  static const String _mono = 'monospace';

  String? studentId;
  String? program;
  String? yearBlock;
  String? _authUid;
  bool loading = true;

  Stream<List<ExamHistoryModel>>? _historyStream;

  @override
  void initState() {
    super.initState();
    _authUid = FirebaseAuth.instance.currentUser?.uid;
    if (_authUid == null) {
      loading = false;
      return;
    }
    _loadStudentData();
  }

  Future<void> _loadStudentData() async {
    final uid = _authUid!;
    try {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = userSnap.data();
      if (!mounted) return;

      setState(() {
  if (data != null) {
    studentId = data['studentId']?.toString();
    program = data['program']?.toString();
    yearBlock = data['yearBlock']?.toString();
  }
  _historyStream = _buildHistoryStream(uid);
  loading = false;
});
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Stream<List<ExamHistoryModel>> _buildHistoryStream(String uid) {
  return FirebaseFirestore.instance
      .collectionGroup('students')
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map((snapshot) {
    final results = snapshot.docs
        .map((doc) {
          // parent of "students" is the examResults/{examId} doc
          final examId =
              doc.reference.parent.parent?.id ??
              (doc.data()['examId'] ?? '').toString();
          return ExamHistoryModel.fromDoc(doc, examId);
        })
        .toList();

    // Unfinished first, then completed by latest submitted.
    results.sort((a, b) {
      final aDone = a.status.toLowerCase() == 'completed';
      final bDone = b.status.toLowerCase() == 'completed';
      if (aDone != bDone) return aDone ? 1 : -1;
      final aTime = a.submittedAt?.toDate() ?? DateTime(1970);
      final bTime = b.submittedAt?.toDate() ?? DateTime(1970);
      return bTime.compareTo(aTime);
    });
    return results;
  });
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
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _scrollShell(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1250),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (loading) return _scrollShell(_skeletonChildren());

    final stream = _historyStream;
    if (stream == null) {
      return _stateBox(
        Icons.info_outline,
        'Profile unavailable',
        "Couldn't load your student profile.",
      );
    }

    return StreamBuilder<List<ExamHistoryModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _stateBox(
            Icons.error_outline,
            'Could not load history',
            '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) return _scrollShell(_skeletonChildren());

        final exams = snapshot.data!;
        final completed = exams
            .where((e) => e.status.toLowerCase() == 'completed')
            .length;
        final inProgress = exams
            .where((e) => e.status.toLowerCase() == 'in-progress')
            .length;

        return _scrollShell([
          _pageHead(),
          const SizedBox(height: 22),
          _summaryCard(exams.length, completed, inProgress),
          const SizedBox(height: 16),
          _examsCard(exams),
        ]);
      },
    );
  }

  // ============================================================
  // PAGE HEAD
  // ============================================================

  Widget _pageHead() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("FOTS / HISTORY", style: _monoStyle(11, color: _accent)),
        const SizedBox(height: 10),
        Text("Exam history.", style: _display(38, h: 1.08)),
        const SizedBox(height: 7),
        const Text(
          "Review your previous exam attempts and results.",
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  Widget _cardHeader(String title, String subtitle, {Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 17, 20, 15),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _muted2,
                    fontFamily: _mono,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ============================================================
  // SUMMARY
  // ============================================================

  Widget _summaryCard(int total, int completed, int inProgress) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader("Summary", "Your exam activity at a glance"),
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 560 ? 3 : 1;
                final width = (constraints.maxWidth - (cols - 1) * 10) / cols;

                Widget tile(String label, int value, IconData icon) =>
                    SizedBox(
                      width: width,
                      child: _statTile(label, value, icon),
                    );

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    tile("Total exams", total, Icons.history),
                    tile(
                      "Completed",
                      completed,
                      Icons.check_circle_outline,
                    ),
                    tile(
                      "In progress",
                      inProgress,
                      Icons.hourglass_top_outlined,
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

  Widget _statTile(String label, int value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardBox(color: _bg, radius: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: _monoStyle(9)),
                const SizedBox(height: 5),
                Text(value.toString(), style: _display(24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // EXAMS LIST
  // ============================================================

  Widget _examsCard(List<ExamHistoryModel> exams) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardHeader(
            "Past exams",
            "Latest first, unfinished exams on top",
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                exams.length == 1 ? '1 EXAM' : '${exams.length} EXAMS',
                style: _monoStyle(9, color: _accent),
              ),
            ),
          ),
          if (exams.isEmpty)
            _stateBox(
              Icons.history,
              'No exam history found',
              'Exams you take will appear here.',
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
                      for (var i = 0; i < exams.length; i++)
                        SizedBox(
                          width: cardWidth,
                          child: _examCard(exams[i], i),
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

  Widget _examCard(ExamHistoryModel exam, int index) {
    final status = exam.status.toLowerCase();
    final completed = status == 'completed';
    final inProgress = status == 'in-progress';

    final title = _text(exam.subject, 'Untitled exam');
    final type = RegExp(r'\bquiz\b', caseSensitive: false).hasMatch(title)
        ? 'QUIZ'
        : 'EXAM';
    final submitted = exam.submittedAt?.toDate();
    final submittedLabel = submitted == null
        ? '—'
        : DateFormat('MMM d, yyyy · h:mm a').format(submitted);
    final scoreLabel = completed ? '${exam.score} / ${exam.total}' : '—';

    final statusLabel = completed
        ? 'COMPLETED'
        : inProgress
        ? 'IN PROGRESS'
        : status.isEmpty
        ? '—'
        : status.toUpperCase();
    final statusColor = completed
        ? _accent
        : inProgress
        ? _warn
        : _error;
    final actionLabel = completed
        ? 'View result'
        : inProgress
        ? 'Continue exam'
        : 'View details';

    final dark = index.isOdd;
    final foreground = dark ? Colors.white : _ink;
    final secondary = dark ? const Color(0xFFD0D0D5) : _muted;
    final borderColor = dark ? const Color(0xFF34343B) : _line;

    void open() {
      context.go('/take-exam/${Uri.encodeComponent(exam.id)}');
    }

    return Material(
      color: dark ? _ink : Colors.white,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                type,
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
                completed
                    ? 'You completed this $type.'
                    : inProgress
                    ? 'This $type is still in progress.'
                    : 'This $type was not completed.',
                style: TextStyle(color: secondary, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _meta('SUBMITTED', submittedLabel, dark: dark),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _meta('SCORE', scoreLabel, dark: dark),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      statusLabel,
                      style: _monoStyle(9, color: statusColor),
                    ),
                  ),
                  Icon(
                    completed
                        ? Icons.assessment_outlined
                        : Icons.arrow_forward_rounded,
                    color: dark ? Colors.white : _accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    actionLabel,
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

  Widget _meta(String label, String value, {required bool dark}) {
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

  // ============================================================
  // EMPTY / ERROR STATE + SKELETON
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

  List<Widget> _skeletonChildren() {
    Widget block(double height, {double radius = 10}) => Container(
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9ECE9),
        borderRadius: BorderRadius.circular(radius),
      ),
    );

    return [
      block(14, radius: 4),
      const SizedBox(height: 14),
      block(40, radius: 6),
      const SizedBox(height: 22),
      block(150),
      const SizedBox(height: 16),
      block(220),
    ];
  }
}