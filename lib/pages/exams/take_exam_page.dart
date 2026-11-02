import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../helpers/SecureStorageHelper.dart';
import '../../helpers/notifications_helper.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/gaze_calibration_overlay.dart';
import '../../helpers/screen_share.dart';
import '../../helpers/platform_utils.dart';

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
  // Shared theme palette (same as ProfilePage / HomePage / ExamListPage)
  static const Color _bgColor = Color(0xFFF7F8F6);
  static const Color _headerColor = Color(0xFF111217);
  static const Color _headerColorLight = Color(0xFF202127);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _textColor = Color(0xFF17181D);
  static const Color _mutedTextColor = Color(0xFF777B80);
  static const Color _accentColor = Color(0xFF087B4F);
  static const Color _successColor = Color(0xFF12815B);
  static const Color _errorColor = Color(0xFFBD2942);
  static const Color _warnColor = Color(0xFFB88826);

  // Button colors
  static const Color _btnStart = Color(0xFF087B4F);
  static const Color _btnResult = Color(0xFF12815B);
  static const Color _btnProgress = Color(0xFFB88826);
  static const Color _btnIncomplete = Color(0xFFBD2942);

  final db = FirebaseFirestore.instance;
  String? studentId;
  int? start;
  int? end;
  bool _monitoringEnabled = false; // set from the exam document in build()

  bool _leftApp = false; // app went to background
  bool _starting = false; // Start Exam flow is running
  bool _dialogOpen = false; // an error popup is showing
  String? _cameraError; // last camera test error (for the popup details)

  final _screen = ScreenShare();

  late Stream<DocumentSnapshot> _examStream;
  Stream<DocumentSnapshot>? _resultStream;

  // Ticks once a second, but only rebuilds when the exam crosses a boundary
  // (not started -> open -> ended).
  Timer? _ticker;
  int _lastPhase = -1;

  /// 0 = not started yet, 1 = open, 2 = ended
  int _computePhase() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (start != null && now < start!) return 0;
    if (end != null && now > end!) return 2;
    return 1;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindExam();
    _loadStudentId();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final phase = _computePhase();
      if (phase != _lastPhase) {
        _lastPhase = phase;
        setState(() {}); // re-evaluates Not started / Start / Ended
      }
    });
  }

  void _bindExam() {
    _examStream = db.collection("exams").doc(widget.examId).snapshots();
    _resultStream = null;
    start = widget.startMillis;
    end = widget.endMillis;
    _monitoringEnabled = false;
    _lastPhase = -1;
    unawaited(markExamNotificationViewed(widget.examId));
  }

  @override
  void didUpdateWidget(covariant TakeExamPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.examId != widget.examId) {
      _bindExam();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (!_screen.handedOff) {
      _screen.stop();
    }
    super.dispose();
  }

  Future<void> _loadStudentId() async {
    final storedstudentId = await SecureStorageHelper.read('studentId');
    if (!mounted) return;
    setState(() {
      studentId = storedstudentId;
    });
  }

  // ---------- Error popup ----------

  Future<void> _showErrorDialog({
    required String title,
    required String message,
    IconData icon = Icons.error_outline,
    Color color = _errorColor,
    String? details,
  }) async {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withOpacity(0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(0.4)),
                    boxShadow: [
                      BoxShadow(
                        color: color.withOpacity(0.35),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 30, color: color),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _mutedTextColor,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (details != null && details.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      details,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _mutedTextColor,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text("OK"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    _dialogOpen = false;
  }

  // ---------- Single "ready" popup that frames BOTH permissions ----------

  Future<bool> _showReadyDialog() async {
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _accentColor.withOpacity(0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accentColor.withOpacity(0.4)),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    size: 30,
                    color: _accentColor,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Before you begin",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "This exam needs two things from your browser:\n\n"
                  "•  Full screen sharing (your ENTIRE screen, not a window or tab)\n"
                  "•  Camera access, for a quick look-at-the-camera check\n\n"
                  "You'll see two browser prompts next — please allow both.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _mutedTextColor,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text("Continue"),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: _mutedTextColor),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return proceed ?? false;
  }

  // ---------- Screen share (whole screen only) ----------

  Future<bool> _requestFullScreenShare() async {
    try {
      await _screen.request();
      return true;
    } catch (e) {
      if (mounted) {
        await _showErrorDialog(
          title: "Full screen sharing required",
          message:
              "You must share your ENTIRE screen to start the exam. Sharing a window or a single tab isn't allowed.",
          icon: Icons.screen_lock_portrait_outlined,
          details: e.toString(),
        );
      }
      return false;
    }
  }

  // ---------- Camera / permissions ----------

  /// Only asks for camera permission (no preview, no waiting). The stream is
  /// stopped right away so gaze calibration / exam.html can open the camera
  /// themselves without hitting "camera already in use".
  Future<bool> _checkCameraAvailability() async {
    _cameraError = null;
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final hasVideoInput = devices.any((d) => d.kind == 'videoinput');
      if (!hasVideoInput) {
        _cameraError = 'No camera was detected.';
        return false;
      }

      final stream = await navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': false,
      });

      stream.getTracks().forEach((t) => t.stop());
      await stream.dispose();
      return true;
    } catch (e) {
      debugPrint("Camera permission failed: $e");
      _cameraError = e.toString();
      return false;
    }
  }

  //  Anti-tab-switch: warn (popup) when the student comes back after leaving
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && !_starting) {
      _leftApp = true;
    }
    if (state == AppLifecycleState.resumed && _leftApp) {
      _leftApp = false;
      if (mounted) {
        _showErrorDialog(
          title: "Don't leave the app",
          message: "Don't leave the app during the exam!",
          icon: Icons.warning_amber_rounded,
          color: _warnColor,
        );
      }
    }
  }

  String formatDate(int millis, {bool withTime = true}) {
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return withTime
        ? DateFormat("MMM d, yyyy h:mm a").format(date)
        : DateFormat("MMM d, yyyy").format(date);
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) {
      return _pageShell(
        child: _buildEmptyState(Icons.lock_outline, "User not authenticated"),
      );
    }

    _resultStream ??= db
        .collection("examResults")
        .doc(widget.examId)
        .collection("students")
        .doc(uid)
        .snapshots();

    return _pageShell(
      child: StreamBuilder<DocumentSnapshot>(
        stream: _examStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildEmptyState(
              Icons.error_outline,
              "Couldn't load exam details",
            );
          }
          if (!snapshot.hasData) {
            return _buildSkeleton();
          }
          if (!snapshot.data!.exists) {
            return StreamBuilder<DocumentSnapshot>(
              stream: _resultStream,
              builder: (context, resultSnap) {
                if (resultSnap.connectionState == ConnectionState.waiting) {
                  return _buildSkeleton();
                }
                if (!resultSnap.hasData || !resultSnap.data!.exists) {
                  return _buildEmptyState(
                    Icons.search_off_outlined,
                    "Exam not found",
                  );
                }

                final resultData =
                    resultSnap.data!.data() as Map<String, dynamic>? ?? {};

                final subject = resultData["subject"];
                final startedAt = resultData["startedAt"];
                final submittedAt = resultData["submittedAt"];
                final status = resultData["status"];

                final fmt = DateFormat("MMM d, yyyy h:mm a");
                final rows = <_DetailRow>[
                  if (startedAt != null)
                    _DetailRow(
                      Icons.play_circle_outline,
                      "Started",
                      fmt.format(startedAt.toDate()),
                    ),
                  if (submittedAt != null)
                    _DetailRow(
                      Icons.task_alt_outlined,
                      "Submitted",
                      fmt.format(submittedAt.toDate()),
                    ),
                ];

                return _pageBody(
                  showSteps: status?.toString().toLowerCase() != "completed",
                  card: _detailsCard(
                    subject: (subject ?? "Exam").toString(),
                    status: status?.toString(),
                    rows: rows,
                    action: status == "completed"
                        ? _actionButton(
                            label: "View Result",
                            icon: Icons.assessment_outlined,
                            color: _btnResult,
                            hint: "Exam completed.",
                            onPressed: () {
                              context.goNamed(
                                'examResult',
                                pathParameters: {'examId': widget.examId},
                              );
                            },
                          )
                        : null,
                  ),
                );
              },
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final subject = data["subject"] ?? "Unknown";
          start =
              data["startTime"]?.toDate().millisecondsSinceEpoch ??
              widget.startMillis;
          end =
              data["endTime"]?.toDate().millisecondsSinceEpoch ??
              widget.endMillis;
          _lastPhase = _computePhase();

          // Used by _buildExamAction to show the gray "Need monitoring" button
          _monitoringEnabled = data["monitoringEnabled"] == true;

          final teacher =
              "${data["creator"] ?? data["teacher"] ?? data["createdBy"] ?? "Unknown"}";

          final rows = <_DetailRow>[
            if (start != null)
              _DetailRow(
                Icons.play_circle_outline,
                "Start",
                formatDate(start!),
              ),
            _DetailRow(Icons.person_outline, "Teacher", teacher),
            if (start != null && end != null)
              _DetailRow(
                Icons.schedule_outlined,
                "Schedule",
                "${formatDate(start!)} - ${DateFormat("h:mm a").format(DateTime.fromMillisecondsSinceEpoch(end!))}",
              ),
          ];

          return StreamBuilder<DocumentSnapshot>(
            stream: _resultStream,
            builder: (context, resSnap) {
              if (!resSnap.hasData && !resSnap.hasError) {
                return _buildSkeleton();
              }
              final res = resSnap.data?.data() as Map<String, dynamic>?;
              final resStatus = res?["status"]?.toString();
              final submittedAt = res?["submittedAt"];
              final done = resStatus?.toLowerCase() == "completed";
              final fmt = DateFormat("MMM d, yyyy h:mm a");

              return _pageBody(
                showSteps: !done,
                card: _detailsCard(
                  subject: subject.toString(),
                  status: resStatus,
                  rows: [
                    ...rows,
                    if (done && submittedAt is Timestamp)
                      _DetailRow(
                        Icons.task_alt_outlined,
                        "Submitted",
                        fmt.format(submittedAt.toDate()),
                      ),
                  ],
                  action: _buildExamAction(
                    subject.toString(),
                    uid,
                    resSnap.data,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Start / Resume / View Result button (real-time updates)
  Widget _buildExamAction(
    String subject,
    String uid, [
    DocumentSnapshot? initial,
  ]) {
    return StreamBuilder<DocumentSnapshot>(
      initialData: initial,
      stream: _resultStream,
      builder: (context, resultSnap) {
        if (resultSnap.hasError) {
          return _actionButton(
            label: "Error",
            icon: Icons.error_outline,
            color: _btnIncomplete,
            hint: "Couldn't load your exam status.",
            onPressed: () => _showErrorDialog(
              title: "Couldn't load exam status",
              message:
                  "We couldn't check your exam status. Please check your connection and try again.",
              details: resultSnap.error.toString(),
            ),
          );
        }
        if (!resultSnap.hasData) {
          return _actionButton(label: "Loading...", onPressed: null);
        }

        final doc = resultSnap.data!;
        final now = DateTime.now().millisecondsSinceEpoch;

        if (doc.exists && doc["status"] == "completed") {
          return _actionButton(
            label: "View Result",
            icon: Icons.assessment_outlined,
            color: _btnResult,
            hint: "Exam completed.",
            onPressed: () {
              context.goNamed(
                'examResult',
                pathParameters: {'examId': widget.examId},
              );
            },
          );
        }

        if (doc.exists && doc["status"] == "in-progress") {
          return _actionButton(
            label: "In progress",
            icon: Icons.hourglass_top_outlined,
            color: _btnProgress,
            hint: "Exam is already being taken.",
            onPressed: () => _showErrorDialog(
              title: "Exam in progress",
              message: "Exam is already being taken.",
              icon: Icons.hourglass_top_outlined,
              color: _warnColor,
            ),
          );
        }

        if (doc.exists && doc["status"] == "incomplete") {
          return _actionButton(
            label: "Incomplete",
            icon: Icons.block_outlined,
            color: _btnIncomplete,
            hint: "You can't take this exam.",
            onPressed: () => _showErrorDialog(
              title: "Exam incomplete",
              message: "You can't take the exam.",
              icon: Icons.block_outlined,
            ),
          );
        }

        if (start != null && now < start!) {
          return _actionButton(
            label: "Not started",
            icon: Icons.lock_clock_outlined,
            hint: "Exam not started yet.",
            onPressed: null,
          );
        }

        if (end != null && now > end!) {
          return _actionButton(
            label: "Ended",
            icon: Icons.event_busy_outlined,
            hint: "Exam ended.",
            onPressed: null,
          );
        }

        // Monitoring not enabled by the instructor: gray, disabled button
        if (!_monitoringEnabled) {
          return _actionButton(
            label: "Need monitoring",
            icon: Icons.visibility_off_outlined,
            color: Colors.grey,
            hint:
                "Your instructor must enable monitoring before you can start.",
            onPressed: null,
          );
        }

        //  Start new attempt — reordered flow: permission popup first,
        //  then full-screen check, then camera permission (no preview),
        //  then calibration runs last. Any failure keeps the student right
        //  here so they can retry.
        return _actionButton(
          label: "Start Exam",
          icon: Icons.play_arrow_rounded,
          color: _btnStart,
          hint:
              "You'll be asked to share your full screen and allow your camera.",
          onPressed: () async {
            if (_starting) return;
            _starting = true;

            try {
              // Fetch exam document to check monitoring settings
              final examDoc = await db
                  .collection("exams")
                  .doc(widget.examId)
                  .get();

              if (!examDoc.exists) {
                await _showErrorDialog(
                  title: "Exam not found",
                  message: "The exam document could not be found.",
                );
                return;
              }

              final examData = examDoc.data() ?? {};
              final monitoringEnabled = examData["monitoringEnabled"] == true;
              // Force isPc off where screen sharing can't exist
              final isPc = examData["isPc"] != false && ScreenShare.supported;

              // Backup check (the button is already gray if this is false)
              if (!monitoringEnabled) {
                await _showErrorDialog(
                  title: "Monitoring Required",
                  message:
                      "This exam requires monitoring to be enabled by your instructor before you can start.",
                  icon: Icons.lock_outline,
                  color: _warnColor,
                );
                return;
              }

              // Step 1: framing popup (first thing the student sees)
              final String dialogMessage = isPc
                  ? "This exam needs two things from your browser:\n\n"
                        "•  Full screen sharing (your ENTIRE screen, not a window or tab)\n"
                        "•  Camera access, for monitoring\n\n"
                        "You'll see two browser prompts next — please allow both. "
                        "After that, a quick eye calibration will start."
                  : "This exam needs camera access for monitoring.\n\n"
                        "You'll see a browser prompt next — please allow it. "
                        "After that, a quick eye calibration will start.";

              final agreed = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) {
                  return Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 380),
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: _accentColor.withOpacity(0.45),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: _accentColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _accentColor.withOpacity(0.4),
                              ),
                            ),
                            child: const Icon(
                              Icons.shield_outlined,
                              size: 30,
                              color: _accentColor,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "Before you begin",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            dialogMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _mutedTextColor,
                              fontSize: 13.5,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text("Continue"),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text(
                              "Cancel",
                              style: TextStyle(color: _mutedTextColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );

              if (agreed != true) return;

              // Step 2: screen share (PC exams only)
              if (isPc) {
                final screenOk = await _requestFullScreenShare();
                if (!mounted || !screenOk) return; // popup already shown
              }

              // Step 3: camera permission only (no preview)
              final cameraOk = await _checkCameraAvailability();
              if (!mounted) return;
              if (!cameraOk) {
                if (isPc) {
                  _screen.stop();
                }
                await _showErrorDialog(
                  title: "Camera not available",
                  message:
                      "No camera was detected or it is turned off. Turn on your camera, make sure no other app is using it, and allow camera access. You cannot take the exam without it.",
                  icon: Icons.videocam_off_outlined,
                  details: _cameraError,
                );
                return;
              }

              // Step 4: gaze calibration (runs AFTER permissions are granted)
              bool closed = false;
              final calibrationOk = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                barrierColor: const Color(0xF00B1220),
                useSafeArea: false,
                builder: (ctx) {
                  void close(bool ok) {
                    if (closed) return;
                    closed = true;
                    if (ctx.mounted) Navigator.of(ctx).pop(ok);
                  }

                  return PopScope(
                    canPop: false,
                    child: Dialog.fullscreen(
                      backgroundColor: Colors.transparent,
                      child: GazeCalibrationOverlay(
                        examId: widget.examId,
                        onCalibrationComplete: () => close(true),
                        onCalibrationFailed: () => close(false),
                        onCalibrationCancelled: () => close(false),
                      ),
                    ),
                  );
                },
              );
              if (!mounted || calibrationOk != true) {
                // Release the screen share so it doesn't keep running
                if (isPc) {
                  _screen.stop();
                }
                if (mounted) {
                  await _showErrorDialog(
                    title: "Calibration Required",
                    message:
                        "Gaze calibration is required to take this exam. Please complete the calibration process to continue.",
                    icon: Icons.visibility_off_outlined,
                    color: _warnColor,
                  );
                }
                return;
              }

              // Start with clean per-attempt state while preserving exam/student
              // identifiers, gaze calibration, and authentication storage.
              clearStaleExamStorage();

              // Make streams reachable by exam.html
              if (isPc) {
                _screen.exposeToExam();
              }

              final now = DateTime.now();
              final startedAt = Timestamp.fromDate(now);

              final resultRef = db
                  .collection("examResults")
                  .doc(widget.examId)
                  .collection("students")
                  .doc(uid);
              await resultRef.set({
                "examId": widget.examId,
                "uid": uid,
                "studentId": studentId ?? uid,
                "status": "in-progress",
                "currentIndex": 0,
                "startedAt": startedAt,
              }, SetOptions(merge: true));

              if (!mounted) return;
              _screen.handedOff = true;

              // Navigate to exam.html via shell route
              context.goNamed(
                'exam',
                pathParameters: {"examId": widget.examId},
              );
            } catch (e) {
              _screen.handedOff = false;
              _screen.stop();
              if (mounted) {
                await _showErrorDialog(
                  title: "Couldn't start the exam",
                  message:
                      "Something went wrong while starting the exam. Please try again.",
                  details: e.toString(),
                );
              }
            } finally {
              _starting = false;
            }
          },
        );
      },
    );
  }

  // ---------- UI helpers: match the clean Secure Exam HTML layout ----------

  Widget _skelBox({double? width, required double height, double radius = 6}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE9ECE9),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildSkeleton() {
    return _SkeletonPulse(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDFE2DF)),
          borderRadius: BorderRadius.circular(9),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(26, 25, 26, 25),
              color: const Color(0xFFF1F3F1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skelBox(width: 220, height: 24),
                  const SizedBox(height: 12),
                  _skelBox(width: 320, height: 12),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: LayoutBuilder(
                builder: (context, c) {
                  final wide = c.maxWidth >= 690;
                  final left = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _skelBox(height: 96),
                      const SizedBox(height: 14),
                      for (var i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          child: _skelBox(height: 14),
                        ),
                    ],
                  );
                  final right = _skelBox(height: 190, radius: 7);

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 20),
                            child: left,
                          ),
                        ),
                        Expanded(flex: 2, child: right),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 14), right],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageShell({required Widget child}) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, viewport) {
            final horizontal = viewport.maxWidth < 600 ? 16.0 : 28.0;
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: viewport.maxHeight),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 22, horizontal, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTitleBar(),
                      const SizedBox(height: 24),
                      child, // no Expanded here
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _pageBody({
    required Widget card,
    Widget? action,
    bool showSteps = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSteps) ...[_buildSecureFlowSteps(), const SizedBox(height: 20)],
        card,
        if (action != null) ...[const SizedBox(height: 16), action],
      ],
    );
  }

  Widget _buildSecureFlowSteps() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDADDD9)),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _flowStep('1', 'Enter exam', active: true),
            Container(width: 26, height: 1, color: const Color(0xFFD8DBD8)),
            _flowStep('2', 'Calibrate'),
            Container(width: 26, height: 1, color: const Color(0xFFD8DBD8)),
            _flowStep('3', 'Exam'),
          ],
        ),
      ),
    );
  }

  Widget _flowStep(String number, String label, {bool active = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _accentColor : const Color(0xFFEFF0EE),
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? _accentColor : const Color(0xFFDCE0DC),
            ),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF777B80),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: active ? _textColor : const Color(0xFF828589),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildTitleBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FOTS SECURE SESSION',
          style: TextStyle(
            color: Color(0xFF27694F),
            fontSize: 10,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'Secure Exam',
          style: TextStyle(
            color: Color(0xFF17181D),
            fontSize: 34,
            height: 1.05,
            letterSpacing: -1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Enter → calibrate → take the exam. The timer starts only after calibration succeeds.',
          style: TextStyle(color: _mutedTextColor, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _statusChip(String status) {
    final s = status.toLowerCase();
    final Color color = s == "completed"
        ? _successColor
        : s == "in-progress"
        ? _warnColor
        : s == "incomplete"
        ? _errorColor
        : _accentColor;
    final label = status.isEmpty
        ? "—"
        : status[0].toUpperCase() + status.substring(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _doubleBorder({
    required Color color,
    required double innerRadius,
    required Widget child,
    bool shadow = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(innerRadius + 3),
        border: Border.all(color: color, width: 1.5),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  Widget _detailsCard({
    required String subject,
    String? status,
    required List<_DetailRow> rows,
    Widget? action,
  }) {
    final completed = status?.toLowerCase() == 'completed';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDFE2DF)),
        borderRadius: BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(26, 25, 26, 25),
            color: _headerColor,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          height: 1.15,
                          letterSpacing: -0.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        completed
                            ? 'You have completed this exam. Your result is ready to view.'
                            : 'Secure gaze session. Camera access begins only after you choose Start Exam.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(.72),
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 12),
                  _statusChip(status),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 690;
                final detailList = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!completed) ...[
                      _buildInstructionsCard(),
                      const SizedBox(height: 14),
                    ],
                    for (int i = 0; i < rows.length; i++)
                      _buildDetail(rows[i], shaded: false),
                  ],
                );
                final actionPanel = Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F8F3),
                    border: Border.all(color: const Color(0xFFDCEDE2)),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE1F3E9),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFCDE8D9)),
                        ),
                        child: Icon(
                          completed
                              ? Icons.task_alt_outlined
                              : Icons.track_changes_outlined,
                          color: const Color(0xFF267A58),
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text(
                        completed ? 'Exam completed' : 'Ready to begin?',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF17181D),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        completed
                            ? 'You have already finished this exam. Open your result to review your score.'
                            : 'You will calibrate first. Looking naturally downward at the screen is expected; you do not need to stare into the camera.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF777B80),
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 17),
                      if (action != null) action,
                    ],
                  ),
                );

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 20),
                          child: detailList,
                        ),
                      ),
                      Expanded(flex: 2, child: actionPanel),
                    ],
                  );
                }
                return Column(
                  children: [
                    detailList,
                    const SizedBox(height: 14),
                    actionPanel,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetail(_DetailRow row, {required bool shaded}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE4E6E4))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              row.label,
              style: const TextStyle(color: Color(0xFF777B80), fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF24262A),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    const items = [
      "Don't switch tabs",
      "Don't leave the app",
      "Look at the screen; looking away for too long may trigger monitoring.",
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.72),
        border: Border.all(color: const Color(0xFFDCEDE2)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF087B4F),
                size: 16,
              ),
              SizedBox(width: 7),
              Text(
                'BEFORE YOU BEGIN',
                style: TextStyle(
                  color: Color(0xFF17181D),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(
                      Icons.check_circle_outline,
                      size: 13,
                      color: Color(0xFF087B4F),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFF686D72),
                        fontSize: 10,
                        height: 1.4,
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

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
    Color color = _accentColor,
    IconData? icon,
    String? hint,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final button = SizedBox(
          width: compact ? double.infinity : 230,
          height: 45,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE7E9E7),
              disabledForegroundColor: const Color(0xFF85898D),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18),
                  const SizedBox(width: 9),
                ],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hint != null) ...[
              Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF777B80),
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 10),
            ],
            Center(child: button),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String message) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFDFE2DF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5EE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 29, color: _accentColor),
            ),
            const SizedBox(height: 15),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF17181D),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(this.icon, this.label, this.value);
}

class _SkeletonPulse extends StatefulWidget {
  final Widget child;
  const _SkeletonPulse({required this.child});

  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(
        begin: .55,
        end: 1,
      ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: widget.child,
    );
  }
}
