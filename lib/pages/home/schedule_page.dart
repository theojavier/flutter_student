import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final DateFormat timeFormat = DateFormat("h:mm a");
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  String? studentId;
  String? program;
  String? yearBlock;
  bool loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadStudentId();
  }
  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  Future<void> _loadStudentId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString("studentId");

    if (id == null) {
      setState(() => loadingUser = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No student session found")),
      );
      return;
    }

    setState(() => studentId = id);
    _loadStudentData(id);
  }

  Future<void> _loadStudentData(String studentId) async {
    try {
      final query = await firestore
          .collection("users")
          .where("studentId", isEqualTo: studentId)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final userDoc = query.docs.first;
        setState(() {
          program = userDoc["program"];
          yearBlock = userDoc["yearBlock"];
          loadingUser = false;
        });
      } else {
        setState(() => loadingUser = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No user found for ID $studentId")),
        );
      }
    } catch (e) {
      setState(() => loadingUser = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading user: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hours = List.generate(12, (i) => 7 + i); // 7AM–7PM
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Schedule"),
        automaticallyImplyLeading: false,
        centerTitle: true,
      ),
      body: loadingUser
          ? const Center(child: CircularProgressIndicator())
          : (program == null || yearBlock == null)
              ? const Center(child: Text("No program/yearBlock found"))
              : StreamBuilder<QuerySnapshot>(
                  stream: firestore
                      .collection("exams")
                      .where("program", isEqualTo: program)
                      .where("yearBlock", isEqualTo: yearBlock)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }

                    // Build a map of exams by day+hour
                    final Map<int, Map<int, String>> scheduleTable = {};

                    if (snapshot.hasData) {
                      for (var doc in snapshot.data!.docs) {
                        final start =
                            (doc["startTime"] as Timestamp).toDate();
                        final end =
                            (doc["endTime"] as Timestamp).toDate();
                        final subject = doc["subject"];

                        if (start.isAfter(weekStart) &&
                            start.isBefore(weekEnd)) {
                          final dayIndex = start.weekday; // 1=Mon … 7=Sun
                          final startHour = start.hour;
                          final endHour = end.hour;

                          final allowedStart =
                              startHour.clamp(7, 19);
                          final allowedEnd =
                              endHour.clamp(7, 19);

                          final timeRange =
                              "${timeFormat.format(start)} – ${timeFormat.format(end)}";

                          scheduleTable[dayIndex] ??= {};
                          for (int hour = allowedStart;
                              hour < allowedEnd;
                              hour++) {
                            final existing =
                                scheduleTable[dayIndex]![hour];
                            scheduleTable[dayIndex]![hour] =
                                "${existing == null || existing.isEmpty
                                        ? ""
                                        : "$existing\n\n"}$subject\n$timeRange";
                          }
                        }
                      }
                    }

                    // Build 8-column table: Time | Mon … Sun
                    // Build 8-column table: Time | Mon … Sun
return Scrollbar(
  controller: _horizontalController,
  thumbVisibility: true,
  notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
  child: SingleChildScrollView(
    controller: _horizontalController,
    scrollDirection: Axis.horizontal,
    child: Scrollbar(
      controller: _verticalController,
      thumbVisibility: true,
      notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
      child: SingleChildScrollView(
        controller: _verticalController,
        scrollDirection: Axis.vertical,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 1120),
          child: Table(
                border: TableBorder.all(color: Colors.black26),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {
                  0: FixedColumnWidth(140),
                  1: FixedColumnWidth(140),
                  2: FixedColumnWidth(140),
                  3: FixedColumnWidth(140),
                  4: FixedColumnWidth(140),
                  5: FixedColumnWidth(140),
                  6: FixedColumnWidth(140),
                  7: FixedColumnWidth(140),
                },
                children: [
                  TableRow(
                    decoration: const BoxDecoration(color: Colors.teal),
                    children: [
                      _headerCell("Time"),
                      _headerCell("Mon"),
                      _headerCell("Tue"),
                      _headerCell("Wed"),
                      _headerCell("Thu"),
                      _headerCell("Fri"),
                      _headerCell("Sat"),
                      _headerCell("Sun"),
                    ],
                  ),
                  for (final hour in hours)
                    TableRow(
                      children: [
                        _timeCell(hour),
                        for (int day = 1; day <= 7; day++)
                          _examCell(scheduleTable[day]?[hour]),
                      ],
                    ),
                ],
              ),
            ),
          ),
          ),
      ),
    );


                  },
                ),
    );
  }

  Widget _headerCell(String text) => Container(
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );

  Widget _timeCell(int hour) {
    final start = TimeOfDay(hour: hour, minute: 0);
    final end = TimeOfDay(hour: hour + 1, minute: 0);
    return Container(
      padding: const EdgeInsets.all(6),
      color: Colors.grey[200],
      child: Text(
        "${start.format(context)} – ${end.format(context)}",
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _examCell(String? content) => Container(
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minHeight: 50),
        child: content == null || content.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content.split("\n\n").map((entry) {
                  final parts = entry.split("\n");
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(parts[0],
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      if (parts.length > 1)
                        Text(parts[1],
                            style: const TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic)),
                      const SizedBox(height: 6),
                    ],
                  );
                }).toList(),
              ),
      );
}
