import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:my_flutter_app/theme/colors.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../helpers/SecureStorageHelper.dart';
import 'package:flutter/foundation.dart';
import 'package:super_overlay/super_overlay.dart';
import '../../widgets/gaze_calibration_overlay.dart';

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
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _successColor = Color(0xFF4ADE80);
  static const Color _errorColor = Color(0xFFF87171);
  static const Color _warnColor = Color(0xFFFBBF24);
  OverlayHandle? calibrationHandle;

  // Button colors
  static const Color _btnStart = Color(0xFF3D8BFF);
  static const Color _btnResult = Color(0xFF16A34A);
  static const Color _btnProgress = Color(0xFFD97706);
  static const Color _btnIncomplete = Color(0xFFDC2626);

  final db = FirebaseFirestore.instance;
  String? studentId;
  int? start;
  int? end;

  bool _leftApp = false; // app went to background
  bool _starting = false; // Start Exam flow is running
  bool _dialogOpen = false; // an error popup is showing
  String? _cameraError; // last camera test error (for the popup details)

  // Kept alive (NOT stopped) once the permission checks pass, so the
  // exam iframe can reuse the same streams instead of requesting them again.
  dynamic _screenStream;
  dynamic _cameraStream;
  bool _screenStreamHandedOff = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStudentId();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_screenStreamHandedOff) {
      _stopJsStream(_screenStream);
      _stopJsStream(_cameraStream);
    }
    _screenStream = null;
    _cameraStream = null;
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

  /// Stops every track on a raw JS MediaStream obtained via js_util.
  void _stopJsStream(dynamic stream) {
    if (stream == null) return;
    try {
      final dynamic tracks = js_util.callMethod(stream, 'getTracks', []);
      final int len = (js_util.getProperty(tracks, 'length') as num).toInt();
      for (var i = 0; i < len; i++) {
        final dynamic track = js_util.getProperty(tracks, '$i');
        js_util.callMethod(track, 'stop', []);
      }
    } catch (e) {
      debugPrint('Failed to stop a media stream: $e');
    }
  }

  /// Calls navigator.mediaDevices.getDisplayMedia directly via js_util
  /// instead of dart:html's MediaDevices class, which doesn't expose that
  /// method. This still returns the browser's real, native MediaStream —
  /// which is exactly what lets us hand it to the exam.html iframe later
  /// instead of exam.html calling getDisplayMedia() again (that second call
  /// is what was causing the screen-share prompt to appear twice).
  Future<bool> _requestFullScreenShare() async {
    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception("Screen sharing isn't supported in this browser.");
      }

      final dynamic promise = js_util.callMethod(
        mediaDevices,
        'getDisplayMedia',
        [
          js_util.jsify({
            'video': {'displaySurface': 'monitor'},
            'audio': false,
          }),
        ],
      );
      final dynamic stream = await js_util.promiseToFuture(promise);

      final dynamic videoTracks = js_util.callMethod(
        stream,
        'getVideoTracks',
        [],
      );
      final int trackCount = (js_util.getProperty(videoTracks, 'length') as num)
          .toInt();

      String displaySurface = '';
      if (trackCount > 0) {
        final dynamic track = js_util.getProperty(videoTracks, '0');
        final dynamic settings = js_util.callMethod(track, 'getSettings', []);
        displaySurface =
            (js_util.getProperty(settings, 'displaySurface') as String?) ?? '';
      }

      if (trackCount == 0 ||
          (displaySurface.isNotEmpty && displaySurface != 'monitor')) {
        _stopJsStream(stream);
        throw Exception(
          'Please choose "Entire Screen" when prompted — sharing a window or browser tab is not allowed.',
        );
      }

      _screenStream = stream; // kept alive on purpose, see doc comment above
      return true;
    } catch (e) {
      debugPrint("Screen share failed: $e");
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

  Future<bool> _checkCameraAvailability() async {
    _cameraError = null;
    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      final hasVideoInput = devices.any((d) => d.kind == 'videoinput');
      if (!hasVideoInput) return false;

      // Single camera acquisition — this is the only place we call
      // getUserMedia for the camera.
      final stream = await navigator.mediaDevices.getUserMedia({
        'video': true,
        'audio': false,
      });

      final videoRenderer = RTCVideoRenderer();
      await videoRenderer.initialize();
      videoRenderer.srcObject = stream;

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            Future.delayed(const Duration(seconds: 5), () {
              if (ctx.mounted && Navigator.canPop(ctx)) {
                Navigator.pop(ctx);
              }
            });

            return AlertDialog(
              backgroundColor: _cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
              title: const Text(
                'Camera Test',
                style: TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Please look at the screen',
                    style: TextStyle(color: _mutedTextColor),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 240,
                    height: 180,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _accentColor.withOpacity(0.6),
                        width: 2,
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
                      borderRadius: BorderRadius.circular(14),
                      child: RTCVideoView(videoRenderer, mirror: true),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      }

      await Future.delayed(const Duration(seconds: 5));
      _detectFace();

      stream.getTracks().forEach((t) => t.stop());
      await videoRenderer.dispose();

      return true;
    } catch (e) {
      debugPrint("Camera test failed: $e");
      _cameraError = e.toString();
      return false;
    }
  }

  // Placeholder for future face detection logic
  void _detectFace() {
    //: implement face detection
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

    return _pageShell(
      child: FutureBuilder<DocumentSnapshot>(
        future: db.collection("exams").doc(widget.examId).get(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildEmptyState(
              Icons.error_outline,
              "Couldn't load exam details",
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _accentColor),
            );
          }
          if (!snapshot.data!.exists) {
            return StreamBuilder<DocumentSnapshot>(
              stream: db
                  .collection("examResults")
                  .doc(widget.examId)
                  .collection("students")
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .snapshots(),
              builder: (context, resultSnap) {
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
                  card: _detailsCard(
                    subject: (subject ?? "Exam").toString(),
                    status: status?.toString(),
                    rows: rows,
                  ),
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
                );
              },
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final subject = data["subject"] ?? "Unknown";
          start =
              widget.startMillis ??
              data["startTime"]?.toDate().millisecondsSinceEpoch;
          end =
              widget.endMillis ??
              data["endTime"]?.toDate().millisecondsSinceEpoch;

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

          return _pageBody(
            card: _detailsCard(subject: subject.toString(), rows: rows),
            action: _buildExamAction(subject.toString(), uid),
          );
        },
      ),
    );
  }

  // Start / Resume / View Result button (real-time updates)
  Widget _buildExamAction(String subject, String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: db
          .collection("examResults")
          .doc(widget.examId)
          .collection("students")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .snapshots(),
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

        //  Start new attempt — single seamless flow: one framing popup,
        //  then full-screen check, then camera check. Only when BOTH pass
        //  do we write Firestore and navigate to exam.html. Any failure
        //  keeps the student right here so they can retry.
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
              final agreed = await _showReadyDialog();
              if (!agreed) return;

              final screenOk = await _requestFullScreenShare();
              if (!mounted || !screenOk) return; // popup already shown

              final cameraOk = await _checkCameraAvailability();
              if (!mounted) return;
              if (!cameraOk) {
                // Screen was granted but camera wasn't — release the
                // screen share since we're not proceeding.
                _stopJsStream(_screenStream);
                _screenStream = null;
                await _showErrorDialog(
                  title: "Camera not available",
                  message:
                      "No camera was detected or it is turned off. Turn on your camera, make sure no other app is using it, and allow camera access. You cannot take the exam without it.",
                  icon: Icons.videocam_off_outlined,
                  details: _cameraError,
                );
                return;
              }

              // Both confirmed — make the screen + camera streams reachable by
              // exam.html so it can reuse the already-approved streams instead of
              // opening a second permission flow.
              if (_screenStream != null) {
                js_util.setProperty(
                  html.window,
                  '__examScreenStream',
                  _screenStream,
                );
              }
              if (_cameraStream != null) {
                js_util.setProperty(
                  html.window,
                  '__examCameraStream',
                  _cameraStream,
                );
              }

              final now = DateTime.now();
              final startedAt = Timestamp.fromDate(now);
              final monitoredAt = Timestamp.fromDate(
                now.add(const Duration(minutes: 5)),
              );

              final examDoc = await db
                  .collection("exams")
                  .doc(widget.examId)
                  .get();
              final examData = examDoc.data() ?? {};
              final examStart = examData["startTime"] as Timestamp?;
              final examEnd = examData["endTime"] as Timestamp?;
              final examSubject = examData["subject"] ?? subject;
              final examTeacher =
                  examData["creator"] ??
                  examData["teacher"] ??
                  examData["createdBy"] ??
                  "Unknown";

              await db
                  .collection("examResults")
                  .doc(widget.examId)
                  .collection("students")
                  .doc(uid)
                  .set({
                    "examId": widget.examId,
                    "uid": uid,
                    "studentId": studentId ?? uid,
                    "status": "in-progress",
                    "cheatingCount": 0,
                    "currentIndex": 0,
                    "subject": examSubject,
                    "teacher": examTeacher,
                    "startTime": examStart ?? startedAt,
                    "endTime": examEnd ?? monitoredAt,
                    "startedAt": startedAt,
                    "createdAt": startedAt,
                    "lastHeartbeatAt": startedAt,
                    "monitoringEnabled": true,
                    "monitoringStartedAt": startedAt,
                    "monitoringDeadlineAt": monitoredAt,
                    "updatedAt": startedAt,
                  }, SetOptions(merge: true));

             if (!mounted) return;
_screenStreamHandedOff = true;

final router = GoRouter.of(context);
await showGeneralDialog<void>(
  context: context,
  useRootNavigator: true,
  barrierDismissible: false,
  barrierColor: Colors.transparent,
  transitionDuration: Duration.zero,
  pageBuilder: (ctx, _, __) => Material(
    type: MaterialType.transparency,
    child: GazeCalibrationOverlay(
      examId: widget.examId,
      onCalibrationComplete: () {
        Navigator.of(ctx, rootNavigator: true).pop();
        router.goNamed(
          'examhtml',
          pathParameters: {'examId': widget.examId},
        );
      },
    ),
  ),
);
            } catch (e) {
              _screenStreamHandedOff = false;
              _stopJsStream(_screenStream);
              _screenStream = null;
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

  // ---------- UI helpers (compact so everything fits the first screen) ----------

  Widget _pageShell({required Widget child}) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(),
              const SizedBox(height: 10),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageBody({required Widget card, Widget? action}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false, overscroll: false),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  card,
                  const SizedBox(height: 10),
                  _buildInstructionsCard(),
                ],
              ),
            ),
          ),
        ),
        if (action != null) ...[const SizedBox(height: 10), action],
      ],
    );
  }

  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
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
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.fact_check_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Exam Details",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              _tag("EXAM INFORMATION"),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
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
                  color: Colors.black.withOpacity(0.25),
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
  }) {
    const double r = 20;

    return _doubleBorder(
      color: _accentColor.withOpacity(0.55),
      innerRadius: r,
      shadow: true,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_headerColorLight, _headerColor],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _tag("SUBJECT"),
                        const Spacer(),
                        if (status != null) _statusChip(status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (rows.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: _cardColor,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Column(
                    children: [
                      for (int i = 0; i < rows.length; i++)
                        _buildDetail(rows[i], shaded: i.isOdd),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetail(_DetailRow row, {required bool shaded}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      decoration: BoxDecoration(
        color: shaded ? Colors.white.withOpacity(0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(row.icon, size: 15, color: _accentColor.withOpacity(0.8)),
          const SizedBox(width: 8),
          Text(
            row.label,
            style: const TextStyle(fontSize: 12.5, color: _mutedTextColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textColor,
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
      "Look at the screen it may trigger as cheating.",
    ];
    const double r = 16;

    return _doubleBorder(
      color: _errorColor.withOpacity(0.55),
      innerRadius: r,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: _errorColor.withOpacity(0.10),
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: _errorColor.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: _errorColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(
                    children: const [
                      TextSpan(
                        text: "IMPORTANT",
                        style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      TextSpan(
                        text: "  Instructions:",
                        style: TextStyle(color: _mutedTextColor),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 5, color: _errorColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: _textColor,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
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
        final double w = (constraints.maxWidth * 0.25)
            .clamp(120.0, 260.0)
            .toDouble();

        return Row(
          children: [
            SizedBox(
              width: w,
              height: 44,
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white.withOpacity(0.08),
                  disabledForegroundColor: _mutedTextColor,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 18),
                        const SizedBox(width: 6),
                      ],
                      Text(label),
                    ],
                  ),
                ),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hint,
                  style: const TextStyle(
                    color: _mutedTextColor,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ],
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_cardColor.withOpacity(0.9), _cardColor.withOpacity(0.55)],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
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
              child: Icon(icon, size: 28, color: _accentColor),
            ),
            const SizedBox(height: 12),
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
}

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(this.icon, this.label, this.value);
}
