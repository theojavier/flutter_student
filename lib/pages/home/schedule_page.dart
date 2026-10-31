import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../helpers/SecureStorageHelper.dart';

typedef _Docs = List<DocumentSnapshot<Map<String, dynamic>>>;

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

// ============================================================
// HELPERS
// ============================================================

DateTime? _toDate(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

int? _intOf(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

String _text(dynamic v, [String fallback = '']) {
  final s = (v ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

String _norm(String s) => s.trim().toLowerCase();

/// "08:30" -> 510
int? _parseHm(dynamic value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_text(value));
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

DateTime _mondayOf(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Reads the canonical class schedule, with support for older day fields.
Set<int> _classDays(Map<String, dynamic> d) {
  const names = {
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
  };

  int? weekdayOf(dynamic item) {
    if (item is num && item >= 1 && item <= 7) return item.toInt();
    final value = item.toString().trim().toLowerCase();
    if (value.length < 3) return null;
    return names[value.substring(0, 3)];
  }

  final out = <int>{};
  final schedules = d['schedules'];
  if (schedules is List) {
    for (final rawSchedule in schedules) {
      if (rawSchedule is! Map) continue;
      final weekday = weekdayOf(rawSchedule['dayOfWeek']);
      if (weekday != null) out.add(weekday);
    }
  }
  if (out.isNotEmpty) return out;

  final rawScheduleDays = d['scheduleDays'];
  final raw = rawScheduleDays is List && rawScheduleDays.isNotEmpty
      ? rawScheduleDays
      : d['days'] ?? d['day'] ?? d['dayOfWeek'];
  final List items = raw is List
      ? raw
      : raw is String
      ? raw.split(RegExp(r'[,/;\s]+'))
      : const [];
  for (final item in items) {
    final weekday = weekdayOf(item);
    if (weekday != null) out.add(weekday);
  }
  return out;
}

/// Every (weekday, start, end) session of a class.
List<({int weekday, int start, int end})> _classScheduleSlots(
  Map<String, dynamic> data,
) {
  int? minutesOf(Map<dynamic, dynamic> source, String key, String labelKey) {
    final value = source[key];
    if (value is num) return value.toInt();
    return _parseHm(source[labelKey]);
  }

  const weekdays = {
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
  };

  int? weekdayOf(dynamic item) {
    if (item is num && item >= 1 && item <= 7) return item.toInt();
    final value = item.toString().trim().toLowerCase();
    if (value.length < 3) return null;
    return weekdays[value.substring(0, 3)];
  }

  final slots = <({int weekday, int start, int end})>[];
  final rawSchedules = data['schedules'];
  if (rawSchedules is List && rawSchedules.isNotEmpty) {
    for (final rawSchedule in rawSchedules) {
      if (rawSchedule is! Map) continue;
      final weekday = weekdayOf(rawSchedule['dayOfWeek']);
      final start = minutesOf(rawSchedule, 'startMinutes', 'startLabel');
      if (weekday == null || start == null) continue;
      final duration = _intOf(rawSchedule['durationMin']);
      final end =
          minutesOf(rawSchedule, 'endMinutes', 'endLabel') ??
          (duration == null || duration <= 0 ? null : start + duration);
      if (end != null && end > start) {
        slots.add((weekday: weekday, start: start, end: end));
      }
    }
  } else {
    // Old single-slot format
    final start = minutesOf(data, 'startMinutes', 'startLabel');
    final duration = _intOf(data['durationMin']);
    final end =
        minutesOf(data, 'endMinutes', 'endLabel') ??
        (start == null || duration == null || duration <= 0
            ? null
            : start + duration);
    if (start != null && end != null && end > start) {
      for (final weekday in _classDays(data)) {
        slots.add((weekday: weekday, start: start, end: end));
      }
    }
  }
  slots.sort((a, b) {
    final byDay = a.weekday.compareTo(b.weekday);
    return byDay != 0 ? byDay : a.start.compareTo(b.start);
  });
  return slots;
}

// ============================================================
// MODELS
// ============================================================

class _Entry {
  const _Entry({
    required this.title,
    this.classId = '',
    required this.start,
    required this.end,
    required this.isExam,
    this.room = '',
    this.adviser = '',
    this.linked = false,
    this.both = false,
  });

  final String title;
  final String classId;
  final DateTime start;
  final DateTime end;
  final bool isExam;
  final bool both;
  final String room;
  final String adviser;

  /// True when an approved exam is linked to this class.
  final bool linked;

  String get key => '$classId|$title|${start.toIso8601String()}|$isExam';

  /// Minutes from midnight (clamped to the start day).
  int get startMin => start.hour * 60 + start.minute;

  int get endMin {
    if (!_sameDay(start, end)) return 24 * 60;
    final e = end.hour * 60 + end.minute;
    return e <= startMin ? startMin + 60 : e;
  }
}

class _Unplaced {
  const _Unplaced({
    required this.title,
    required this.timeLabel,
    required this.room,
    required this.adviser,
  });

  final String title;
  final String timeLabel;
  final String room;
  final String adviser;
}

class _ExamInfo {
  const _ExamInfo({
    required this.id,
    required this.subject,
    required this.classId,
    required this.start,
    required this.end,
  });

  final String id;
  final String subject;
  final String classId;
  final DateTime start;
  final DateTime end;
}

class _ScheduleData {
  const _ScheduleData(this.entries, this.unplaced);
  final List<_Entry> entries;
  final List<_Unplaced> unplaced;
}

/// A card with its final position inside a day column.
class _Placed {
  const _Placed(this.entry, this.top, this.height, this.stacked);
  final _Entry entry;
  final double top;
  final double height;

  /// True when this card overlaps another one (shown as a stacked card).
  final bool stacked;
}

// ============================================================
// HOVER CARD (pops up above the child)
// ============================================================

class _HoverCard extends StatefulWidget {
  const _HoverCard({
    required this.child,
    required this.popup,
    this.onHoverChange,
  });

  final Widget child;
  final Widget popup;
  final ValueChanged<bool>? onHoverChange;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;

  void _show() {
    if (_entry != null) return;

    // If there is no room above (top of the screen), show it below instead.
    var below = false;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      below = box.localToGlobal(Offset.zero).dy < 240;
    }

    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          targetAnchor: below ? Alignment.bottomCenter : Alignment.topCenter,
          followerAnchor: below ? Alignment.topCenter : Alignment.bottomCenter,
          offset: Offset(0, below ? 8 : -8),
          child: IgnorePointer(
            child: Material(color: Colors.transparent, child: widget.popup),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    widget.onHoverChange?.call(true);
  }

  void _hide() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    widget.onHoverChange?.call(false);
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _show(),
        onExit: (_) => _hide(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Touch devices: tap to toggle.
          onTap: () => _entry == null ? _show() : _hide(),
          child: widget.child,
        ),
      ),
    );
  }
}

// ============================================================
// PAGE
// ============================================================

class _SchedulePageState extends State<SchedulePage> {
  // FOTS editorial palette (green)
  static const Color _bg = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _accent = Color(0xFF087B4F);
  static const Color _accentDark = Color(0xFF075C3C);
  static const Color _accentSoft = Color(0xFFE8F5EB);
  static const Color _examSoft = Color(0xFFEDEEF0);
  static const Color _todayTint = Color(0xFFFAFCFA);
  static const Color _line = Color(0xFFDFE2DF);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _muted2 = Color(0xFF8A8D91);
  static const String _mono = 'monospace';

  // Grid sizing
  static const double _timeColumnWidth = 78;
  static const double _dayColumnWidth = 170;
  static const double _hourRowHeight = 88;

  /// How much of a card stays visible when another card covers it.
  static const double _peek = 28;
  static const double _minCardHeight = 64;

  final FirebaseFirestore db = FirebaseFirestore.instance;
  final DateFormat _timeFmt = DateFormat('h:mm a');

  /// Key of the card the mouse is over (it is brought to the front).
  final ValueNotifier<String?> _hover = ValueNotifier<String?>(null);

  late DateTime _weekStart;

  bool _loading = true;
  bool _missingInfo = false;
  String? _loadError;
  String? _yearBlock;

  Stream<_Docs>? _classesStream;
  Stream<_Docs>? _examsStream;

  @override
  void initState() {
    super.initState();
    _weekStart = _mondayOf(DateTime.now());
    _loadPrefs();
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final storedProgram = await SecureStorageHelper.read('program');
    final storedCode = await SecureStorageHelper.read('programCode');
    final storedYearBlock = await SecureStorageHelper.read('yearBlock');

    String profileCode = '';
    String profileYearBlock = '';
    var classIds = <String>[];

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final profile = await db.collection('users').doc(uid).get();
        final user = profile.data();
        if (user != null) {
          profileCode = _text(user['programCode']);
          profileYearBlock = _text(user['yearBlock']);
          final raw = user['classIds'];
          if (raw is List) {
            classIds = raw
                .map((item) => item.toString().trim())
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList();
          }
        }
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _loadError = 'Unable to load your student profile: $error';
          _loading = false;
        });
        return;
      }
    }

    final programValue = [
      profileCode,
      (storedCode ?? '').trim(),
      (storedProgram ?? '').trim(),
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final yearBlock = [
      profileYearBlock,
      (storedYearBlock ?? '').trim(),
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');

    if (!mounted) return;

    // Irregular students are enrolled in specific classes rather than a block.
    if (_norm(yearBlock) == 'irregular') {
      final ids = classIds.take(30).toList();
      setState(() {
        _yearBlock = 'Irregular · ${classIds.length} classes';
        _classesStream = _combine([
          for (final id in ids)
            db
                .collection('classes')
                .doc(id)
                .snapshots()
                .map(
                  (snapshot) => <DocumentSnapshot<Map<String, dynamic>>>[
                    snapshot,
                  ],
                ),
        ]);
        _examsStream = _combine([
          for (final id in ids)
            _docsOf(db.collection('exams').where('classId', isEqualTo: id)),
        ]);
        _loading = false;
      });
      return;
    }

    if (programValue.isEmpty || yearBlock.isEmpty) {
      setState(() {
        _missingInfo = true;
        _loading = false;
      });
      return;
    }

    setState(() {
      _yearBlock = yearBlock;
      _classesStream = _docsOf(
        db
            .collection('classes')
            .where('program', isEqualTo: programValue)
            .where('yearBlock', isEqualTo: yearBlock),
      );
      _examsStream = _docsOf(
        db
            .collection('exams')
            .where('program', isEqualTo: programValue)
            .where('yearBlock', isEqualTo: yearBlock),
      );
      _loading = false;
    });
  }

  Stream<_Docs> _docsOf(Query<Map<String, dynamic>> query) =>
      query.snapshots().map(
        (snapshot) =>
            List<DocumentSnapshot<Map<String, dynamic>>>.from(snapshot.docs),
      );

  /// Merges several snapshot streams into one list (no extra packages).
  Stream<_Docs> _combine(List<Stream<_Docs>> sources) {
    if (sources.isEmpty) {
      return Stream.value(<DocumentSnapshot<Map<String, dynamic>>>[]);
    }

    final latest = List<_Docs?>.filled(sources.length, null);
    final subscriptions = <StreamSubscription<_Docs>>[];
    late final StreamController<_Docs> controller;

    void emit() {
      if (latest.any((docs) => docs == null)) return;
      controller.add([for (final docs in latest) ...docs!]);
    }

    controller = StreamController<_Docs>.broadcast(
      onListen: () {
        for (var i = 0; i < sources.length; i++) {
          subscriptions.add(
            sources[i].listen((docs) {
              latest[i] = docs;
              emit();
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        subscriptions.clear();
      },
    );
    return controller.stream;
  }

  // ============================================================
  // SCHEDULE LOGIC
  // ============================================================
  //
  // 1. Classes come from the `classes` collection (status == active).
  // 2. Each class repeats weekly for every configured schedule slot.
  // 3. An approved exam merges only with the matching class session it overlaps.
  // 4. A class without a usable schedule and without an exam goes in the
  //    "day or time not set" list.
  // 5. Exams can be anywhere. When anything overlaps in time, the cards
  //    are stacked (see _stackDay).

  _ScheduleData _compose(_Docs classDocs, _Docs examDocs) {
    final exams = <_ExamInfo>[];
    for (final doc in examDocs) {
      final d = doc.data();
      if (d == null) continue;
      if (_text(d['approvalStatus']) != 'approved') continue;
      final start = _toDate(d['startTime']);
      if (start == null) continue;
      final end =
          _toDate(d['endTime']) ??
          start.add(
            Duration(
              minutes: _intOf(d['duration'] ?? d['durationMinutes']) ?? 60,
            ),
          );
      exams.add(
        _ExamInfo(
          id: doc.id,
          subject: _text(d['subject'], 'Untitled exam'),
          classId: _text(d['classId']),
          start: start,
          end: end,
        ),
      );
    }

    final entries = <_Entry>[];
    final unplaced = <_Unplaced>[];
    final examClassInfo =
        <String, ({String classId, String room, String adviser})>{};

    for (final doc in classDocs) {
      final d = doc.data();
      if (d == null) continue;
      if (_text(d['status']) != 'active') continue;

      final subject = _text(d['subject'], 'Untitled class');
      final room = _text(d['roomDefault']);
      final adviser = _text(d['adviserName']);

      final slots = _classScheduleSlots(d);

      final myExams = exams.where((e) => e.classId == doc.id).toList();
      for (final e in myExams) {
        examClassInfo[e.id] = (classId: doc.id, room: room, adviser: adviser);
      }

      if (slots.isNotEmpty) {
        for (final slot in slots) {
          final date = DateTime(
            _weekStart.year,
            _weekStart.month,
            _weekStart.day + (slot.weekday - 1),
          );
          entries.add(
            _Entry(
              title: subject,
              classId: doc.id,
              start: DateTime(
                date.year,
                date.month,
                date.day,
                slot.start ~/ 60,
                slot.start % 60,
              ),
              end: DateTime(
                date.year,
                date.month,
                date.day,
              ).add(Duration(minutes: slot.end)),
              isExam: false,
              room: room,
              adviser: adviser,
            ),
          );
        }
      } else if (myExams.isEmpty) {
        final legacyStart =
            _intOf(d['startMinutes']) ?? _parseHm(d['startLabel']);
        final duration = _intOf(d['durationMin']);
        final legacyEnd =
            _intOf(d['endMinutes']) ??
            _parseHm(d['endLabel']) ??
            (legacyStart == null
                ? null
                : legacyStart +
                      (duration != null && duration > 0 ? duration : 60));
        final label =
            legacyStart != null && legacyEnd != null && legacyEnd > legacyStart
            ? '${_minutesLabel(legacyStart)} – ${_minutesLabel(legacyEnd)}'
            : 'Time not set';
        unplaced.add(
          _Unplaced(
            title: subject,
            timeLabel: label,
            room: room,
            adviser: adviser,
          ),
        );
      }
    }

    // Approved exams (linked to a class or not)
    final weekEnd = DateTime(
      _weekStart.year,
      _weekStart.month,
      _weekStart.day + 7,
    );
    for (final e in exams) {
      if (e.start.isBefore(_weekStart) || !e.start.isBefore(weekEnd)) continue;
      final info = examClassInfo[e.id];

      // Merge only the matching class session that overlaps this exam.
      final i = entries.indexWhere(
        (c) =>
            !c.isExam &&
            _sameDay(c.start, e.start) &&
            c.start.isBefore(e.end) &&
            c.end.isAfter(e.start) &&
            e.classId.isNotEmpty &&
            c.classId == e.classId,
      );

      final merged = _Entry(
        title: e.subject,
        classId: info?.classId ?? e.classId,
        start: e.start,
        end: e.end,
        isExam: true,
        both: i != -1,
        room: info?.room ?? '',
        adviser: info?.adviser ?? '',
        linked: info != null,
      );

      if (i != -1) {
        entries[i] = merged;
      } else {
        entries.add(merged);
      }
    }

    entries.sort((a, b) => a.start.compareTo(b.start));
    unplaced.sort((a, b) => a.title.compareTo(b.title));
    return _ScheduleData(entries, unplaced);
  }

  String _minutesLabel(int minutes) {
    final m = minutes % (24 * 60);
    return _timeFmt.format(DateTime(2000, 1, 1, m ~/ 60, m % 60));
  }

  // ============================================================
  // STACK LAYOUT
  // ============================================================
  //
  // Cards that overlap in time form a "cluster" and are drawn as a
  // stack: each card starts at its real time but is pushed down at least
  // `_peek` px below the previous card, so its header always stays
  // visible. Later cards sit on top, the last one shows fully.
  // Hovering any card brings it to the front.

  List<_Placed> _stackDay(
    List<_Entry> items,
    int firstHour,
    double totalHeight,
  ) {
    final sorted = [...items]..sort((a, b) => a.start.compareTo(b.start));
    final result = <_Placed>[];

    // Group into clusters of overlapping entries.
    final clusters = <List<_Entry>>[];
    var clusterEnd = -1;
    for (final e in sorted) {
      if (clusters.isNotEmpty && e.startMin < clusterEnd) {
        clusters.last.add(e);
        if (e.endMin > clusterEnd) clusterEnd = e.endMin;
      } else {
        clusters.add([e]);
        clusterEnd = e.endMin;
      }
    }

    for (final cluster in clusters) {
      final stacked = cluster.length > 1;
      var prevTop = -1000.0;
      for (final e in cluster) {
        final naturalTop = (e.startMin - firstHour * 60) / 60 * _hourRowHeight;
        final naturalBottom =
            (e.endMin - firstHour * 60) / 60 * _hourRowHeight - 3;

        var top = naturalTop + 2;
        if (stacked && top < prevTop + _peek) top = prevTop + _peek;

        var bottom = naturalBottom < top + _minCardHeight
            ? top + _minCardHeight
            : naturalBottom;
        if (bottom > totalHeight - 2) bottom = totalHeight - 2;
        if (bottom < top + 30) top = bottom - 30;

        prevTop = top;
        result.add(_Placed(e, top, bottom - top, stacked));
      }
    }
    return result;
  }

  // ============================================================
  // WEEK NAVIGATION
  // ============================================================

  void _shiftWeek(int delta) {
    setState(() {
      _weekStart = DateTime(
        _weekStart.year,
        _weekStart.month,
        _weekStart.day + (7 * delta),
      );
    });
  }

  void _goToToday() => setState(() => _weekStart = _mondayOf(DateTime.now()));

  String _weekLabel() {
    final end = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6);
    return '${DateFormat('MMM d').format(_weekStart)} – ${DateFormat('MMM d, y').format(end)}'
        .toUpperCase();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: _stateBox(
          Icons.error_outline,
          'Unable to load student profile',
          _loadError!,
        ),
      );
    }

    if (_missingInfo) {
      return Scaffold(
        backgroundColor: _bg,
        body: _stateBox(
          Icons.info_outline,
          'Student information missing',
          'Your program or year/block could not be found. Please sign in again.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1350),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _pageHead(),
                  const SizedBox(height: 22),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: _cardBox(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [_cardHeader(), _scheduleBody()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // STYLES
  // ============================================================

  TextStyle _monoStyle(double size, {Color color = _muted2}) => TextStyle(
    fontFamily: _mono,
    fontSize: size,
    color: color,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w500,
  );

  TextStyle _display(double size, {Color color = _ink, double h = 1.0}) =>
      TextStyle(
        fontSize: size,
        height: h,
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: -size * 0.05,
      );

  BoxDecoration _cardBox({Color color = Colors.white, double radius = 10}) =>
      BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _line),
      );

  // ============================================================
  // PAGE HEAD
  // ============================================================

  Widget _pageHead() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("FOTS / SCHEDULE", style: _monoStyle(11, color: _accent)),
        const SizedBox(height: 10),
        Text("Schedule.", style: _display(38, h: 1.08)),
        const SizedBox(height: 7),
        const Text(
          "Your weekly classes and approved exams. Overlapping items stack "
          "like cards — hover one to bring it forward.",
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  // ============================================================
  // CARD HEADER (title, week navigator, legend)
  // ============================================================

  Widget _cardHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;

          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Weekly Schedule",
                style: TextStyle(
                  color: _ink,
                  fontSize: 26,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Classes and approved exams for ${_yearBlock ?? ''}",
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          );

          final nav = _weekNavigator();

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 16), nav],
            );
          }

          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 20),
              nav,
            ],
          );
        },
      ),
    );
  }

  Widget _weekNavigator() {
    Widget arrow(IconData icon, VoidCallback onTap, String tip) => Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: _cardBox(radius: 8),
          child: Icon(icon, size: 20, color: _ink),
        ),
      ),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        arrow(Icons.chevron_left, () => _shiftWeek(-1), 'Previous week'),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: _cardBox(color: _bg, radius: 8),
          child: Text(_weekLabel(), style: _monoStyle(11, color: _ink)),
        ),
        arrow(Icons.chevron_right, () => _shiftWeek(1), 'Next week'),
        OutlinedButton(
          onPressed: _goToToday,
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            backgroundColor: _accentSoft,
            minimumSize: const Size(0, 40),
            side: BorderSide(color: _accent.withOpacity(.25)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text("TODAY", style: _monoStyle(10, color: _accent)),
        ),
      ],
    );
  }

  // ============================================================
  // BODY (streams -> weekly table)
  // ============================================================

  Widget _scheduleBody() {
    return StreamBuilder<_Docs>(
      stream: _classesStream,
      builder: (context, classSnap) {
        if (classSnap.hasError) {
          return _stateBox(
            Icons.error_outline,
            'Unable to load classes',
            classSnap.error.toString(),
          );
        }

        return StreamBuilder<_Docs>(
          stream: _examsStream,
          builder: (context, examSnap) {
            if (examSnap.hasError) {
              return _stateBox(
                Icons.error_outline,
                'Unable to load exams',
                examSnap.error.toString(),
              );
            }

            if (!classSnap.hasData || !examSnap.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 70),
                child: Center(child: CircularProgressIndicator(color: _accent)),
              );
            }

            final classDocs = classSnap.data!
                .where((doc) => doc.exists)
                .toList();
            final examDocs = examSnap.data!;
            final data = _compose(classDocs, examDocs);

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _weeklyTable(data.entries),
                if (data.unplaced.isNotEmpty) _unplacedSection(data.unplaced),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // WEEKLY TABLE
  // ============================================================

  Widget _weeklyTable(List<_Entry> entries) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Timeline grows if something starts before 7 AM or ends after 7 PM.
    var firstHour = 7;
    var lastHour = 19;
    for (final e in entries) {
      final sh = e.startMin ~/ 60;
      final eh = (e.endMin + 59) ~/ 60;
      if (sh < firstHour) firstHour = sh;
      if (eh > lastHour) lastHour = eh;
    }
    if (lastHour > 24) lastHour = 24;

    final days = List.generate(
      7,
      (i) => DateTime(_weekStart.year, _weekStart.month, _weekStart.day + i),
    );

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              dragDevices: const {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.stylus,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _tableCorner(),
                      for (final day in days)
                        _weekdayHeader(day, isToday: _sameDay(day, today)),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          for (int h = firstHour; h < lastHour; h++)
                            _timeCell(h),
                        ],
                      ),
                      for (final day in days)
                        _dayScheduleColumn(
                          day: day,
                          entries: entries,
                          firstHour: firstHour,
                          lastHour: lastHour,
                          isToday: _sameDay(day, today),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: _line)),
            ),
            child: Wrap(
              spacing: 20,
              runSpacing: 10,
              children: [
                _tableLegend(color: _accent, label: 'CLASS'),
                _tableLegend(color: _ink, label: 'EXAM'),
                _tableLegend(color: _accentDark, label: 'CLASS + EXAM'),
                _tableLegend(color: _todayTint, label: 'TODAY', outlined: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableCorner() {
    return Container(
      width: _timeColumnWidth,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(
          right: BorderSide(color: _line),
          bottom: BorderSide(color: _line),
        ),
      ),
      child: Text('TIME', style: _monoStyle(9, color: _muted)),
    );
  }

  Widget _weekdayHeader(DateTime day, {required bool isToday}) {
    return Container(
      width: _dayColumnWidth,
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isToday ? _accentSoft : Colors.white,
        border: Border(
          right: const BorderSide(color: _line),
          bottom: BorderSide(
            color: isToday ? _accent : _line,
            width: isToday ? 2 : 1,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('EEEE').format(day).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _monoStyle(10, color: isToday ? _accent : _muted),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('MMM d').format(day),
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeCell(int hour) {
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour >= 12 && hour < 24 ? 'PM' : 'AM';

    return Container(
      width: _timeColumnWidth,
      height: _hourRowHeight,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(
          right: BorderSide(color: _line),
          bottom: BorderSide(color: _line),
        ),
      ),
      child: Text('$displayHour $period', style: _monoStyle(10, color: _muted)),
    );
  }

  Widget _dayScheduleColumn({
    required DateTime day,
    required List<_Entry> entries,
    required int firstHour,
    required int lastHour,
    required bool isToday,
  }) {
    final totalHeight = (lastHour - firstHour) * _hourRowHeight;
    final placed = _stackDay(
      entries.where((e) => _sameDay(e.start, day)).toList(),
      firstHour,
      totalHeight,
    );

    final grid = Column(
      children: [
        for (int h = firstHour; h < lastHour; h++)
          Container(
            width: _dayColumnWidth,
            height: _hourRowHeight,
            decoration: BoxDecoration(
              color: isToday ? _todayTint : Colors.white,
              border: const Border(
                right: BorderSide(color: _line),
                bottom: BorderSide(color: _line),
              ),
            ),
          ),
      ],
    );

    // Rebuilds only this stack when the hovered card changes.
    return ValueListenableBuilder<String?>(
      valueListenable: _hover,
      builder: (context, hovered, _) {
        // Hovered card goes last so it is drawn on top.
        final ordered = [...placed];
        final hi = ordered.indexWhere((p) => p.entry.key == hovered);
        if (hi != -1) ordered.add(ordered.removeAt(hi));

        return SizedBox(
          width: _dayColumnWidth,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              grid,
              for (final p in ordered)
                _positionedCard(p, isHovered: p.entry.key == hovered),
            ],
          ),
        );
      },
    );
  }

  Widget _positionedCard(_Placed p, {required bool isHovered}) {
    final e = p.entry;
    return Positioned(
      key: ValueKey(e.key),
      top: p.top,
      left: 5,
      right: 5,
      height: p.height,
      child: _HoverCard(
        popup: _popupCard(e),
        onHoverChange: (on) {
          if (on) {
            _hover.value = e.key;
          } else if (_hover.value == e.key) {
            _hover.value = null;
          }
        },
        child: _eventCard(p, isHovered: isHovered),
      ),
    );
  }

  /// A card in the grid: rounded, soft fill, solid border.
  /// The header row stays visible when another card covers the rest.
  Widget _eventCard(_Placed p, {required bool isHovered}) {
    final e = p.entry;
    final Color color = e.both ? _accentDark : (e.isExam ? _ink : _accent);
    final Color fill = e.both
        ? const Color(0xFFD3EBDD)
        : (e.isExam ? _examSoft : _accentSoft);
    final timeRange = '${_timeFmt.format(e.start)} – ${_timeFmt.format(e.end)}';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, isHovered ? -1 : 0, 0),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(isHovered ? .9 : .55)),
        boxShadow: (p.stacked || isHovered)
            ? [
                BoxShadow(
                  color: Colors.black.withOpacity(isHovered ? .18 : .08),
                  blurRadius: isHovered ? 14 : 6,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // HEADER ROW (always visible, even when stacked)
              SizedBox(
                height: _peek - 10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      e.both ? 'CLASS + EXAM' : (e.isExam ? 'EXAM' : 'CLASS'),
                      style: _monoStyle(8, color: color),
                    ),
                  ],
                ),
              ),
              if (p.height >= 52) ...[
                const SizedBox(height: 4),
                Text(
                  timeRange,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
              if (p.height >= 72 && e.room.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  e.room,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (p.height >= 90 && e.linked) ...[
                const SizedBox(height: 3),
                const Text(
                  'EXAM LINKED',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _accentDark,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The detail card that pops up on hover (full date, time, room...).
  Widget _popupCard(_Entry e) {
    final Color color = e.both ? _accentDark : (e.isExam ? _ink : _accent);
    final date = DateFormat('EEEE, MMMM d, y').format(e.start);
    final time = '${_timeFmt.format(e.start)} – ${_timeFmt.format(e.end)}';
    final mins = e.end.difference(e.start).inMinutes;
    final duration = mins >= 60
        ? '${mins ~/ 60} hr${mins % 60 == 0 ? '' : ' ${mins % 60} min'}'
        : '$mins min';

    Widget row(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          Icon(icon, size: 14, color: _muted2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.3),
            ),
          ),
        ],
      ),
    );

    return Container(
      width: 270,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.both ? 'CLASS + EXAM' : (e.isExam ? 'EXAM' : 'CLASS'),
                        style: _monoStyle(9, color: color),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        e.title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      row(Icons.calendar_today_outlined, date),
                      row(Icons.schedule, '$time  ·  $duration'),
                      if (e.room.isNotEmpty)
                        row(Icons.meeting_room_outlined, e.room),
                      if (e.adviser.isNotEmpty)
                        row(Icons.person_outline, e.adviser),
                      if (e.linked)
                        Padding(
                          padding: const EdgeInsets.only(top: 9),
                          child: Text(
                            'LINKED TO APPROVED EXAM',
                            style: _monoStyle(8, color: _accentDark),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableLegend({
    required Color color,
    required String label,
    bool outlined = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: outlined
                ? Border.all(color: _accent.withOpacity(.35))
                : null,
          ),
        ),
        const SizedBox(width: 7),
        Text(label, style: _monoStyle(9, color: _muted)),
      ],
    );
  }

  // ============================================================
  // CLASSES WITH NO DAY SET
  // ============================================================

  Widget _unplacedSection(List<_Unplaced> items) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _line)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "WEEKLY CLASSES · DAY OR TIME NOT SET",
            style: _monoStyle(10, color: _ink),
          ),
          const SizedBox(height: 5),
          const Text(
            "These classes are missing a day or a time, so they cannot be placed on the grid.",
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 10),
          for (final u in items)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: _cardBox(radius: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (u.room.isNotEmpty || u.adviser.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (u.room.isNotEmpty) u.room,
                              if (u.adviser.isNotEmpty) u.adviser,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _monoStyle(9),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(u.timeLabel, style: _monoStyle(10, color: _ink)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // EMPTY / ERROR STATE
  // ============================================================

  Widget _stateBox(IconData icon, String title, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 50),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _accent, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
