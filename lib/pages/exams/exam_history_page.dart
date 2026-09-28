import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/exam_history_model.dart';
import '../../widgets/exam_history_item.dart';

class ExamHistoryPage extends StatefulWidget {
  const ExamHistoryPage({super.key});

  @override
  State<ExamHistoryPage> createState() => _ExamHistoryPageState();
}

class _ExamHistoryPageState extends State<ExamHistoryPage> {
  // Shared theme palette (same as HomePage / ProfilePage / LoginPage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _successColor = Color(0xFF4ADE80);
  static const Color _errorColor = Color(0xFFF87171);

  String? studentId;
  String? program;
  String? yearBlock;
  String? _authUid;
  bool loading = true;

  // Created once, so rebuilds don't re-subscribe / re-fetch everything
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

          if (program != null && yearBlock != null) {
            _historyStream = _buildHistoryStream(uid, program!, yearBlock!);
          }
        }
        loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Stream<List<ExamHistoryModel>> _buildHistoryStream(
    String uid,
    String program,
    String yearBlock,
  ) {
    final examResultsRef = FirebaseFirestore.instance
        .collection("examResults")
        .where("program", isEqualTo: program)
        .where("yearBlock", isEqualTo: yearBlock);

    return examResultsRef.snapshots().asyncMap((snapshot) async {
      // Read all per-exam student docs in parallel
      final futures = snapshot.docs.map<Future<ExamHistoryModel?>>((
        examDoc,
      ) async {
        final studentSnap = await examDoc.reference
            .collection("students")
            .doc(uid)
            .get();

        return studentSnap.exists
            ? ExamHistoryModel.fromDoc(studentSnap, examDoc.id)
            : null;
      });

      final results = (await Future.wait(futures))
          .whereType<ExamHistoryModel>()
          .toList();

      // Newest first
      results.sort((a, b) {
        final aTime = a.submittedAt?.toDate() ?? DateTime(1970);
        final bTime = b.submittedAt?.toDate() ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });

      return results;
    });
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (loading) return _buildSkeletonUI();

    final stream = _historyStream;
    if (stream == null) {
      return _messageState("Couldn't load your student profile.");
    }

    return StreamBuilder<List<ExamHistoryModel>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _messageState('Error: ${snapshot.error}', isError: true);
        }
        if (!snapshot.hasData) {
          return _buildSkeletonUI();
        }

        final exams = snapshot.data!;
        final completedCount = exams
            .where((e) => e.status.toLowerCase() == 'completed')
            .length;

        // Hides scrollbars on this page (scrolling still works)
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(
            context,
          ).copyWith(scrollbars: false, overscroll: false),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _heroCard(),
                      const SizedBox(height: 22),

                      _sectionHeader(Icons.dashboard_outlined, "Summary"),
                      Row(
                        children: [
                          Expanded(
                            child: _statCard(
                              icon: Icons.history,
                              title: "Total Exams",
                              count: exams.length,
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
                        Icons.assignment_turned_in_outlined,
                        "Past Exams",
                      ),
                    ],
                  ),
                ),
              ),

              if (exams.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: _emptyCard(Icons.history, "No exam history found"),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final exam = exams[index];
                      return ExamHistoryItem(
                        exam: exam,
                        onTap: () {
                          context.go(
                            '/take-exam/${exam.id}',
                            extra: {
                              "examId": exam.id,
                              "subject": exam.subject,
                              "score": exam.score,
                              "total": exam.total,
                              'startMillis': null,
                              'endMillis': null,
                            },
                          );
                        },
                      );
                    }, childCount: exams.length),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------- UI helpers ----------

  // Same card look as the Home page cards
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

  // Icon chip + title + divider line
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

  // Hero card: framed icon + title (like the Home hero, more compact)
  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
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
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
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
              borderRadius: BorderRadius.circular(17),
              child: Container(
                color: _cardColor,
                child: const Icon(
                  Icons.history_edu_outlined,
                  size: 32,
                  color: _textColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Exam History",
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width < 360 ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "REVIEW YOUR PAST EXAMS",
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

  Widget _messageState(String message, {bool isError = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: isError ? _errorColor : _mutedTextColor),
        ),
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
          block(120, radius: 24),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: block(120)),
              const SizedBox(width: 12),
              Expanded(child: block(120)),
            ],
          ),
          const SizedBox(height: 22),
          block(130),
          const SizedBox(height: 12),
          block(130),
        ],
      ),
    );
  }
}