import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/exam_model.dart';
import '../../widgets/exam_item_card.dart';
import '../../helpers/SecureStorageHelper.dart';

class ExamListPage extends StatefulWidget {
  const ExamListPage({super.key});

  @override
  State<ExamListPage> createState() => _ExamListPageState();
}

class _ExamListPageState extends State<ExamListPage> {
  // Shared theme palette (same as ProfilePage / HomePage / ExamHistoryPage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _studentId;
  String? _program;
  String? _yearBlock;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final studentId = await SecureStorageHelper.read('studentId');
    final program = await SecureStorageHelper.read('program');
    final yearBlock = await SecureStorageHelper.read('yearBlock');

    if (!mounted) return;
    setState(() {
      _studentId = studentId;
      _program = program;
      _yearBlock = yearBlock;
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

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }

    if (_studentId == null) {
      return _messageScaffold(
        icon: Icons.lock_outline,
        message: 'Not logged in. Please login to see your exams.',
      );
    }

    if (_program == null || _yearBlock == null) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }

    final range = _weekRange();
    final startTs = Timestamp.fromDate(range['start']!);
    final endTs = Timestamp.fromDate(range['end']!);

    final examsQuery = _db
        .collection('exams')
        .where('program', isEqualTo: _program)
        .where('yearBlock', isEqualTo: _yearBlock)
        .where('startTime', isGreaterThanOrEqualTo: startTs)
        .where('endTime', isLessThanOrEqualTo: endTs);

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(),
              const SizedBox(height: 16),

              // Exams list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: examsQuery.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _accentColor),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return _buildEmptyState(
                        Icons.event_busy_outlined,
                        'No exams scheduled for this week',
                      );
                    }

                    final exams = snapshot.data!.docs
                        .map((doc) => ExamModel.fromDoc(doc))
                        .toList();

                    // Hides the scrollbar (scrolling still works)
                    return ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: false,
                        overscroll: false,
                      ),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: exams.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          return ExamItemCard(exam: exams[index]);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Floating title bar — same construction as the Profile page
  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
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
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(12.5),
              ),
              child: const Icon(Icons.edit_note_outlined,
                  color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "My Exams",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "THIS WEEK",
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
        ],
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _cardColor.withOpacity(0.9),
              _cardColor.withOpacity(0.55),
            ],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accentColor.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withOpacity(0.35),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(icon, size: 32, color: _accentColor),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _mutedTextColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Full-page message (used for the "not logged in" state)
  Widget _messageScaffold({required IconData icon, required String message}) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(),
              const SizedBox(height: 16),
              _buildEmptyState(icon, message),
            ],
          ),
        ),
      ),
    );
  }
}