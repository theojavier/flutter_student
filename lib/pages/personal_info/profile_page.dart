import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../helpers/SecureStorageHelper.dart';
import '../../widgets/pull_to_refresh_shell.dart';
import '../../utils/string_keyed_map.dart';
import 'profile_calibration_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // FOTS editorial green palette, adapted from the supplied HTML.
  static const Color _background = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _green = Color(0xFF087B4F);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _softGreen = Color(0xFFDCF2E5);
  static const Color _warn = Color(0xFFB88826); // Orange for warnings

  String? _userId;
  Map<String, dynamic>? _userData;
  String? _latestClassYearBlock;
  String? _latestClassAcademicYear;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _calibrationStatus; // Gaze calibration status
  bool _loadingCalibrationStatus = true;

  @override
  void initState() {
    super.initState();
    AppRefresh.tick.addListener(_refreshProfile);
    _loadProfile();
    _loadCalibrationStatus();
  }

  @override
  void dispose() {
    AppRefresh.tick.removeListener(_refreshProfile);
    super.dispose();
  }

  void _refreshProfile() {
    _loadProfile();
    _loadCalibrationStatus();
  }

  Future<void> _loadProfile() async {
    try {
      final storedUserId = await SecureStorageHelper.read('userId');
      if (storedUserId == null || storedUserId.trim().isEmpty) {
        if (!mounted) return;
        setState(() {
          _error = 'No signed-in user was found. Please sign in again.';
          _loading = false;
        });
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(storedUserId)
          .get();

      if (!mounted) return;
      if (!snapshot.exists) {
        setState(() {
          _userId = storedUserId;
          _error = 'Profile not found.';
          _loading = false;
        });
        return;
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final classYearBlock = await _fetchLatestClassYearBlock(data);
      if (!mounted) return;
      setState(() {
        _userId = storedUserId;
        _userData = data;
        _latestClassYearBlock = classYearBlock;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load your profile. Please try again.';
        _loading = false;
      });
    }
  }

  Future<void> _loadCalibrationStatus() async {
    if (!mounted) return;
    setState(() => _loadingCalibrationStatus = true);

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );
      final callable = functions.httpsCallable('getGazeCalibrationStatus');

      final result = await callable.call();

      if (!mounted) return;

      final data = decodeStringKeyedMap(result.data);
      for (final platform in ['pc', 'mobile']) {
        final platformData = data?[platform];
        if (platformData != null) {
          data![platform] = decodeStringKeyedMap(platformData);
        }
      }
      setState(() {
        _calibrationStatus = data;
        _loadingCalibrationStatus = false;
      });
    } catch (e) {
      debugPrint('[profile] Error loading calibration status: $e');
      if (!mounted) return;
      setState(() => _loadingCalibrationStatus = false);
    }
  }

  Future<String?> _fetchLatestClassYearBlock(
    Map<String, dynamic> userData,
  ) async {
    _classYearBlockCandidates.clear();
    final firestore = FirebaseFirestore.instance;
    final classIds = <String>{};

    final singleClassId = userData['classId']?.toString().trim();
    if (singleClassId != null && singleClassId.isNotEmpty) {
      classIds.add(singleClassId);
    }

    final rawClassIds = userData['classIds'];
    if (rawClassIds is Iterable) {
      for (final id in rawClassIds) {
        final value = id?.toString().trim();
        if (value != null && value.isNotEmpty) classIds.add(value);
      }
    }

    // First try class document IDs stored on the user's profile.
    for (final id in classIds) {
      try {
        final doc = await firestore.collection('classes').doc(id).get();
        if (doc.exists && doc.data() != null) {
          // Keep only documents that actually contain a year/block value.
          if ((doc.data()!['yearBlock']?.toString().trim().isNotEmpty ??
              false)) {
            // Convert the document snapshot into a query snapshot candidate below
            // by retaining its data and timestamp separately.
            final value = doc.data()!['yearBlock'].toString().trim();
            if (value.isNotEmpty) {
              final updatedAt = doc.data()!['updatedAt'];
              _classYearBlockCandidates.add((
                value,
                doc.data()!['schoolYear']?.toString().trim(),
                _dateForSort(updatedAt),
              ));
            }
          }
        }
      } catch (_) {
        // Continue to the fallback query if a class document cannot be read.
      }
    }

    // If document IDs are auto-generated, also try the classId field itself.
    for (final id in classIds) {
      try {
        final query = await firestore
            .collection('classes')
            .where('classId', isEqualTo: id)
            .get();
        for (final doc in query.docs) {
          final value = doc.data()['yearBlock']?.toString().trim();
          if (value != null && value.isNotEmpty) {
            _classYearBlockCandidates.add((
              value,
              doc.data()['schoolYear']?.toString().trim(),
              _dateForSort(doc.data()['updatedAt']),
            ));
          }
        }
      } catch (_) {
        // Some class documents may not have a classId field.
      }
    }

    // Also look up by programCode. This handles class documents whose Firestore
    // document IDs are auto-generated rather than equal to classId.
    final programCode = userData['programCode']?.toString().trim();
    if (programCode != null && programCode.isNotEmpty) {
      try {
        final query = await firestore
            .collection('classes')
            .where('programCode', isEqualTo: programCode)
            .get();
        for (final doc in query.docs) {
          final value = doc.data()['yearBlock']?.toString().trim();
          if (value != null && value.isNotEmpty) {
            _classYearBlockCandidates.add((
              value,
              doc.data()['schoolYear']?.toString().trim(),
              _dateForSort(doc.data()['updatedAt']),
            ));
          }
        }
      } catch (_) {
        // Keep the year/block already available on the user profile as fallback.
      }
    }

    if (_classYearBlockCandidates.isEmpty) return null;
    _classYearBlockCandidates.sort((a, b) => b.$3.compareTo(a.$3));
    final latest = _classYearBlockCandidates.first;
    _latestClassAcademicYear = (latest.$2 != null && latest.$2!.isNotEmpty)
        ? latest.$2
        : null;
    _classYearBlockCandidates.clear();
    return latest.$1;
  }

  final List<(String, String?, DateTime)> _classYearBlockCandidates = [];

  DateTime _dateForSort(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _value(String key, [String fallback = 'N/A']) {
    final value = _userData?[key];
    if (value == null || value.toString().trim().isEmpty) return fallback;
    return value.toString();
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    if (parts.isEmpty) return 'ST';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length < 2 ? parts.first.length : 2)
          .toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _background,
        body: Center(child: CircularProgressIndicator(color: _green)),
      );
    }

    if (_error != null || _userData == null) {
      return Scaffold(
        backgroundColor: _background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off_outlined, size: 42, color: _muted),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Profile not found.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _ink, fontSize: 14),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _loadProfile();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final name = _value('name', _value('displayName', 'Student'));
    final imageUrl = _normaliseImageUrl(_value('profileImage', ''));
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          const Positioned(
            top: -120,
            right: -100,
            child: _BackgroundGlow(size: 340),
          ),
          const Positioned(
            bottom: -170,
            left: -140,
            child: _BackgroundGlow(size: 380),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                width < 600 ? 16 : 32,
                width < 600 ? 22 : 34,
                width < 600 ? 16 : 32,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1250),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Eyebrow('ACCOUNT  /  STUDENT RECORD'),
                      const SizedBox(height: 8),
                      const Text(
                        'My Profile',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 36,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'View your student information and enrollment details.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 26),
                      if (wide)
                        SizedBox(
                          height:
                              430, // CHANGE THIS VALUE TO INCREASE BOTH CARD HEIGHTS
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _profileCard(name, imageUrl),
                              ),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: _personalCard()),
                            ],
                          ),
                        )
                      else ...[
                        _profileCard(name, imageUrl),
                        const SizedBox(height: 16),
                        _personalCard(),
                      ],
                      const SizedBox(height: 18),
                      _enrollmentCard(),
                      const SizedBox(height: 18),
                      _gazeCalibrationCard(),
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

  Widget _gazeCalibrationCard() {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Gaze Tracking Calibration',
            subtitle: 'Setup and improve gaze tracking accuracy for exams',
            icon: Icons.remove_red_eye_outlined,
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Calibrate your gaze tracking for accurate exam monitoring. Your calibration improves automatically during exams.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 520;
                    return twoColumns
                        ? Row(
                            children: [
                              Expanded(child: _calibrationStatusCard('PC')),
                              const SizedBox(width: 14),
                              Expanded(child: _calibrationStatusCard('Mobile')),
                            ],
                          )
                        : Column(
                            children: [
                              _calibrationStatusCard('PC'),
                              const SizedBox(height: 14),
                              _calibrationStatusCard('Mobile'),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadingCalibrationStatus
                        ? null
                        : _startCalibration,
                    icon: const Icon(Icons.center_focus_strong, size: 17),
                    label: const Text('Calibrate this device'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calibrationStatusCard(String platform) {
    final platformKey = platform.toLowerCase();
    final statusData = decodeStringKeyedMap(_calibrationStatus?[platformKey]);

    final bool isCalibrated = statusData?['calibrated'] == true;
    final bool needsRecalibration = statusData?['needsRecalibration'] == true;
    final int? daysOld = statusData?['daysOld'] as int?;
    final double? accuracy = (statusData?['accuracy'] as num?)?.toDouble();
    final int? learningSamples = statusData?['learningSampleCount'] as int?;

    final IconData platformIcon = platform == 'PC'
        ? Icons.computer
        : Icons.phone_android;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBF9),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isCalibrated ? _softGreen : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  platformIcon,
                  color: isCalibrated ? _green : Colors.grey.shade400,
                  size: 20,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      platform.toUpperCase(),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isCalibrated
                          ? (needsRecalibration ? 'Needs update' : 'Calibrated')
                          : 'Not calibrated',
                      style: TextStyle(
                        color: isCalibrated
                            ? (needsRecalibration ? _warn : _green)
                            : _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isCalibrated && accuracy != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: _softGreen,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFB9E2CA)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 12,
                    color: _green,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Accuracy: ${accuracy.toStringAsFixed(0)}px',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _green,
                    ),
                  ),
                ],
              ),
            ),
            if (daysOld != null) ...[
              const SizedBox(height: 6),
              Text(
                'Calibrated $daysOld ${daysOld == 1 ? 'day' : 'days'} ago',
                style: const TextStyle(fontSize: 10, color: _muted),
              ),
            ],
            if (learningSamples != null && learningSamples > 0) ...[
              const SizedBox(height: 4),
              Text(
                '$learningSamples learning samples',
                style: const TextStyle(fontSize: 10, color: _muted),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _startCalibration() async {
    if (!await _requestCalibrationCameraPermission()) return;
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: const Color(0xB3000000),
      useSafeArea: false,
      builder: (_) => Dialog.fullscreen(
        backgroundColor: Colors.transparent,
        child: const ProfileCalibrationPage(),
      ),
    );

    // If calibration succeeded, reload status
    if (result == true) {
      _loadCalibrationStatus();
    }
  }

  Future<bool> _requestCalibrationCameraPermission() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return true;
    }

    try {
      final status = await Permission.camera.request();
      if (status.isGranted) return true;
      if (!mounted) return false;

      if (status.isPermanentlyDenied) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Camera permission required'),
            content: const Text(
              'Allow camera access in your device settings to calibrate gaze.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  final opened = await openAppSettings();
                  if (!opened && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not open app settings.'),
                      ),
                    );
                  }
                },
                child: const Text('Open settings'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera access is needed to start gaze calibration.'),
          ),
        );
      }
      return false;
    } catch (error) {
      debugPrint(
        '[profile-calibration] Camera permission request failed: $error',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not request camera access. Please try again.'),
          ),
        );
      }
      return false;
    }
  }

  String _normaliseImageUrl(String url) {
    if (url.isEmpty) return '';
    if (url.contains('imgur.com') && !url.contains('i.imgur.com')) {
      final clean = url.split('?').first;
      return '${clean.replaceAll('imgur.com', 'i.imgur.com')}.jpg';
    }
    return url;
  }

  Widget _profileCard(String name, String imageUrl) {
    return _Panel(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: _green,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(name),
                    )
                  : _avatarFallback(name),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            name.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _value('studentId', _value('ID', 'Student ID not set')),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: _softGreen,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFB9E2CA)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined, color: _green, size: 14),
                SizedBox(width: 6),
                Text(
                  'STUDENT PROFILE',
                  style: TextStyle(
                    color: _green,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Divider(color: _line, height: 1),
          const SizedBox(height: 15),
          _miniInfo(Icons.school_outlined, 'Program', _value('program')),
          const SizedBox(height: 13),
          _miniInfo(
            Icons.calendar_month_outlined,
            'Academic year',
            _latestClassAcademicYear ??
                _value('academicYear', _value('schoolYear')),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: _softGreen,
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: _green,
          fontSize: 25,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _miniInfo(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _green, size: 17),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _personalCard() {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Personal information',
            subtitle: 'Your details used across the student portal',
            icon: Icons.person_outline,
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 520;
                    final fieldWidth = twoColumns
                        ? (constraints.maxWidth - 14) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: fieldWidth,
                          child: _readOnlyField(
                            'DISPLAY NAME',
                            _value('name', _value('displayName', 'Student')),
                            Icons.person_outline,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _readOnlyField(
                            'STUDENT ID',
                            _value('studentId', _value('ID')),
                            Icons.badge_outlined,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _readOnlyField(
                            'GENDER',
                            _value('gender'),
                            Icons.wc_outlined,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _readOnlyField(
                            'CIVIL STATUS',
                            _value('civilStatus'),
                            Icons.favorite_border,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _readOnlyField(
                            'NATIONALITY',
                            _value('nationality'),
                            Icons.flag_outlined,
                          ),
                        ),
                        SizedBox(
                          width: fieldWidth,
                          child: _readOnlyField(
                            'DATE OF BIRTH',
                            _value('dob'),
                            Icons.cake_outlined,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: _muted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _enrollmentCard() {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Enrollment details',
            subtitle: 'Academic information associated with your account',
            icon: Icons.school_outlined,
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720
                    ? 3
                    : (constraints.maxWidth >= 420 ? 2 : 1);
                final gap = 12.0;
                final itemWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                final details = <(IconData, String, String)>[
                  (Icons.menu_book_outlined, 'PROGRAM', _value('program')),
                  (
                    Icons.groups_outlined,
                    'YEAR / BLOCK',
                    _latestClassYearBlock ?? _value('yearBlock'),
                  ),
                  (Icons.event_note_outlined, 'SEMESTER', _value('semester')),
                ];
                return Wrap(
                  spacing: gap,
                  runSpacing: 12,
                  children: details.map((item) {
                    return SizedBox(
                      width: itemWidth,
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAFBF9),
                          border: Border.all(color: _line),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _softGreen,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(item.$1, color: _green, size: 18),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.$2,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .5,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    item.$3,
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.96),
        border: Border.all(color: const Color(0xFFDFE2DF)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080D1015),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFDFE2DF))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFDCF2E5),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: const Color(0xFF087B4F), size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111217),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6F7276),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF666970),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF087B4F),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              const Color(0xFF58D99A).withOpacity(.12),
              const Color(0xFF58D99A).withOpacity(.035),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
