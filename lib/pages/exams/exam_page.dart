// lib/pages/exams/exam_page.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/question_model.dart';
import '../../theme/colors.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: avoid_web_libraries_in_flutter
import 'exam_page_stub.dart'
    if (dart.library.html) 'exam_page_web.dart';

class ExamPage extends StatefulWidget {
  final String examId;
  final String studentId;

  const ExamPage({
    super.key,
    required this.examId,
    required this.studentId,
  });

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

  List<String> matchingPool = [];

  DateTime? endTime;
  Duration remaining = Duration.zero;
  Timer? countdownTimer;

  String teacherId = "";

  final webHandlers = WebLifecycleHandlers();

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      webHandlers.setup(
      _logCheatingEvent,
      () => _examFinished,
      _showWarning,
      );
    }
    WidgetsBinding.instance.addObserver(this);
    _initAndLoad();
  }

  /// ------------------------ INIT & LOAD ------------------------
  Future<void> _initAndLoad() async {
    final prefs = await SharedPreferences.getInstance();

    // restore current index
    int? savedIndex = prefs.getInt("currentIndex");

    // fetch exam doc
    final examDoc = await db.collection("exams").doc(widget.examId).get();
    teacherId = examDoc.data()?['teacherId'] ?? "";

    // fetch questions
    final questionsSnap = await examDoc.reference.collection("questions").get();
    List<QuestionModel> allQuestions =
        questionsSnap.docs.map((d) => QuestionModel.fromFirestore(d)).toList();

    // ------- TYPE-BASED SHUFFLE -------
    // group by type
    final Map<String, List<QuestionModel>> typeGroups = {};
    for (var q in allQuestions) {
      typeGroups.putIfAbsent(q.type.toLowerCase(), () => []).add(q);
    }

    // shuffle within type
    List<QuestionModel> shuffled = [];
    typeGroups.forEach((type, list) {
      list.shuffle(Random());
      shuffled.addAll(list);
    });

    questions = shuffled;

    // restore answers from local prefs
    Map<int, String> restoredAnswers = {};
    for (int i = 0; i < questions.length; i++) {
      final ans = prefs.getString("answer_$i");
      if (ans != null) restoredAnswers[i] = ans;
    }
    answers = restoredAnswers;

    // build matching pool if needed
    final pool = <String>[];
    for (var q in questions) {
      if (q.type.toLowerCase() == "matching" && q.options != null) pool.addAll(q.options!);
    }
    pool.shuffle(Random());
    final seen = <String>{};
    matchingPool = pool.where((item) => seen.add(item)).toList();

    // load end time
    final endTs = examDoc.data()?["endTime"];
    if (endTs is Timestamp) {
    endTime = endTs.toDate();
      _startCountdownIfNeeded();
    } else {
      debugPrint("⚠️ No valid endTime set for exam ${widget.examId}");
    }

    setState(() {
      currentIndex = savedIndex ?? 0;
      loading = false;
    });
    

    // restore Firestore answers
    await _restoreAnswersFromFirestore();
    

    // ensure result doc exists
    final examRef = db.collection("examResults").doc(widget.examId);
    // ✅ ensure main examId doc has teacherId
    await examRef.set({
      "teacherId": teacherId, // 👈 added here
    }, SetOptions(merge: true));
    
    final resultRef = examRef.collection(widget.studentId).doc("result");

  // check if student already has result status
    final resultSnap = await resultRef.get();
      if (resultSnap.exists) {
        final data = resultSnap.data() ?? {};
        final status = data["status"]?.toString() ?? "";
      if (status == "incomplete" || status == "submitted") {
        if (mounted) {
          _showWarning("🚫 You cannot re-enter this exam.");
          Navigator.of(context).pop(); // or context.go('/examHistory');
        }
        return; // stop init completely
      }
    }
    await resultRef.set({
      "examId": widget.examId,
      "studentId": widget.studentId,
      "status": "in-progress",
      "cheatingCount": 0,
      "lastSavedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // restore cheating count
     final latestSnap = await resultRef.get();
    if (latestSnap.exists) cheatingCount = latestSnap.data()?["cheatingCount"] ?? 0;
  }

  /// ------------------------ ANSWER SAVE & RESTORE ------------------------
  Future<void> _saveAnswer(int displayIndex, String? answerStr) async {
  if (answerStr == null) return;
  final q = questions[displayIndex];
  answers[displayIndex] = answerStr;

  try {
    final examRef = db.collection("examResults").doc(widget.examId);
    final resultRef = examRef.collection(widget.studentId).doc("result");

    // ❌ Removed redundant teacherId / metadata writes
    // ✅ Only save the answer itself
    final answersCol = resultRef.collection("answers");
    await answersCol.doc(q.id).set({
      "questionId": q.id,
      "question": q.questionText,
      "answer": answerStr,
      "correctAnswer": q.correctAnswer,
      "displayIndex": displayIndex,
      // ❌ removed "timestamp"
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

  // cancel any pending save
  _saveDebounce?.cancel();

  // wait 2 seconds after last change
  _saveDebounce = Timer(const Duration(seconds: 2), () {
    _saveAnswer(currentIndex, selected);
  });

  setState(() {});
  }


  Future<void> _nextPressed() async {
  _saveDebounce?.cancel(); // cancel any pending debounce
  await _saveAnswer(currentIndex, answers[currentIndex]); // force flush
  await _saveProgressLocally();

  if (currentIndex + 1 < questions.length) {
    setState(() => currentIndex++);
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

  /// ------------------------ COUNTDOWN ------------------------
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

  /// ------------------------ CHEATING TRACK ------------------------
  Future<void> _logCheatingEvent() async {
  if (_examFinished) return;
  try {
    final examRef = db.collection("examResults").doc(widget.examId);
    final resultRef = examRef.collection(widget.studentId).doc("result");

    await resultRef.set({
      "examId": widget.examId,
      "studentId": widget.studentId,
      "status": "in-progress",
      "lastCheatingUpdate": FieldValue.serverTimestamp(),
      "cheatingCount": FieldValue.increment(1), // ✅ atomic increment
    }, SetOptions(merge: true));

    // keep local counter in sync (optional, not critical)
    cheatingCount++;
  } catch (e) {
    debugPrint("logCheatingEvent error: $e");
  }
  }

  Future<void> _markIncompleteIfNeeded() async {
    try {
      final ref = db.collection("examResults").doc(widget.examId).collection(widget.studentId).doc("result");
      final snap = await ref.get();
      if (snap.exists && snap.data()?["status"] != "completed") {
        await ref.set({"status": "incomplete", "submittedAt": FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("markIncomplete error: $e");
    }
  }

  /// ------------------------ SUBMIT ------------------------
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
          if (correct.map((c) => c.toString().toLowerCase()).contains(ans.toLowerCase())) computedScore++;
        } else if (correct != null) {
          if (ans.toLowerCase() == correct.toString().toLowerCase()) computedScore++;
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

      final prefs = await SharedPreferences.getInstance();
      for (int i = 0; i < questions.length; i++) {
        await prefs.remove("answer_$i");
      }

      if (mounted) {
        context.goNamed(
          'examResult',
          pathParameters: {'examId': widget.examId, 'studentId': widget.studentId},
        );
      }
    } catch (e) {
      debugPrint("submitExam error: $e");
      await _markIncompleteIfNeeded();
    } finally {
      submitting = false;
      if (mounted) setState(() {});
    }
  }

  /// ------------------------ LIFECYCLE ------------------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
  if (!kIsWeb) {
    if (state == AppLifecycleState.paused && !_examFinished) {
      _logCheatingEvent();
      _showWarning("⚠️ You minimized/alt-tabbed. Stay focused!");
      _saveProgressLocally();
    }

    // ✅ More reliable than only detached
    if ((state == AppLifecycleState.inactive || state == AppLifecycleState.detached) && !_examFinished) {
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
    webHandlers.dispose();
    _saveDebounce?.cancel(); // cancel pending answer save

    unawaited(_markIncompleteIfNeeded()
      .timeout(const Duration(seconds: 2), onTimeout: () {
    debugPrint("⚠️ Dispose incomplete flush timed out");
    }));
    
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  /// ------------------------ UI ------------------------
  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (questions.isEmpty) return const Scaffold(body: Center(child: Text("No questions found")));

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
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(q.questionText ?? "Question", style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 20),
              Text("Remaining Time: ${_formatRemaining(remaining)}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black)),
              const SizedBox(height: 10),
              // multiple-choice
              if (q.type.toLowerCase() == "multiple-choice" && q.options != null)
                Column(
                  children: q.options!.map((opt) {
                    final selected = answers[currentIndex];
                    return RadioListTile<String>(
                      title: Text(opt),
                      value: opt,
                      groupValue: selected,
                      onChanged: (val) => val != null ? _onOptionSelected(val) : null,
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
                      onChanged: (val) => val != null ? _onOptionSelected(val) : null,
                    );
                  }).toList(),
                ),
              // matching
              if (q.type.toLowerCase() == "matching")
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: answers[currentIndex],
                  hint: const Text("Select match"),
                  items: matchingPool.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) => val != null ? _onOptionSelected(val) : null,
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.purple500, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
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
                                    "You have answered ${answers.length} out of ${questions.length} questions. Do you want to submit?"),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Cancel")),
                                  ElevatedButton(
                                    onPressed: submitting
                                      ? null
                                      : () {
                                        Navigator.of(context).pop();
                                        _submitExam();
                                        },
                                    child: const Text("Submit"),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                  child: Text(submitting
                      ? "Please wait..."
                      : (currentIndex + 1 < questions.length ? "Next" : "Submit")),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
