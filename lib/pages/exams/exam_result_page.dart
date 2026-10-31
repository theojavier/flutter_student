import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ExamResultPage extends StatefulWidget {
  final String examId;

  const ExamResultPage({super.key, required this.examId});

  @override
  State<ExamResultPage> createState() => _ExamResultPageState();
}

class _ExamResultPageState extends State<ExamResultPage> {
  // FOTS editorial palette (same as the class exam / history pages)
  static const Color _bg = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _muted2 = Color(0xFF8A8D91);
  static const Color _accent = Color(0xFF087B4F);
  static const Color _accentSoft = Color(0xFFE8F5EB);
  static const String _mono = 'monospace';

  // Grade colors
  static const Color _green = Color(0xFF087B4F);
  static const Color _orange = Color(0xFFB88826);
  static const Color _red = Color(0xFFBD2942);

  String? _authUid;

  // Created once so rebuilds don't refetch
  late final Future<Map<String, dynamic>> _future = _load();

  @override
  void initState() {
    super.initState();
    _authUid = FirebaseAuth.instance.currentUser?.uid;
  }

  Future<Map<String, dynamic>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Sign in to view this result.');

    final db = FirebaseFirestore.instance;
    final docs = await Future.wait([
      db.collection('users').doc(uid).get(),
      db
          .collection('examResults')
          .doc(widget.examId)
          .collection('students')
          .doc(uid)
          .get(),
    ]);

    final user = docs[0];
    final result = docs[1];

        if (!user.exists || user.data()?['studentId'] == null) {
      throw StateError('Student not found.');
    }
    if (!result.exists) {
      throw StateError('Result not found.');
    }

    // The result doc's studentId holds the auth uid, so use the one
    // from the user's profile for display.
    return {
      ...?result.data(),
      'studentId': user.data()!['studentId'].toString(),
    };
  }

  // ============================================================
  // GRADING
  // ============================================================

  Color _getColor(double percent) {
    if (percent >= 80) return _green;
    if (percent >= 75) return _orange;
    return _red;
  }

  String _getMark(double percent) => percent >= 75 ? 'Passed' : 'Failed';

  String _fmt(num n) =>
      n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1);

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
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return _shell(_skeletonChildren());
            }
            if (snap.hasError) {
              return _stateBox(
                Icons.info_outline,
                'Result unavailable',
                snap.error.toString().replaceFirst('Bad state: ', ''),
              );
            }

            final data = snap.data!;
            final score = ((data['score'] ?? 0) as num).toDouble();
            final total = ((data['total'] ?? 0) as num).toDouble();
            final studentId = (data['studentId'] ?? 'Unknown').toString();
            final subject = (data['subject'] ?? 'Unknown subject').toString();

            // Adjusted percent
            final rawPercent = total > 0 ? (score / total) * 100 : 0.0;
            final percent = (50 + rawPercent / 2).clamp(0.0, 100.0).toDouble();

            final color = _getColor(percent);
            final mark = _getMark(percent);

            return _shell([
              _pageHead(),
              const SizedBox(height: 22),
              _resultCard(
                subject: subject,
                studentId: studentId,
                score: score,
                total: total,
                percent: percent,
                color: color,
                mark: mark,
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _shell(List<Widget> children) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
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
        const SizedBox(height: 14),
        Text('FOTS / RESULT', style: _monoStyle(11, color: _accent)),
        const SizedBox(height: 10),
        Text('Exam result.', style: _display(38, h: 1.08)),
        const SizedBox(height: 7),
        const Text(
          'Your score and equivalent grade for this exam.',
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  // ============================================================
  // RESULT CARD
  // ============================================================

  Widget _resultCard({
    required String subject,
    required String studentId,
    required double score,
    required double total,
    required double percent,
    required Color color,
    required String mark,
  }) {
    final passed = percent >= 75;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: _cardBox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            color: _ink,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SUBJECT', style: _monoStyle(9)),
                      const SizedBox(height: 7),
                      Text(
                        subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          height: 1.15,
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _markPill(mark, color, passed),
              ],
            ),
          ),

          // BODY
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;

                final scorePanel = _scorePanel(percent, color, mark);

                final tiles = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _detailTile(
                      'Score',
                      '${_fmt(score)} / ${_fmt(total)}',
                      Icons.assessment_outlined,
                    ),
                    const SizedBox(height: 10),
                    _detailTile(
                      'Equivalent grade',
                      '${percent.toStringAsFixed(2)} %',
                      Icons.percent_rounded,
                      valueColor: color,
                    ),
                    const SizedBox(height: 10),
                    _detailTile(
                      'Mark',
                      mark,
                      passed
                          ? Icons.check_circle_outline
                          : Icons.highlight_off_outlined,
                      valueColor: color,
                    ),
                    const SizedBox(height: 10),
                    _detailTile(
                      'Student ID',
                      studentId,
                      Icons.badge_outlined,
                    ),
                  ],
                );

                if (wide) {
  return IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: scorePanel),
        const SizedBox(width: 14),
        Expanded(flex: 2, child: tiles),
      ],
    ),
  );
}
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [scorePanel, const SizedBox(height: 14), tiles],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _markPill(String mark, Color color, bool passed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: color),
          const SizedBox(width: 6),
          Text(
            mark.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scorePanel(double percent, Color color, String mark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        color: color.withOpacity(.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(.28)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EQUIVALENT GRADE', style: _monoStyle(10, color: color)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                percent.toStringAsFixed(2),
                style: _display(56, color: color),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('%', style: _display(22, color: color)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            mark == 'Passed'
                ? 'You passed this exam.'
                : 'You did not reach the passing grade.',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile(
    String label,
    String value,
    IconData icon, {
    Color valueColor = _ink,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardBox(color: _bg, radius: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 17, color: _accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: _monoStyle(9)),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
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
      block(300),
    ];
  }
}