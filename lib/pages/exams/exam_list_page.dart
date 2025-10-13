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

  /// Compute week start (Monday 00:00) and week end (Sunday 23:59:59)
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

    debugPrint("PROGRAM filter = $_program");
    debugPrint("YEARBLOCK filter = $_yearBlock");
    debugPrint("WEEK START = $startTs, END = $endTs");

    final examsQuery = _db
        .collection('exams')
        .where('program', isEqualTo: _program)
        .where('yearBlock', isEqualTo: _yearBlock)
        .where('startTime', isGreaterThanOrEqualTo: startTs)
        .where('endTime', isLessThanOrEqualTo: endTs);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.purple.shade700,
        title: const Text('My Exam'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: examsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No exams this week'));
          }

          final exams = snapshot.data!.docs
              .map((doc) => ExamModel.fromDoc(doc))
              .toList();

          debugPrint("Found ${exams.length} exams this week:");
          for (var e in exams) {
            debugPrint(
                "${e.subject} → ${e.startTime?.toDate()} - ${e.endTime?.toDate()}");
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: exams.length,
            itemBuilder: (context, index) {
              return ExamItemCard(exam: exams[index]);
            },
          );
        },
      ),
    );
  }
}
