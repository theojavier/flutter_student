import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../helpers/face_identity_storage.dart';
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

  Future<dynamic> _handleAction(
    String action,
    Map<String, dynamic> data,
  ) async {
    switch (action) {
      case 'getFaceReference':
      case 'saveFaceReference':
        return FaceIdentityStorage.handleAction(action, data);

      case 'getGazeCalibration':
        final platform = data['platform'] as String?;
        if (platform != 'pc' && platform != 'mobile') {
          throw Exception('The detected device platform is invalid.');
        }
        final result = await FirebaseFunctions.instanceFor(
          region: 'asia-southeast1',
        ).httpsCallable('getGazeCalibration').call({'platform': platform});
        final response = Map<String, dynamic>.from(result.data as Map);
        final recordValue = response['record'] ?? response['data'];
        final nestedRecord = recordValue is Map
            ? Map<String, dynamic>.from(recordValue)
            : <String, dynamic>{};
        final calibrationData =
            response['calibrationData'] ??
            nestedRecord['calibrationData'] ??
            response['calibration'] ??
            nestedRecord['calibration'] ??
            (nestedRecord['version'] != null ? nestedRecord : null) ??
            (response['version'] != null ? response : null);
        final recordMetadata = <String, dynamic>{};
        for (final key in [
          'platform',
          'calibratedAt',
          'timestamp',
          'accuracy',
          'daysOld',
          'learningSampleCount',
          'createdAt',
          'updatedAt',
        ]) {
          final value = nestedRecord[key];
          if (value is String || value is num || value is bool) {
            recordMetadata[key] = nestedRecord[key];
          }
        }
        final hostResponse = <String, dynamic>{};
        for (final key in [
          'success',
          'exists',
          'hasInvalidRecord',
          'needsRecalibration',
          'daysOld',
          'accuracy',
          'learningSampleCount',
          'checkError',
          'message',
        ]) {
          final value = response[key];
          if (value is String || value is num || value is bool) {
            hostResponse[key] = value;
          }
        }
        return {
          ...hostResponse,
          if (recordValue != null) 'record': recordMetadata,
          'exists': response['exists'] == true || calibrationData != null,
          'calibrationData': calibrationData,
          'platform': platform,
        };

      case 'saveGazeCalibration':
        final platform = data['platform'] as String?;
        final calibrationData = data['calibrationData'];
        if ((platform != 'pc' && platform != 'mobile') ||
            calibrationData == null) {
          throw Exception('Calibration data is incomplete.');
        }
        final result =
            await FirebaseFunctions.instanceFor(
              region: 'asia-southeast1',
            ).httpsCallable('saveGazeCalibration').call({
              'platform': platform,
              'calibrationData': calibrationData,
            });
        final saved = Map<String, dynamic>.from(result.data as Map);
        if (saved['success'] != true) {
          throw Exception('The calibration was not saved.');
        }
        return saved;

      case 'gazeSetupComplete':
      case 'calibrationComplete':
        if (!mounted) return null;
        if (_calibrationComplete) return;
        setState(() => _calibrationComplete = true);
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) widget.onCalibrationComplete();
        });
        return null;

      case 'calibrationFailed':
        if (!mounted) return null;
        if (_calibrationFailed) return;
        _calibrationFailed = true;
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) widget.onCalibrationFailed();
        });
        return null;

      case 'calibrationCancelled':
        if (!mounted) return null;
        if (_cancelled || _calibrationComplete) return;
        _cancelled = true;
        widget.onCalibrationCancelled?.call();
        return null;
    }
    return null;
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
                      'Gaze Setup Complete!',
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
