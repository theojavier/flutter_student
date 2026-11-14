import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

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
  static bool _factoryRegistered = false;
  static const String _viewType = 'profile-gaze-calibration-overlay';
  static html.IFrameElement? _activeFrame;
  static Map<String, dynamic>? _pendingCalibration;
  static String? _hostToken;
  StreamSubscription<html.MessageEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _pendingCalibration = widget.previousCalibration;
    final random = Random.secure();
    _hostToken = base64Url.encode(
      List<int>.generate(24, (_) => random.nextInt(256)),
    );
    _ensureFactoryRegistered();

    _sub = html.window.onMessage.listen(_handleMessage);
  }

  void _handleMessage(html.MessageEvent event) {
    if (!mounted || event.origin != html.window.location.origin) return;
    dynamic data = event.data;
    try {
      if (data is String) data = jsonDecode(data);
    } on FormatException catch (error) {
      debugPrint('[profile-calibration] Ignoring malformed message: $error');
      return;
    }
    if (data is! Map ||
        data['action'] is! String ||
        data['hostToken'] != _hostToken) {
      return;
    }

    debugPrint('[profile-calibration-web] Received ${data['action']}');
    unawaited(_dispatchMessage(Map<String, dynamic>.from(data)));
  }

  Future<void> _dispatchMessage(Map<String, dynamic> message) async {
    final requestId = message['requestId'];
    try {
      final result = await widget.onAction(
        message['action'] as String,
        message,
      );
      if (requestId is String) {
        debugPrint(
          '[profile-calibration-web] Responding to ${message['action']}',
        );
        _activeFrame?.contentWindow?.postMessage(
          jsonEncode({
            'requestId': requestId,
            'hostToken': _hostToken,
            'result': result,
          }),
          html.window.location.origin,
        );
      }
    } catch (error) {
      debugPrint('[profile-calibration] Host action failed: $error');
      if (requestId is String) {
        _activeFrame?.contentWindow?.postMessage(
          jsonEncode({
            'requestId': requestId,
            'hostToken': _hostToken,
            'error': error.toString(),
          }),
          html.window.location.origin,
        );
      }
    }
  }

  void _ensureFactoryRegistered() {
    if (_factoryRegistered) return;
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src =
            '${html.window.location.origin}/assets/gaze-calibration.html?profile=1'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background = 'transparent'
        ..allow = 'camera; fullscreen';
      _activeFrame = iframe;
      iframe.onLoad.listen((_) {
        iframe.contentWindow?.postMessage({
          'action': 'setProfileCalibrationBaseline',
          'calibrationData': _pendingCalibration,
          'hostToken': _hostToken,
        }, html.window.location.origin);
      });
      return iframe;
    });
    _factoryRegistered = true;
  }

  @override
  void dispose() {
    _sub?.cancel();
    final iframe = _activeFrame;
    if (iframe != null) {
      iframe.contentWindow?.postMessage({'action': 'dispose'}, '*');
      iframe.src = 'about:blank';
      _activeFrame = null;
      _hostToken = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const HtmlElementView(viewType: _viewType);
}
