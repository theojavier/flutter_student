import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_week_view/flutter_week_view.dart';


class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final DateFormat timeFormat = DateFormat("h:mm a");

  String? studentId;
  String? program;
  String? yearBlock;
  bool loadingUser = true;

  @override
  void initState() {
    super.initState();
   _loadPrefs();
  }
  Future<void> _loadPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    program = prefs.getString("program");
    yearBlock = prefs.getString("yearBlock");
    loadingUser = false;
  });
}

//   Future<void> _loadStudentId() async {
//     final prefs = await SharedPreferences.getInstance();
//     final id = prefs.getString("studentId");
//     if (id == null) {
//       setState(() => loadingUser = false);
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(const SnackBar(content: Text("No student session found")));
//       return;
//     }
//     setState(() => studentId = id);
//     _loadStudentData(id);
//   }

//   Future<void> _loadStudentData(String studentId) async {
//   try {
//     final query = await firestore
//         .collection("users")
//         .where("studentId", isEqualTo: studentId)
//         .limit(1)
//         .get();

//     if (query.docs.isNotEmpty) {
//       final userDoc = query.docs.first;
//       setState(() {
//         program = userDoc["program"] ?? '';
//         yearBlock = userDoc["yearBlock"] ?? '';
//         loadingUser = false;
//       });

//       // Log to browser console
//       html.window.console.log(
//         "Loaded user data: program=${program ?? 'null'}, yearBlock=${yearBlock ?? 'null'}"
//       );
//     } else {
//       setState(() => loadingUser = false);
//       html.window.console.log("No user found for ID $studentId");
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text("No user found for ID $studentId")),
//       );
//     }
//   } catch (e) {
//     setState(() => loadingUser = false);
//     html.window.console.error("Error loading user: $e");
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text("Error loading user: $e")),
//     );
//   }
// }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: loadingUser
          ? const Center(child: CircularProgressIndicator())
          : (program == null || yearBlock == null)
          ? const Center(child: Text("No program/yearBlock found"))
          : SafeArea(
              child: Column(
                children: [
                  // Top title cube
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade700,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Schedule',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  // WeekView schedule
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: firestore
                          .collection("exams")
                          .where("program", isEqualTo: program)
                          .where("yearBlock", isEqualTo: yearBlock)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final events = <FlutterWeekViewEvent>[];
                        final now = DateTime.now();
                        final monday = now.subtract(
                          Duration(days: now.weekday - 1),
                        );
                        final weekStart = DateTime(
                          monday.year,
                          monday.month,
                          monday.day,
                        );
                        final weekEnd = weekStart.add(const Duration(days: 7));

                        if (snapshot.hasData) {
                          for (var doc in snapshot.data!.docs) {
                            final start = (doc["startTime"] as Timestamp)
                                .toDate();
                            final end = (doc["endTime"] as Timestamp).toDate();
                            final subject = doc["subject"];

                            if (start.isAfter(weekStart) &&
                                start.isBefore(weekEnd)) {
                              events.add(
                                FlutterWeekViewEvent(
                                  title: subject,
                                  description:
                                      "${timeFormat.format(start)} – ${timeFormat.format(end)}",
                                  start: start,
                                  end: end,
                                ),
                              );
                            }
                          }
                        }

                        final ScrollController _horizontalController =
                            ScrollController();
                        final ScrollController _verticalController =
                            ScrollController();

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1220),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.teal.shade700,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Scrollbar(
                              controller: _horizontalController,
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                controller: _horizontalController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: (185 * 7) + 60,
                                  height: (19 - 7) * 60.0, // 7AM–7PM
                                  child: SingleChildScrollView(
                                    controller: _verticalController,
                                    scrollDirection: Axis.vertical,
                                    child: AbsorbPointer(
                                      absorbing: true,
                                      child: WeekView(
                                        dates: List.generate(
                                          7,
                                          (i) =>
                                              weekStart.add(Duration(days: i)),
                                        ),
                                        events: events,

                                        minimumTime: const TimeOfDay(
                                          hour: 6,
                                          minute: 57,
                                        ),
                                        maximumTime: const TimeOfDay(
                                          hour: 19,
                                          minute: 18,
                                        ),
                                        initialTime: DateTime(
                                          now.year,
                                          now.month,
                                          now.day,
                                          7,
                                          0,
                                        ),
                                        style: const WeekViewStyle(
                                          dayViewWidth: 185,
                                          headerSize: 50,
                                        ),
                                        dayViewStyleBuilder: (date) =>
                                            DayViewStyle(
                                              currentTimeRuleColor: Colors.grey
                                                  .withOpacity(0.0),
                                              currentTimeCircleColor: Colors
                                                  .grey
                                                  .withOpacity(0.0),
                                            ),

                                        dayBarStyleBuilder: (date) {
                                          return DayBarStyle(
                                            color: Colors.teal.shade700,
                                            textStyle: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.shade700,
                                              border: const Border(
                                                bottom: BorderSide(
                                                  color: Colors.black26,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        hourColumnStyle: HourColumnStyle(
                                          textStyle: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade700,
                                            border: const Border(
                                              right: BorderSide(
                                                color: Colors.black26,
                                                width: 1,
                                              ),
                                            ),
                                          ),
                                          timeFormatter: (time) {
                                            final hour = time.hour > 12
                                                ? time.hour - 12
                                                : time.hour;
                                            final period = time.hour >= 12
                                                ? 'PM'
                                                : 'AM';
                                            return '$hour $period'; // shows "7 AM", "8 AM", etc.
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
