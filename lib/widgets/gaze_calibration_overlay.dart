import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'dart:ui_web' as ui;

class GazeCalibrationOverlay extends StatefulWidget {
  final String examId;
  final VoidCallback onCalibrationComplete;
  final VoidCallback onCalibrationFailed;
  final VoidCallback? onCalibrationCancelled;

  const GazeCalibrationOverlay({
    super.key,
    required this.examId,
    required this.onCalibrationComplete,
    required this.onCalibrationFailed,
    this.onCalibrationCancelled,
  });

  @override
  State<GazeCalibrationOverlay> createState() => _GazeCalibrationOverlayState();
}

class _GazeCalibrationOverlayState extends State<GazeCalibrationOverlay> {
  static bool _factoryRegistered = false;
  static const String _viewType = 'gaze-calibration-overlay';
  bool _calibrationComplete = false;
  bool _calibrationFailed = false;
  bool _cancelled = false;
  late final StreamSubscription<html.MessageEvent> _messageSubscription;

  @override
  void initState() {
    super.initState();

    _ensureFactoryRegistered();

    // Listen for calibration completion message
    _messageSubscription = html.window.onMessage.listen((event) {
      if (!mounted) return;
      final data = event.data;
      if (data is Map && data['action'] == 'calibrationComplete') {
        setState(() {
          _calibrationComplete = true;
        });

        // Wait a moment to show success, then notify parent
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            widget.onCalibrationComplete();
          }
        });
      } else if (data is Map && data['action'] == 'calibrationFailed') {
        if (_calibrationFailed) return;
        _calibrationFailed = true;

        // let the "Maximum Attempts Reached" box stay visible before closing
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) widget.onCalibrationFailed();
        });
      } else if (data is Map && data['action'] == 'calibrationCancelled') {
        if (_cancelled || _calibrationComplete) return;
        _cancelled = true;
        widget.onCalibrationCancelled?.call();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_messageSubscription.cancel());
    super.dispose();
  }

  void _ensureFactoryRegistered() {
    if (_factoryRegistered) return;

    print('🎯 Registering gaze calibration iframe factory');

    // Register factory only once
    // ignore: undefined_prefixed_name
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      print('🎯 Creating gaze calibration iframe with viewId: $viewId');

      final iframe = html.IFrameElement()
        ..src = '${html.window.location.origin}/assets/gaze-calibration.html'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.background =
            'transparent' // TRANSPARENT
        ..allow = 'camera; fullscreen';

      print('🎯 Iframe src: ${iframe.src}');

      return iframe;
    });

    _factoryRegistered = true;
    print('🎯 Factory registered successfully');
  }

  @override
  Widget build(BuildContext context) {
    print(
      '🎯 Building GazeCalibrationOverlay - calibrationComplete: $_calibrationComplete',
    );

    return Container(
      color: Colors.transparent, // Let the HTML handle the background
      child: Stack(
        children: [
          // Calibration iframe (fullscreen)
          const Positioned.fill(child: HtmlElementView(viewType: _viewType)),

          // Success overlay
          if (_calibrationComplete)
            Container(
              color: const Color(0xDE0B1220), // Semi-transparent dark
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF4ADE80),
                      size: 80,
                    ),
                    SizedBox(height: 20),
                    Text(
                      'Calibration Complete!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Starting exam...',
                      style: TextStyle(color: Color(0xFF9FB0C3), fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
