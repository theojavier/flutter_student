import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class GazeCalibrationView extends StatefulWidget {
  final String examId;
  final Future<dynamic> Function(String action, Map<String, dynamic> data)
  onAction;

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

  // Clear stale attempt state without removing the saved gaze calibration.
  static final _resetScript = UserScript(
    source: """
      try {
        ['cheatingCount', 'cheatClipIndex', 'pendingCheatStill']
          .forEach(function(k) { localStorage.removeItem(k); });

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
          '?exam=1&examId=${widget.examId}',
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
              return widget.onAction(
                data['action'] as String,
                Map<String, dynamic>.from(data),
              );
            }
            return null;
          },
        );
      },
      onConsoleMessage: (c, m) => debugPrint('[calibration] ${m.message}'),
    );
  }
}
