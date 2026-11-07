import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui;
import 'package:flutter/material.dart';

class ProfileGazeCalibrationView extends StatefulWidget {
  final void Function(String action, Map<String, dynamic>? data) onAction;
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
  StreamSubscription<html.MessageEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _pendingCalibration = widget.previousCalibration;
    _ensureFactoryRegistered();

    _sub = html.window.onMessage.listen((event) {
      if (!mounted) return;
      final data = event.data;
      if (data is Map) {
        final action = data['action'] as String?;
        if (action != null) {
          // Convert to Map<String, dynamic>
          final mappedData = Map<String, dynamic>.from(data);

          // Handle different actions
          if (action == 'saveCalibration') {
            _handleSaveCalibration(mappedData);
          } else {
            widget.onAction(action, mappedData);
          }
        }
      }
    });
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
        }, html.window.location.origin);
      });
      return iframe;
    });
    _factoryRegistered = true;
  }

  void _handleSaveCalibration(Map<String, dynamic> data) async {
    final platform = data['platform'] as String?;
    final calibrationData = data['calibrationData'];

    if (platform == null || calibrationData == null) {
      widget.onAction('calibrationFailed', {'error': 'Missing data'});
      return;
    }

    widget.onAction('saveCalibration', {
      'platform': platform,
      'calibrationData': calibrationData,
    });
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
