import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_flutter_app/theme/colors.dart';
import 'package:go_router/go_router.dart';

class TakeExamPage extends StatefulWidget {
  final String examId;
  final int? startMillis;
  final int? endMillis;

  const TakeExamPage({
    super.key,
    required this.examId,
    this.startMillis,
    this.endMillis,
  });

  @override
  State<TakeExamPage> createState() => _TakeExamPageState();
}

class _TakeExamPageState extends State<TakeExamPage>
    with WidgetsBindingObserver {
  final db = FirebaseFirestore.instance;
  String? studentId;
  int? start;
  int? end;
  bool isWarningShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStudentId();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      studentId = prefs.getString("studentId");
    });
  }

  // 🔹 Anti-tab-switch: warn when app goes background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !isWarningShown) {
      isWarningShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Don’t leave the app during the exam!"),
          backgroundColor: Colors.red,
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        isWarningShown = false;
      });
    }
  }

  String formatDate(int millis, {bool withTime = true}) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return withTime
        ? DateFormat("MMM d, yyyy h:mm a").format(date)
        : DateFormat("MMM d, yyyy").format(date);
  }


  @override
  Widget build(BuildContext context) {
    if (studentId == null) {
      return const Scaffold(
        body: Center(child: Text("⚠️ Not logged in")),
      );
    }

    return Scaffold(
      appBar: AppBar(
      automaticallyImplyLeading: false,
      title: const Text("Exam Details")),
      body: FutureBuilder<DocumentSnapshot>(
        future: db.collection("exams").doc(widget.examId).get(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.data!.exists) {
            return const Center(child: Text("Exam not found"));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final subject = data["subject"] ?? "Unknown";
          final teacherId = data["teacherId"] ?? "";
          start = widget.startMillis ??
              data["startTime"]?.toDate().millisecondsSinceEpoch;
          end = widget.endMillis ??
              data["endTime"]?.toDate().millisecondsSinceEpoch;


          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🔹 Subject
                Text(subject,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),

                // 🔹 Start time
                if (start != null)
                  Text("Start: ${formatDate(start!)}",
                      style: const TextStyle(fontSize: 16)),

                const SizedBox(height: 16),

                // 🔹 Instructions
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: const Color(0xFFEEEEEE),
                  child: const Text(
                    "Instructions:\n- Don’t switch tabs\n- Don’t leave the app",
                    style: TextStyle(fontSize: 14),
                  ),
                ),

                const SizedBox(height: 16),
                Divider(color: Colors.grey[400]),

                // 🔹 Teacher name
                FutureBuilder<DocumentSnapshot>(
                  future: teacherId.isNotEmpty
                      ? db.collection("users").doc(teacherId).get()
                      : Future.value(null),
                  builder: (context, teacherSnap) {
                    String teacherText = "Teacher: Unknown";
                    if (teacherSnap.hasData &&
                        teacherSnap.data != null &&
                        teacherSnap.data!.exists) {
                      final teacherData =
                          teacherSnap.data!.data() as Map<String, dynamic>;
                      final name = teacherData["name"];
                      if (name != null) teacherText = "Teacher: $name";
                    }
                    return Text(teacherText,
                        style: const TextStyle(fontSize: 16));
                  },
                ),

                // 🔹 Duration
                if (start != null && end != null)
                  Text(
                    "${formatDate(start!)} - ${DateFormat("h:mm a").format(DateTime.fromMillisecondsSinceEpoch(end!))}",
                    style: const TextStyle(fontSize: 16),
                  ),


                const Spacer(),

                // 🔹 Start / Resume / View Result button (real-time updates)
StreamBuilder<DocumentSnapshot>(
  stream: db
      .collection("examResults")
      .doc(widget.examId)
      .collection(studentId!)
      .doc("result")
      .snapshots(),
  builder: (context, resultSnap) {
    if (!resultSnap.hasData) {
      return ElevatedButton(
        onPressed: null,
        child: const Text("Loading..."),
      );
    }

    final doc = resultSnap.data!;
    final now = DateTime.now().millisecondsSinceEpoch;

// ✅ Completed
if (doc.exists && doc["status"] == "completed") {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: AppColors.viewResult),
    child: const Text("View Result"),
    onPressed: () {
// View Result
context.goNamed(
  'examResult',
  pathParameters:{
    "examId": widget.examId,
    "studentId": studentId!,
  },
);
    },
  );
}

// ✅ In-progress
if (doc.exists && doc["status"] == "in-progress") {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: AppColors.resumeExam),
    child: const Text("Exam being taken"),
    onPressed: () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Exam is already being taken"),
        ),
      );
    },
  );
}
if (doc.exists && doc["status"] == "incomplete") {
  return ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 255, 0, 0)),
    child: const Text("Exam incomplete"),
    onPressed: () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("you can't take the exam"),
        ),
      );
    },
  );
}

    // ✅ Exam not started yet
    if (start != null && now < start!) {
      return ElevatedButton(
        onPressed: null,
        child: const Text("Exam not started yet"),
      );
    }

    // ✅ Exam ended
    if (end != null && now > end!) {
      return ElevatedButton(
        onPressed: null,
        child: const Text("Exam ended"),
      );
    }

// ✅ Start new attempt
return ElevatedButton(
  style: ElevatedButton.styleFrom(backgroundColor: AppColors.startExam),
  child: const Text("Start Exam"),
  onPressed: () async {
    await db
        .collection("examResults")
        .doc(widget.examId)
        .collection(studentId!)
        .doc("result")
        .set({
      "examId": widget.examId,
      "studentId": studentId,
      "status": "in-progress",
      "startedAt": DateTime.now(),
    });

    // Start Exam
context.goNamed(
  'exam',
  pathParameters: {
    "examId": widget.examId,
    "studentId": studentId!,
  },
);
  },
);
  },
),
              ],
            ),
          );
        },
      ),
    );
  }
}
