// cheat_detector_stub.dart
class CheatDetector {
  final Function()? onStrike;
  final Function()? onReset;

  CheatDetector({this.onStrike, this.onReset});

  Future<void> start() async {}
  Future<void> stop() async {}
  void send(String message) {}
}
