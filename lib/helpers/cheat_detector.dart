//cheat_detector
import 'package:flutter/foundation.dart';
import 'cheat_detector_web.dart';

// Conditional import: use Web handler for web, USB handler for others
import 'cheat_detector_usb.dart'
    if (dart.library.html) 'cheat_detector_web.dart';

class CheatDetector {
  final Function()? onStrike;
  final Function()? onReset;

  dynamic _handler;
  bool _enabled = false;

  CheatDetector({this.onStrike, this.onReset});

  /// Starts the cheat detection system
  Future<void> start() async {
    _enabled = true;

    if (kIsWeb) {
      _handler = CheatDetectorWeb();
      _handler.start(onStrike: onStrike, onReset: onReset);
    } else {
      _handler = CheatDetectorUSB();
      await _handler.start(onStrike: onStrike, onReset: onReset);
    }

    print("CheatDetector started on ${kIsWeb ? 'Web' : 'Native'}");
  }

  /// Stops the cheat detection system
  Future<void> stop() async {
    _enabled = false;
    await _handler?.stop();
    print("CheatDetector stopped");
  }

  /// Sends a message to Arduino (optional)
  void send(String message) {
    if (_enabled && _handler != null && _handler.send != null) {
      _handler.send(message);
    }
  }
}
