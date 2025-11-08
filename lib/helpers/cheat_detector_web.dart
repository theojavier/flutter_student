//cheat_detector_web
import 'dart:html';
import 'dart:js' as js;

class CheatDetectorWeb {
  bool _enabled = false;

  void start({
    Function()? onStrike,
    Function()? onReset,
  }) {
    _enabled = true;

    window.onMessage.listen((event) {
      if (!_enabled) return;

      final msg = event.data.toString().trim();
      if (msg == "STRIKE") onStrike?.call();
      if (msg == "OK") onReset?.call();
    });

    js.context.callMethod('connectUSB');
    print("Web USB listener started");
  }

  void stop() {
    _enabled = false;
  }

  void send(String message) {
    js.context.callMethod('sendToArduino', [message]);
    print("Sent to Arduino: $message");
  }
}
