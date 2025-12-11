import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_flutter_app/theme/colors.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../helpers/cheat_detector.dart';

class TakeExamPage extends StatefulWidget {
  final String examId;
  final int? startMillis;
  final int? endMillis;
  final String? studentId;

  const TakeExamPage({
    super.key,
    required this.examId,
    this.studentId,
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

  bool _hasCamera = false;
  bool _checkingCamera = true;
  MediaStream? _cameraStream;

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

  Future<bool> _checkCameraAvailability() async {
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final hasVideoInput = devices.any((d) => d.kind == 'videoinput');
      if (!hasVideoInput) return false;

      // Try to open the camera
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': false,
      });

      final videoRenderer = RTCVideoRenderer();
      await videoRenderer.initialize();
      videoRenderer.srcObject = stream;

      // Show a dialog for 5 seconds and auto-close it
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            // Auto-close after 5 seconds
            Future.delayed(const Duration(seconds: 5), () {
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            });

            return AlertDialog(
              title: const Text('Camera Test'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Please look at the screen'),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 240,
                    height: 180,
                    child: RTCVideoView(videoRenderer, mirror: true),
                  ),
                ],
              ),
            );
          },
        );
      }

      // Wait for 5 seconds (same as dialog)
      await Future.delayed(const Duration(seconds: 5));
      _detectFace();

      // Stop and clean up
      stream.getTracks().forEach((t) => t.stop());
      await videoRenderer.dispose();

      return true;
    } catch (e) {
      debugPrint("Camera test failed: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Camera test failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  // Placeholder for future face detection logic
  void _detectFace() {
    //: implement face detection
  }

  //  Anti-tab-switch: warn when app goes background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !isWarningShown) {
      isWarningShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(" Don’t leave the app during the exam!"),
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
      return const Scaffold(body: Center(child: Text(" Not logged in")));
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Column(
          children: [
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 8),
                  const Text(
                    'Exam Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<DocumentSnapshot>(
                future: db.collection("exams").doc(widget.examId).get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.data!.exists) {
                    // Fallback: examResults
                    return StreamBuilder<DocumentSnapshot>(
                      stream: db
                          .collection("examResults")
                          .doc(widget.examId)
                          .collection("students")
                          .doc(studentId!)
                          .snapshots(),
                      builder: (context, resultSnap) {
                        if (!resultSnap.hasData || !resultSnap.data!.exists) {
                          return const Center(child: Text("Exam not found"));
                        }

                        final resultData =
                            resultSnap.data!.data() as Map<String, dynamic>? ??
                            {};

                        final subject = resultData["subject"];
                        final startedAt = resultData["startedAt"];
                        final submittedAt = resultData["submittedAt"];
                        final status = resultData["status"];

                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (subject != null)
                                Text(
                                  subject,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFE6F0F8),
                                  ),
                                ),
                              if (startedAt != null)
                                Text(
                                  "Started: ${DateFormat("MMM d, yyyy h:mm a").format(startedAt.toDate())}",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFFE6F0F8),
                                  ),
                                )
                              else if (submittedAt != null)
                                Text(
                                  "Submitted: ${DateFormat("MMM d, yyyy h:mm a").format(submittedAt.toDate())}",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFFE6F0F8),
                                  ),
                                ),
                              if (status != null)
                                Text(
                                  "Status: $status",
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFFE6F0F8),
                                  ),
                                ),
                              const SizedBox(height: 16),

                              // Instructions Box (added here)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F3B61),
                                  border: Border.all(
                                    color: Colors.red,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: RichText(
                                  textAlign: TextAlign.start,
                                  text: const TextSpan(
                                    style: TextStyle(
                                      color: Color(0xFFE6F0F8),
                                      fontSize: 14,
                                      height: 1.4,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: "IMPORTANT:\n",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text:
                                            "Instructions:\n- Don’t switch tabs\n- Don’t leave the app\n- Look at the screen it may trigger as cheating.",
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (submittedAt != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    "Submitted: ${DateFormat("MMM d, yyyy h:mm a").format(submittedAt.toDate())}",
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFFE6F0F8),
                                    ),
                                  ),
                                ),

                              const Spacer(),

                              // Same View Result button design
                              if (status == "completed")
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.viewResult,
                                  ),
                                  child: const Text("View Result"),
                                  onPressed: () {
                                    context.goNamed(
                                      'examResult',
                                      pathParameters: {'examId': widget.examId},
                                    );
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  }

                  final data = snapshot.data!.data() as Map<String, dynamic>;
                  final subject = data["subject"] ?? "Unknown";
                  final teacherId = data["teacherId"] ?? "";
                  start =
                      widget.startMillis ??
                      data["startTime"]?.toDate().millisecondsSinceEpoch;
                  end =
                      widget.endMillis ??
                      data["endTime"]?.toDate().millisecondsSinceEpoch;

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFE6F0F8),
                          ),
                        ),
                        if (start != null)
                          Text(
                            "Start: ${formatDate(start!)}",
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFFE6F0F8),
                            ),
                          ),
                        const SizedBox(height: 16),

                        // Instructions Box
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F3B61),
                            border: Border.all(color: Colors.red, width: 2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: RichText(
                            textAlign: TextAlign.start,
                            text: const TextSpan(
                              style: TextStyle(
                                color: Color(0xFFE6F0F8),
                                fontSize: 14,
                                height: 1.4,
                              ),
                              children: [
                                TextSpan(
                                  text: "IMPORTANT:\n",
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                TextSpan(
                                  text:
                                      "Instructions:\n- Don’t switch tabs\n- Don’t leave the app\n- Look at the screen it may trigger as cheating.",
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Divider(color: Colors.grey[400]),

                        //  Teacher name
                        Text(
                          "Teacher: ${data["creator"] ?? data["teacher"] ?? data["createdBy"] ?? "Unknown"}",
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFFE6F0F8),
                          ),
                        ),

                        //  Duration
                        if (start != null && end != null)
                          Text(
                            "${formatDate(start!)} - ${DateFormat("h:mm a").format(DateTime.fromMillisecondsSinceEpoch(end!))}",
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFFE6F0F8),
                            ),
                          ),

                        const Spacer(),

                        //  Start / Resume / View Result button (real-time updates)
                        StreamBuilder<DocumentSnapshot>(
                          stream: db
                              .collection("examResults")
                              .doc(widget.examId)
                              .collection("students")
                              .doc(studentId!)
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

                            //  Completed
                            if (doc.exists && doc["status"] == "completed") {
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.viewResult,
                                ),
                                child: const Text("View Result"),
                                onPressed: () {
                                  // View Result
                                  context.goNamed(
                                    'examResult',
                                    pathParameters: {
                                      'examId': widget.examId,
                                      //'studentId': studentId!,
                                    },
                                  );
                                },
                              );
                            }

                            //  In-progress
                            if (doc.exists && doc["status"] == "in-progress") {
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.resumeExam,
                                ),
                                child: const Text("Exam being taken"),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Exam is already being taken",
                                      ),
                                    ),
                                  );
                                },
                              );
                            }
                            if (doc.exists && doc["status"] == "incomplete") {
                              return ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color.fromARGB(
                                    255,
                                    255,
                                    0,
                                    0,
                                  ),
                                ),
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

                            //  Exam not started yet
                            if (start != null && now < start!) {
                              return ElevatedButton(
                                onPressed: null,
                                child: const Text("Exam not started yet"),
                              );
                            }

                            //  Exam ended
                            if (end != null && now > end!) {
                              return ElevatedButton(
                                onPressed: null,
                                child: const Text("Exam ended"),
                              );
                            }

                            //  Start new attempt
                            return ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.startExam,
                              ),
                              child: const Text("Start Exam"),
                              onPressed: () async {
                                bool hasCamera =
                                    await _checkCameraAvailability();
                                if (!hasCamera) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "No camera detected! You cannot take the exam.",
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  return; // Stop here if no camera
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Camera test completed!"),
                                    backgroundColor: Colors.green,
                                  ),
                                );

                                // Save student exam result
                                await db
                                    .collection("examResults")
                                    .doc(widget.examId)
                                    .collection("students")
                                    .doc(studentId!)
                                    .set({
                                      "examId": widget.examId,
                                      "studentId": studentId,
                                      "status": "in-progress",
                                      "cheatingCount": 0,
                                      "currentIndex": 0,
                                      "subject": subject,
                                    });

                                context.goNamed(
                                  'examhtml',
                                  pathParameters: {"examId": widget.examId},
                                );

                                // Start Exam
                                // context.goNamed(
                                //   'examhtml',
                                //   pathParameters: {
                                //     "examId": widget.examId,
                                //     "studentId": studentId!,
                                //   },
                                // );
                              },
                            );
                          },
                        ),
                      ],
                    ),
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
