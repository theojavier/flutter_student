import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class GazeCalibrationView extends StatefulWidget {
  final String examId;
  final void Function(String action) onAction;

  const GazeCalibrationView({
    super.key,
    required this.examId,
    required this.onAction,
  });

  @override
  State<GazeCalibrationView> createState() => _GazeCalibrationViewState();
}

class _GazeCalibrationViewState extends State<GazeCalibrationView> {
  static const _origin = 'https://student-099266.web.app';

  // Runs BEFORE the page's own scripts, clearing both calibration and stale exam-attempt data.
  // Calibration is redone right now; exam leftovers must be wiped so the next attempt starts fresh.
  static final _resetScript = UserScript(
    source: """
      try {
        // Calibration data (will be rewritten by this calibration session)
        localStorage.removeItem('gazeCalibrationData');

        // Exam-attempt leftovers (keep in sync with EXAM_LOCAL_KEYS in exam.html)
        ['cheatingCount', 'cheatClipIndex', 'pendingCheatStill']
          .forEach(function(k) { localStorage.removeItem(k); });

        // Session-scoped exam state
        ['gazeBias', 'gazeOnlineClicks', 'examStarted', 'is_unloading']
          .forEach(function(k) { sessionStorage.removeItem(k); });
      } catch (e) {}
    """,
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
  );

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(
          '$_origin/assets/gaze-calibration.html'
          '?examId=${widget.examId}&platform=mobile&v=3',
        ),
      ),
      initialUserScripts: UnmodifiableListView([_resetScript]),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        cacheEnabled: false,
      ),
      onPermissionRequest: (controller, request) async {
        return PermissionResponse(
          resources: request.resources,
          action: PermissionResponseAction.GRANT,
        );
      },
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'flutterMessage',
          callback: (args) {
            final data = args.isNotEmpty ? args.first : null;
            if (data is Map && data['action'] is String) {
              widget.onAction(data['action'] as String);
            }
          },
        );
      },
      onConsoleMessage: (c, m) => debugPrint('[calibration] ${m.message}'),
    );
  }
}
