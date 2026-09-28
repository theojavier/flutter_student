import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_week_view/flutter_week_view.dart';
import '../../helpers/SecureStorageHelper.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  // Shared theme palette (same as ProfilePage / LoginPage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final DateFormat timeFormat = DateFormat("h:mm a");

  // Created once (not inside the StreamBuilder) so they aren't recreated
  // on every snapshot, and disposed properly.
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

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
    final storedProgram = await SecureStorageHelper.read('program');
    final storedYearBlock = await SecureStorageHelper.read('yearBlock');
    if (!mounted) return;
    setState(() {
      program = storedProgram;
      yearBlock = storedYearBlock;
      loadingUser = false;
    });
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: loadingUser
          ? const Center(
              child: CircularProgressIndicator(color: _accentColor),
            )
          : (program == null || yearBlock == null)
              ? const Center(
                  child: Text(
                    "No program/yearBlock found",
                    style: TextStyle(color: _textColor),
                  ),
                )
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTitleBar(),
                        const SizedBox(height: 16),
                        Expanded(child: _buildScheduleCard()),
                      ],
                    ),
                  ),
                ),
    );
  }

  // Floating title bar — same construction as the Profile page
  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
         Container(
  padding: const EdgeInsets.all(3), // border thickness
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(15),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        const Color(0xFF3D8BFF).withOpacity(0.9),
        const Color(0xFF3D8BFF).withOpacity(0.25),
      ],
    ),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF3D8BFF).withOpacity(0.35),
        blurRadius: 14,
        spreadRadius: 1,
      ),
    ],
  ),
  child: ClipRRect(
    borderRadius: BorderRadius.circular(12), // outer radius minus padding
    child: Container(
      color: const Color(0xFF0F3B61),
      padding: const EdgeInsets.all(10),
      child: const Icon(Icons.calendar_month_outlined,
          color: Colors.white, size: 22),
    ),
  ),
),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Schedule",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${program!} • ${yearBlock!}".toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Calendar card with the week view inside
  Widget _buildScheduleCard() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(17),
        child: StreamBuilder<QuerySnapshot>(
          stream: firestore
              .collection("exams")
              .where("program", isEqualTo: program)
              .where("yearBlock", isEqualTo: yearBlock)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _accentColor),
              );
            }

            final events = <FlutterWeekViewEvent>[];
            final now = DateTime.now();
            final monday = now.subtract(Duration(days: now.weekday - 1));
            final weekStart = DateTime(monday.year, monday.month, monday.day);
            final weekEnd = weekStart.add(const Duration(days: 7));

            if (snapshot.hasData) {
              for (var doc in snapshot.data!.docs) {
                final start = (doc["startTime"] as Timestamp).toDate();
                final end = (doc["endTime"] as Timestamp).toDate();
                final subject = doc["subject"];

                if (start.isAfter(weekStart) && start.isBefore(weekEnd)) {
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

            return ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor:
                    WidgetStateProperty.all(_accentColor.withOpacity(0.7)),
                radius: const Radius.circular(8),
              ),
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
                            (i) => weekStart.add(Duration(days: i)),
                          ),
                          events: events,
                          minimumTime: const TimeOfDay(hour: 6, minute: 57),
                          maximumTime: const TimeOfDay(hour: 19, minute: 18),
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

                          // Day columns: dark, today gets a soft blue tint
                          dayViewStyleBuilder: (date) => DayViewStyle(
                            backgroundColor: _isToday(date)
                                ? Color.alphaBlend(
                                    _accentColor.withOpacity(0.10),
                                    _bgColor,
                                  )
                                : _bgColor,
                            backgroundRulesColor:
                                Colors.white.withOpacity(0.06),
                            currentTimeRuleColor: Colors.grey.withOpacity(0.0),
                            currentTimeCircleColor:
                                Colors.grey.withOpacity(0.0),
                          ),

                          // Day header bar
                          dayBarStyleBuilder: (date) => DayBarStyle(
                            color: _headerColor,
                            textStyle: TextStyle(
                              color: _isToday(date) ? _accentColor : _textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            dateFormatter: (year, month, day) =>
                                DateFormat("EEE d").format(date),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [_headerColorLight, _headerColor],
                              ),
                              border: Border(
                                bottom: BorderSide(
                                  color: _isToday(date)
                                      ? _accentColor
                                      : Colors.white.withOpacity(0.08),
                                  width: _isToday(date) ? 2 : 1,
                                ),
                              ),
                            ),
                          ),

                          // Hour column on the left
                          hourColumnStyle: HourColumnStyle(
                            textStyle: const TextStyle(
                              color: _mutedTextColor,
                              fontSize: 12,
                            ),
                            decoration: BoxDecoration(
                              color: _headerColor,
                              border: Border(
                                right: BorderSide(
                                  color: Colors.white.withOpacity(0.08),
                                  width: 1,
                                ),
                              ),
                            ),
                            timeFormatter: (time) {
                              final hour =
                                  time.hour > 12 ? time.hour - 12 : time.hour;
                              final period = time.hour >= 12 ? 'PM' : 'AM';
                              return '$hour $period'; // "7 AM", "8 AM", etc.
                            },
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
    );
  }
}