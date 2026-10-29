import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

class GazeCalibrationView extends StatefulWidget {
  final String examId;

  /// 'calibrationComplete' | 'calibrationFailed' | 'calibrationCancelled'
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
      final data = event.data;
      if (data is Map && data['action'] is String) {
        widget.onAction(data['action'] as String);
      }
    });
  }

  void _ensureFactoryRegistered() {
    if (_factoryRegistered) return;
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = '${html.window.location.origin}/assets/gaze-calibration.html'
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
