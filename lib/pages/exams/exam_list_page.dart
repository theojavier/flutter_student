import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/exam_model.dart';
import '../../widgets/exam_item_card.dart';

class ExamListPage extends StatefulWidget {
  const ExamListPage({super.key});

  @override
  State<ExamListPage> createState() => _ExamListPageState();
}

class _ExamListPageState extends State<ExamListPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  String? _studentId;
  String? _program;
  String? _yearBlock;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initSessionAndLoadStudent();
  }

  Future<void> _initSessionAndLoadStudent() async {
    final prefs = await SharedPreferences.getInstance();
    final sid = prefs.getString('studentId');
    if (sid == null) {
      setState(() {
        _studentId = null;
        _loading = false;
      });
      return;
    }

    setState(() => _studentId = sid);

    final userQuery = await _db
        .collection('users')
        .where('studentId', isEqualTo: sid)
        .limit(1)
        .get();

    if (userQuery.docs.isNotEmpty) {
      final userDoc = userQuery.docs.first;
      setState(() {
        _program = userDoc.data()['program'] as String?;
        _yearBlock = userDoc.data()['yearBlock'] as String?;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No user record found for studentId: $sid')),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_studentId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Exam')),
        body: const Center(
          child: Text('Not logged in. Please login to see your exams.'),
        ),
      );
    }

    if (_program == null || _yearBlock == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Exam')),
        body: const Center(child: Text('Loading student info...')),
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
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: [
            // Top title cube
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2B45),
                borderRadius: BorderRadius.circular(16),
                // boxShadow: [
                //   BoxShadow(
                //     color: Colors.black.withOpacity(0.2),
                //     blurRadius: 6,
                //     offset: const Offset(0, 3),
                //   ),
                // ],
              ),
              child: const Center(
                child: Text(
                  'My Exams',
                  style: TextStyle(
                    color: Color(0xFFE6F0F8),
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // Exams list
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: examsQuery.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No exams scheduled for this week',
                        style: TextStyle(fontSize: 16, color: Color(0xFFE6F0F8),),
                      ),
                    );
                  }

                  final exams = snapshot.data!.docs
                      .map((doc) => ExamModel.fromDoc(doc))
                      .toList();

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: exams.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return ExamItemCard(exam: exams[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
