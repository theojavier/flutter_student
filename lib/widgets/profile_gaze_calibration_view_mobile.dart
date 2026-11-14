import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ProfileGazeCalibrationView extends StatefulWidget {
  final Future<dynamic> Function(String action, Map<String, dynamic> data)
  onAction;
  final Map<String, dynamic>? previousCalibration;

  const ProfileGazeCalibrationView({
    super.key,
    required this.onAction,
    this.previousCalibration,
  });

  @override
  State<ProfileGazeCalibrationView> createState() =>
      _ProfileGazeCalibrationViewState();
}

class _ProfileGazeCalibrationViewState
    extends State<ProfileGazeCalibrationView> {
  static const _origin = 'https://student-099266.web.app';

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('$_origin/assets/gaze-calibration.html?profile=1'),
      ),
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
            if (data is Map) {
              final action = data['action'] as String?;
              if (action != null) {
                return widget.onAction(action, Map<String, dynamic>.from(data));
              }
            }
          },
        );
      },
      onLoadStop: (controller, url) async {
        final calibration = widget.previousCalibration;
        await controller.evaluateJavascript(
          source:
              'window.setProfileCalibrationBaseline(${jsonEncode(calibration)});',
        );
      },
      onConsoleMessage: (c, m) =>
          debugPrint('[profile-calibration] ${m.message}'),
    );
  }
}
