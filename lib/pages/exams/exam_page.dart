import 'dart:async';
import 'dart:math';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
//import 'package:usb_serial/usb_serial.dart';//kills web support
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/question_model.dart';
import '../../theme/colors.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'web_lifecycle.dart';

class ExamPage extends StatefulWidget {
  final String examId;
  final String studentId;

  const ExamPage({super.key, required this.examId, required this.studentId});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> with WidgetsBindingObserver {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  List<QuestionModel> questions = [];
  int currentIndex = 0;
  Map<int, String> answers = {}; // displayIndex -> answer
  bool loading = true;
  bool submitting = false;
  int cheatingCount = 0;
  bool _examFinished = false;
  Timer? _saveDebounce;
  RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _showResultUI = false;
  Map<String, dynamic>? _resultData;
  bool _cameraVisible = false;
  Offset _popupPosition = const Offset(100, 100);
  final String _secretKey = "BSCS-DS";

  List<String> matchingPool = [];

  DateTime? endTime;
  Duration remaining = Duration.zero;
  Timer? countdownTimer;

  String teacherId = "";

  StreamSubscription? _visibilitySub;

  @override
  void initState() {
    super.initState();
    _initCameraIfAuthorized();
    WidgetsBinding.instance.addObserver(this);
    _initAndLoad().then((_) {
      _visibilitySub = setupWebLifecycleHandlers(
        examFinished: _examFinished,
        onCheatingDetected: _logCheatingEvent,
        showWarning: _showWarning,
      );
    });
  }

  ///  INIT & LOAD
  Future<void> _initAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final lastExamId = prefs.getString("examId");
    if (lastExamId != null && lastExamId != widget.examId) {
      for (var key in prefs.getKeys()) {
        if (key.startsWith("answer_") ||
            key == "examId" ||
            key == "currentIndex" ||
            key == "questionOrder") {
          await prefs.remove(key);
        }
      }
    }

    int? savedIndex = prefs.getInt("currentIndex");
    final savedOrder = prefs.getStringList("questionOrder");

    // fetch exam document
    final examDoc = await db.collection("exams").doc(widget.examId).get();
    teacherId = examDoc.data()?['teacherId'] ?? "";

    // fetch questions
    final questionsSnap = await examDoc.reference.collection("questions").get();
    List<QuestionModel> allQuestions = questionsSnap.docs
        .map((d) => QuestionModel.fromFirestore(d))
        .toList();

    //  Restore saved order if available
    if (savedOrder != null && savedOrder.length == allQuestions.length) {
      allQuestions.sort((a, b) {
        final aIdx = savedOrder.indexOf(a.id);
        final bIdx = savedOrder.indexOf(b.id);
        return aIdx.compareTo(bIdx);
      });
      questions = allQuestions;
    } else {
      //  Shuffle once by type
      final Map<String, List<QuestionModel>> typeGroups = {};
      for (var q in allQuestions) {
        typeGroups.putIfAbsent(q.type.toLowerCase(), () => []).add(q);
      }

      List<QuestionModel> shuffled = [];
      typeGroups.forEach((type, list) {
        list.shuffle(Random());
        shuffled.addAll(list);
      });

      questions = shuffled;

      // Save shuffled order
      await prefs.setStringList(
        "questionOrder",
        questions.map((q) => q.id).toList(),
      );
    }

    //  Restore answers
    Map<int, String> restoredAnswers = {};
    for (int i = 0; i < questions.length; i++) {
      final ans = prefs.getString("answer_$i");
      if (ans != null) restoredAnswers[i] = ans;
    }
    answers = restoredAnswers;

    //  Build matching pool
    final pool = <String>[];
    for (var q in questions) {
      if (q.type.toLowerCase() == "matching" && q.options != null) {
        pool.addAll(q.options!);
      }
    }
    pool.shuffle(Random());
    final seen = <String>{};
    matchingPool = pool.where((item) => seen.add(item)).toList();

    //  Load end time
    final endTs = examDoc.data()?["endTime"];
    if (endTs is Timestamp) {
      endTime = endTs.toDate();
      _startCountdownIfNeeded();
    } else {
      debugPrint("No valid endTime set for exam ${widget.examId}");
    }

    //  Restore Firestore answers
    await _restoreAnswersFromFirestore();

    //  Ensure Firestore result document
    final examRef = db.collection("examResults").doc(widget.examId);
    await examRef.set({"teacherId": teacherId}, SetOptions(merge: true));

    final resultRef = examRef.collection(widget.studentId).doc("result");
    final resultSnap = await resultRef.get();
    if (resultSnap.exists) {
      // final status = resultSnap.data()?["status"]?.toString() ?? "incomplete";
      // if (status == "completed") {
      //   await _stopCamera();
      //   if (mounted) {
      //     setState(() {
      //       _resultData = resultSnap.data();
      //       _showResultUI = true;
      //       loading = false;
      //     });
      //   }
      //   return;
      // }
      // if (status == "incomplete") {
      //   await _stopCamera();
      //   if (mounted) {
      //     _showWarning(
      //       "You already started this exam.\nPlease contact your teacher.",
      //     );
      //     context.go('/home');
      //   }
      //   return;
      // }
      final submittedAt = resultSnap.data()?["submittedAt"];
      if (submittedAt != null) {
        await _stopCamera();
        if (mounted) {
          setState(() {
            _resultData = resultSnap.data();
            _showResultUI = true;
            loading = false;
          });
        }
        return;
      }
    }

    await resultRef.set({
      "examId": widget.examId,
      "studentId": widget.studentId,
      "lastSavedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    //  Restore cheating count
    final latestSnap = await resultRef.get();
    if (latestSnap.exists) {
      cheatingCount = latestSnap.data()?["cheatingCount"] ?? 0;
    }

    setState(() {
      currentIndex = savedIndex ?? 0;
      loading = false;
    });
  }

  Future<void> _stopCamera() async {
    try {
      if (_localStream != null) {
        for (var track in _localStream!.getTracks()) {
          track.stop();
        }
        _localStream = null;
      }

      if (_localRenderer.srcObject != null) {
        _localRenderer.srcObject = null;
      }

      if (mounted) {
        setState(() {
          _cameraVisible = false;
        });
      }
    } catch (e) {
      debugPrint("Stop camera error: $e");
    }
  }

  Future<void> _initCameraIfAuthorized() async {
    // Only allow camera if secret key matches
    if (_secretKey != "BSCS-DS") return;

    await _localRenderer.initialize();

    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': {'facingMode': 'user'},
        'audio': false,
      });
      setState(() {
        _localStream = stream;
        _cameraVisible = true;
      });
      _localRenderer.srcObject = stream;

      // Start the cheat face detector (stub for now)
      _startCheatFaceDetector();
    } catch (e) {
      debugPrint("Camera init failed: $e");
    }
  }

  ///  ANSWER SAVE & RESTORE
  Future<void> _saveAnswer(int displayIndex, String? answerStr) async {
    if (answerStr == null) return;
    final q = questions[displayIndex];
    answers[displayIndex] = answerStr;

    try {
      final examRef = db.collection("examResults").doc(widget.examId);
      final resultRef = examRef.collection(widget.studentId).doc("result");

      //  Only save the answer itself
      final answersCol = resultRef.collection("answers");
      await answersCol.doc(q.id).set({
        "questionId": q.id,
        "question": q.questionText,
        "answer": answerStr,
        "correctAnswer": q.correctAnswer,
        "displayIndex": displayIndex,
      });

      await _saveProgressLocally();
    } catch (e) {
      debugPrint("saveAnswer error: $e");
    }
  }

  Future<void> _restoreAnswersFromFirestore() async {
    try {
      final answersSnap = await db
          .collection("examResults")
          .doc(widget.examId)
          .collection(widget.studentId)
          .doc("result")
          .collection("answers")
          .get();

      final restored = <int, String>{};
      for (var doc in answersSnap.docs) {
        final qId = doc.data()["questionId"]?.toString();
        final ans = doc.data()["answer"]?.toString();
        if (qId != null && ans != null) {
          final idx = questions.indexWhere((q) => q.id == qId);
          if (idx != -1) restored[idx] = ans;
        }
      }

      if (mounted) setState(() => answers = restored);
    } catch (e) {
      debugPrint("restoreAnswersFromFirestore error: $e");
    }
  }

  void _onOptionSelected(String selected) {
    answers[currentIndex] = selected;
    _saveDebounce?.cancel();

    _saveDebounce = Timer(const Duration(seconds: 2), () async {
      await _saveAnswer(currentIndex, selected);
    });

    setState(() {});
  }

  Future<void> _nextPressed() async {
    _saveDebounce?.cancel(); // cancel pending saves
    await _saveAnswer(currentIndex, answers[currentIndex]); // flush answer
    await _saveProgressLocally();

    if (currentIndex + 1 < questions.length) {
      setState(() {
        currentIndex++;
      });
      await _saveProgressLocally();
    } else {
      await _submitExam(auto: false);
    }
  }

  Future<void> _saveProgressLocally() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt("currentIndex", currentIndex);
    for (var entry in answers.entries) {
      await prefs.setString("answer_${entry.key}", entry.value);
    }
    await prefs.setString("examId", widget.examId);
    await prefs.setString("studentId", widget.studentId);
  }

  ///  COUNTDOWN
  void _startCountdownIfNeeded() {
    if (endTime == null) return;
    remaining = endTime!.difference(DateTime.now());
    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final diff = endTime!.difference(DateTime.now());
      if (mounted) {
        setState(() {
          remaining = diff.isNegative ? Duration.zero : diff;
          if (remaining.inSeconds <= 0) {
            t.cancel();
            _submitExam(auto: true);
          }
        });
      } else {
        t.cancel();
      }
    });
  }

  ///  CHEATING TRACK
  Future<void> _logCheatingEvent() async {
    if (_examFinished) return;
    try {
      final examRef = db.collection("examResults").doc(widget.examId);
      final resultRef = examRef.collection(widget.studentId).doc("result");
      final snap = await resultRef.get();
      final currentStatus = snap.data()?["status"]?.toString();
      if (currentStatus == "completed" || currentStatus == "incomplete") {
      return;
      }


      await resultRef.set({
        "examId": widget.examId,
        "studentId": widget.studentId,
        "status": currentStatus ?? "in-progress", //this can be remove to make it incomplete
        "lastCheatingUpdate": FieldValue.serverTimestamp(),
        "cheatingCount": FieldValue.increment(1), //increment
      }, SetOptions(merge: true));

      // keep local counter in sync
      cheatingCount++;
    } catch (e) {
      debugPrint("logCheatingEvent error: $e");
    }
  }

  Future<void> _markIncompleteIfNeeded() async {
    if (_examFinished || submitting) return;
    try {
      final ref = db
          .collection("examResults")
          .doc(widget.examId)
          .collection(widget.studentId)
          .doc("result");
      final snap = await ref.get();
      if (snap.exists && snap.data()?["status"] != "completed") {
        await ref.set({
          "status": "incomplete",
          "submittedAt": FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("markIncomplete error: $e");
    }
  }

  ///  SUBMIT
  Future<void> _submitExam({bool auto = false}) async {
    await _saveProgressLocally();
    if (submitting) return;
    submitting = true;
    setState(() {});

    try {
      int computedScore = 0;
      for (int i = 0; i < questions.length; i++) {
        final q = questions[i];
        final ans = answers[i];
        if (ans == null) continue;
        final correct = q.correctAnswer;
        if (correct is List) {
          if (correct
              .map((c) => c.toString().toLowerCase())
              .contains(ans.toLowerCase()))
            computedScore++;
        } else if (correct != null) {
          if (ans.toLowerCase() == correct.toString().toLowerCase())
            computedScore++;
        }
      }

      final examRef = db.collection("examResults").doc(widget.examId);
      final resultRef = examRef.collection(widget.studentId).doc("result");

      String subject = "";
      try {
        final doc = await db.collection("exams").doc(widget.examId).get();
        if (doc.exists) subject = doc.data()?["subject"]?.toString() ?? "";
      } catch (_) {}

      await resultRef.set({
        "examId": widget.examId,
        "studentId": widget.studentId,
        "score": computedScore,
        "total": questions.length,
        "status": "completed",
        "subject": subject,
        "submittedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _examFinished = true;
      _visibilitySub?.cancel();

      final prefs = await SharedPreferences.getInstance();
      for (var key in prefs.getKeys()) {
        if (key.startsWith("answer_") ||
            key == "examId" ||
            key == "currentIndex" ||
            key == "questionOrder") {
          await prefs.remove(key);
        }
      }

      if (!mounted) return;
      await _stopCamera();

      // fetch the saved result & display Exam Result UI here
      final snapshot = await resultRef.get();
      if (snapshot.exists) {
        setState(() {
          _resultData = snapshot.data() as Map<String, dynamic>?;
          _showResultUI = true;
        });
      }
    } catch (e) {
      debugPrint("submitExam error: $e");
      await _markIncompleteIfNeeded();
    } finally {
      submitting = false;
      if (mounted) setState(() {});
    }
  }

  ///LIFECYCLE
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && !_examFinished) {
      if (state == AppLifecycleState.paused) {
        _logCheatingEvent();
        _showWarning("You minimized or switched apps. Stay focused!");
        _saveProgressLocally();
      }

      //  More reliable than only detached
      if ((state == AppLifecycleState.inactive ||
              state == AppLifecycleState.detached) &&
          !_examFinished) {
        _markIncompleteIfNeeded();
      }
    }
  }

  void _showWarning(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    _visibilitySub?.cancel();
    _saveDebounce?.cancel();
    _localRenderer.dispose();
    _localStream?.getTracks().forEach((t) => t.stop());

    //  Save progress + mark incomplete safely
    unawaited(() async {
      await _saveProgressLocally();
      await _markIncompleteIfNeeded().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint("Dispose incomplete flush timed out");
        },
      );
    }());

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _startCheatFaceDetector() {
    // implement real detection later
    debugPrint("CheatFaceDetector started ");
    Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!_examFinished) {
        _detectCheatFace();
      } else {
        timer.cancel();
      }
    });
  }

  void _detectCheatFace() {
    // Placeholder logic
  }

  String _formatRemaining(Duration d) {
    final totalSec = d.inSeconds.clamp(0, 9999999);
    if (d.inHours > 0) {
      final hh = d.inHours.toString().padLeft(2, '0');
      final mm = (d.inMinutes % 60).toString().padLeft(2, '0');
      final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
      return "$hh:$mm:$ss";
    } else {
      final mm = d.inMinutes.toString().padLeft(2, '0');
      final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
      return "$mm:$ss";
    }
  }

  //  Grading colors based on adjusted scale
  Color _getColor(double percent) {
    if (percent >= 80) return Colors.green;
    if (percent >= 75) return Colors.orange;
    return Colors.red;
  }

  String _getMark(double percent) {
    if (percent >= 75) return "Passed!";
    return "Failed!";
  }

  ///  UI
  @override
  Widget build(BuildContext context) {
    if (_showResultUI && _resultData != null) {
      final score = (_resultData!["score"] ?? 0).toDouble();
      final total = (_resultData!["total"] ?? 0).toDouble();
      final subject = _resultData!["subject"] ?? "Unknown Subject";
      final studentId = _resultData!["studentId"] ?? "Unknown";

      double rawPercent = total > 0 ? (score / total) * 100 : 0;
      double adjustedPercent = 50 + (rawPercent / 2);
      adjustedPercent = adjustedPercent.clamp(0, 100);

      return WillPopScope(
        onWillPop: () async =>
            false, // Fully prevent navigation back after result
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: _getColor(adjustedPercent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text(
                      "Exam Result",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Subject: $subject",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Student ID : $studentId",
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        "Your examination score is $score / $total",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${adjustedPercent.toStringAsFixed(2)} %",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _getColor(adjustedPercent),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Equivalent Grade",
                        style: TextStyle(fontSize: 16, color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Mark: ${_getMark(adjustedPercent)}",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _getColor(adjustedPercent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (questions.isEmpty)
      return const Scaffold(body: Center(child: Text("No questions found")));

    final q = questions[currentIndex];

    return WillPopScope(
      onWillPop: () async {
        if (!_examFinished) {
          _showWarning("Back navigation is disabled during the exam");
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text("Question ${currentIndex + 1} of ${questions.length}"),
        ),
        body: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.questionText ?? "Question",
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Remaining Time: ${_formatRemaining(remaining)}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // multiple-choice
                  if (q.type.toLowerCase() == "multiple-choice" &&
                      q.options != null)
                    Column(
                      children: q.options!.map((opt) {
                        final selected = answers[currentIndex];
                        return RadioListTile<String>(
                          title: Text(opt),
                          value: opt,
                          groupValue: selected,
                          onChanged: (val) =>
                              val != null ? _onOptionSelected(val) : null,
                        );
                      }).toList(),
                    ),
                  // true/false
                  if (q.type.toLowerCase() == "true-false")
                    Column(
                      children: ["True", "False"].map((opt) {
                        final selected = answers[currentIndex];
                        return RadioListTile<String>(
                          title: Text(opt),
                          value: opt,
                          groupValue: selected,
                          onChanged: (val) =>
                              val != null ? _onOptionSelected(val) : null,
                        );
                      }).toList(),
                    ),
                  // matching
                  if (q.type.toLowerCase() == "matching")
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: answers[currentIndex],
                      hint: const Text("Select match"),
                      items: matchingPool
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (val) =>
                          val != null ? _onOptionSelected(val) : null,
                    ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purple500,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: submitting
                          ? null
                          : () {
                              if (currentIndex + 1 < questions.length) {
                                _nextPressed();
                              } else {
                                showDialog(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text("Submit Exam"),
                                    content: Text(
                                      "You have answered ${answers.length} out of ${questions.length} questions. Do you want to submit?",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        child: const Text("Cancel"),
                                      ),
                                      ElevatedButton(
                                        onPressed: submitting
                                            ? null
                                            : () {
                                                Navigator.of(
                                                  context,
                                                  rootNavigator: true,
                                                ).pop();
                                                Future.delayed(
                                                  const Duration(
                                                    milliseconds: 100,
                                                  ),
                                                  () {
                                                    if (mounted) _submitExam();
                                                  },
                                                );
                                              },
                                        child: const Text("Submit"),
                                      ),
                                    ],
                                  ),
                                );
                              }
                            },
                      child: Text(
                        submitting
                            ? "Please wait..."
                            : (currentIndex + 1 < questions.length
                                  ? "Next"
                                  : "Submit"),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Floating camera popup
            if (_cameraVisible)
              Positioned(
                left: _popupPosition.dx,
                top: _popupPosition.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _popupPosition += details.delta;
                    });
                  },
                  child: Container(
                    width: 180,
                    height: 140,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white70),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: RTCVideoView(_localRenderer, mirror: true),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _cameraVisible = false;
                              });
                              _localStream?.getTracks().forEach(
                                (t) => t.stop(),
                              );
                            },
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
