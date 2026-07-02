//C:\Users\acer\OneDrive\Desktop\theo\my_flutter_app\lib\helpers\cheat_detector_web.dart
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

class CheatDetector {
  final Function()? onStrike;
  final Function()? onReset;

  StreamSubscription<html.Event>? _visListener;
  bool _enabled = false;

  CheatDetector({this.onStrike, this.onReset});

  /// If [autoConnect] is true, will try calling JS connectUSB automatically
  Future<void> start({bool autoConnect = true}) async {
    _enabled = true;

    _visListener = html.document.onVisibilityChange.listen((event) {
      if (!_enabled) return;
      if (html.document.visibilityState == 'hidden') {
        onStrike?.call();
        _sendToArduino("STRIKE");
      }
    });

    if (autoConnect) {
      try {
        js.context.callMethod('connectUSB');
      } catch (_) {
        print("Auto-connect failed: permission required or JS not loaded.");
      }
    }

    print("CheatDetector started (Web)");
  }

  Future<void> stop() async {
    _enabled = false;
    await _visListener?.cancel();
    print("CheatDetector stopped (Web)");
  }

  void send(String message) => _sendToArduino(message);

  void _sendToArduino(String message) {
    try {
      js.context.callMethod('sendToArduino', [message]);
      print("Sent to Arduino: $message");
    } catch (_) {}
  }
}
