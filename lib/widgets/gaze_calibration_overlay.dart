import 'package:flutter/material.dart';
import 'gaze_calibration_view.dart';

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
  bool _calibrationComplete = false;
  bool _calibrationFailed = false;
  bool _cancelled = false;

  void _handleAction(String action) {
    if (!mounted) return;

    switch (action) {
      case 'calibrationComplete':
        if (_calibrationComplete) return;
        setState(() => _calibrationComplete = true);
        // Wait a moment to show success, then notify parent
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) widget.onCalibrationComplete();
        });
        break;

      case 'calibrationFailed':
        if (_calibrationFailed) return;
        _calibrationFailed = true;
        // let the "Maximum Attempts Reached" box stay visible before closing
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) widget.onCalibrationFailed();
        });
        break;

      case 'calibrationCancelled':
        if (_cancelled || _calibrationComplete) return;
        _cancelled = true;
        widget.onCalibrationCancelled?.call();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GazeCalibrationView(
              examId: widget.examId,
              onAction: _handleAction,
            ),
          ),
          if (_calibrationComplete)
            Container(
              color: const Color(0xDE0B1220),
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
