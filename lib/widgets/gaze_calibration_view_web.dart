import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

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
  static bool _factoryRegistered = false;
  static const String _viewType = 'gaze-calibration-overlay';
  static html.IFrameElement? _activeFrame;
  StreamSubscription<html.MessageEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _ensureFactoryRegistered();

    _sub = html.window.onMessage.listen((event) {
      if (!mounted) return;
      if (event.origin != html.window.location.origin) {
        return;
      }
      final rawData = event.data;
      dynamic data;
      try {
        data = rawData is String ? jsonDecode(rawData) : rawData;
      } on FormatException catch (error) {
        debugPrint('[calibration-bridge] Ignoring malformed message: $error');
        return;
      }
      if (data is! Map) return;
      final message = <String, dynamic>{};
      for (final entry in data.entries) {
        if (entry.key is String) {
          message[entry.key as String] = entry.value;
        }
      }
      if (message['action'] is! String) return;
      final requestId = message['requestId'];
      unawaited(
        widget
            .onAction(message['action'] as String, message)
            .then<void>((result) {
              if (requestId is String) {
                try {
                  _activeFrame?.contentWindow?.postMessage(
                    jsonEncode({'requestId': requestId, 'result': result}),
                    html.window.location.origin,
                  );
                } catch (error) {
                  debugPrint(
                    '[calibration-bridge] Could not encode response: $error',
                  );
                  _activeFrame?.contentWindow?.postMessage(
                    jsonEncode({
                      'requestId': requestId,
                      'error': 'The calibration response could not be encoded.',
                    }),
                    html.window.location.origin,
                  );
                }
              }
            })
            .catchError((Object error) {
              debugPrint('[calibration-bridge] Host action failed: $error');
              if (requestId is String) {
                _activeFrame?.contentWindow?.postMessage(
                  jsonEncode({
                    'requestId': requestId,
                    'error': error.toString(),
                  }),
                  html.window.location.origin,
                );
              }
            }),
      );
    });
  }

  void _ensureFactoryRegistered() {
    if (_factoryRegistered) return;
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src =
            '${html.window.location.origin}/assets/gaze-calibration.html?exam=1'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background = 'transparent'
        ..allow = 'camera; fullscreen';
      _activeFrame = iframe;
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
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const HtmlElementView(viewType: _viewType);
}
