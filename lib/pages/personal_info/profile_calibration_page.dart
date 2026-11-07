import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../widgets/profile_gaze_calibration_view.dart';

class ProfileCalibrationPage extends StatefulWidget {
  const ProfileCalibrationPage({super.key});

  @override
  State<ProfileCalibrationPage> createState() => _ProfileCalibrationPageState();
}

class _ProfileCalibrationPageState extends State<ProfileCalibrationPage> {
  bool _saving = false;
  bool _loadingBaseline = true;
  Map<String, dynamic>? _previousCalibration;

  @override
  void initState() {
    super.initState();
    _loadCalibrationBaseline();
  }

  String get _platform {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => 'mobile',
      _ => 'pc',
    };
  }

  Future<void> _loadCalibrationBaseline() async {
    if (mounted) {
      setState(() {
        _loadingBaseline = true;
      });
    }

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );
      final result = await functions.httpsCallable('getGazeCalibration').call({
        'platform': _platform,
      });
      final response = result.data as Map<String, dynamic>?;
      final calibration = response?['calibrationData'];
      if (!mounted) return;
      setState(() {
        _previousCalibration = response?['exists'] == true && calibration is Map
            ? Map<String, dynamic>.from(calibration)
            : null;
        _loadingBaseline = false;
      });
    } catch (error) {
      debugPrint(
        '[profile-calibration] Could not load previous calibration: $error',
      );
      if (!mounted) return;
      setState(() {
        _previousCalibration = null;
        _loadingBaseline = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not load the cloud calibration ($error). The calibration page will check its local saved copy.',
          ),
        ),
      );
    }
  }

  Future<void> _handleCalibrationAction(
    String action,
    Map<String, dynamic>? data,
  ) async {
    debugPrint('[profile-calibration] Action: $action');

    switch (action) {
      case 'saveCalibration':
        await _saveCalibrationToFirebase(data);
        break;

      case 'calibrationComplete':
        // The saveCalibration action will be called separately
        break;

      case 'calibrationFailed':
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data?['error'] as String? ?? 'Calibration failed'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context, rootNavigator: true).pop();
        break;

      case 'calibrationCancelled':
        Navigator.of(context, rootNavigator: true).pop();
        break;

      default:
        debugPrint('[profile-calibration] Unknown action: $action');
    }
  }

  Future<void> _saveCalibrationToFirebase(Map<String, dynamic>? data) async {
    if (data == null) {
      debugPrint('[profile-calibration] No data to save');
      return;
    }

    if (!mounted) return;
    setState(() => _saving = true);

    try {
      final platform = data['platform'] as String?;
      if (platform != 'pc' && platform != 'mobile') {
        throw Exception('The detected device platform is invalid');
      }
      final calibrationData = data['calibrationData'];

      if (calibrationData == null) {
        throw Exception('No calibration data provided');
      }

      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );
      final callable = functions.httpsCallable('saveGazeCalibration');

      final result = await callable.call({
        'platform': platform,
        'calibrationData': calibrationData,
      });

      if (!mounted) return;

      final responseData = result.data as Map<String, dynamic>?;
      final success = responseData?['success'] == true;

      if (success) {
        final accuracy = responseData?['accuracy'] as num?;
        final learningSampleCount =
            responseData?['learningSampleCount'] as int?;
        final savedCalibration = calibrationData is Map
            ? Map<String, dynamic>.from(calibrationData)
            : null;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Calibration saved! Accuracy: ${accuracy?.toStringAsFixed(0)}px'
              '${learningSampleCount != null && learningSampleCount > 0 ? ' • $learningSampleCount learning samples' : ''}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );

        await _showSessionReport(savedCalibration);

        // Wait a bit before navigating back
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop(true);
        }
      } else {
        throw Exception('Save failed');
      }
    } catch (e) {
      debugPrint('[profile-calibration] Error saving calibration: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save calibration: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );

      setState(() => _saving = false);
    }
  }

  Future<void> _showSessionReport(Map<String, dynamic>? calibrationData) async {
    final rawReport = calibrationData?['sessionReport'];
    if (rawReport is! Map) return;

    final report = Map<String, dynamic>.from(rawReport);
    final rawSessions = report['sessions'];
    final sessions = rawSessions is List
        ? rawSessions
              .whereType<Map>()
              .map((session) => Map<String, dynamic>.from(session))
              .toList()
        : <Map<String, dynamic>>[];
    final displaySessions = [...sessions]
      ..sort((left, right) {
        final leftScore = left['score'];
        final rightScore = right['score'];
        if (leftScore is! num) return rightScore is! num ? 0 : 1;
        if (rightScore is! num) return -1;
        return rightScore.compareTo(leftScore);
      });
    final rawMatrix = report['matrix'];
    final matrix = rawMatrix is Map
        ? Map<String, dynamic>.from(rawMatrix)
        : <String, dynamic>{};
    if (sessions.isEmpty || !mounted) return;

    String sessionLabel(Object? value) {
      final id = value?.toString() ?? '';
      final session = sessions.cast<Map<String, dynamic>?>().firstWhere(
        (item) => item?['sessionId'] == id,
        orElse: () => null,
      );
      if (session?['isNew'] == true) return 'New run';
      if (id == 'legacy') return 'Previous data';
      final timestamp = int.tryParse(id.replaceFirst('session-', ''));
      if (timestamp == null) return id;
      final date = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    final disagreementRows = <Widget>[];
    for (final entry in matrix.entries) {
      if (entry.value is! Map) continue;
      for (final testEntry in Map<String, dynamic>.from(
        entry.value as Map,
      ).entries) {
        final error = testEntry.value;
        if (error is! num) continue;
        disagreementRows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${sessionLabel(entry.key)} → ${sessionLabel(testEntry.key)}: ${error.round()}px',
            ),
          ),
        );
      }
    }

    const ink = Color(0xFF111217);
    const muted = Color(0xFF6F7276);
    const green = Color(0xFF087B4F);
    const softGreen = Color(0xFFE8F5EE);
    const line = Color(0xFFDFE2DF);

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: softGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.insights_outlined,
                        color: green,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calibration updated',
                            style: TextStyle(
                              color: ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Session consistency report',
                            style: TextStyle(color: muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Lower scores mean the calibration runs agree more closely. The newest run is kept; when history exceeds four runs, the least consistent older run is removed.',
                  style: TextStyle(color: muted, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...displaySessions.map((session) {
                          final score = session['score'];
                          final isNew = session['isNew'] == true;
                          final removed = session['dropped'] == true;
                          final accent = removed
                              ? const Color(0xFFB42338)
                              : isNew
                              ? green
                              : muted;
                          final background = removed
                              ? const Color(0xFFFFF1F3)
                              : isNew
                              ? softGreen
                              : const Color(0xFFFAFBF9);
                          final border = removed
                              ? const Color(0xFFF0CAD0)
                              : isNew
                              ? const Color(0xFFCDE7D7)
                              : line;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: background,
                              border: Border.all(color: border),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sessionLabel(session['sessionId']),
                                        style: const TextStyle(
                                          color: ink,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (isNew || removed) ...[
                                        const SizedBox(height: 5),
                                        Text(
                                          removed
                                              ? 'Removed from calibration history'
                                              : 'Just recorded',
                                          style: TextStyle(
                                            color: accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  score is num
                                      ? '${score.round()} px'
                                      : 'Need another run',
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        if (disagreementRows.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          const Divider(color: line, height: 24),
                          const Text(
                            'Cross-check details',
                            style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Model trained on the first run, tested on the second.',
                            style: TextStyle(
                              color: muted,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFBF9),
                              border: Border.all(color: line),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: disagreementRows,
                            ),
                          ),
                        ] else if (sessions.length == 1) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: softGreen,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'This run is your baseline. Session comparison will be available after another nine-point calibration.',
                              style: TextStyle(
                                color: ink,
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (_loadingBaseline)
            const Center(child: CircularProgressIndicator())
          else
            ProfileGazeCalibrationView(
              previousCalibration: _previousCalibration,
              onAction: _handleCalibrationAction,
            ),
          if (_saving)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Card(
                  margin: EdgeInsets.all(24),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF087B4F)),
                        SizedBox(height: 16),
                        Text(
                          'Saving calibration to your profile...',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
