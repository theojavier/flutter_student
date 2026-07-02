import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';

class CheatDetector {
  final Function()? onStrike;
  final Function()? onReset;

  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  bool _enabled = false;

  CheatDetector({this.onStrike, this.onReset});

  Future<void> start() async {
    _enabled = true;

    final devices = await UsbSerial.listDevices();
    if (devices.isEmpty) return;

    final device = devices.first;
    _port = await device.create();
    if (_port == null || !await _port!.open()) return;

    await _port!.setPortParameters(9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _subscription = _port!.inputStream?.listen((data) {
      if (!_enabled) return;
      final msg = String.fromCharCodes(data).trim();
      if (msg == "STRIKE") onStrike?.call();
      if (msg == "OK") onReset?.call();
    });

    print("CheatDetector started (Native)");
  }

  Future<void> stop() async {
    _enabled = false;
    await _subscription?.cancel();
    await _port?.close();
    print("CheatDetector stopped (Native)");
  }

  Future<void> send(String message) async {
    if (_port == null) return;
    await _port!.write(Uint8List.fromList("$message\n".codeUnits));
    print("Sent to Arduino: $message");
  }
}
