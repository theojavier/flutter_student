//cheat_detector_usb
import 'dart:async';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';

class CheatDetectorUSB {
  UsbPort? _port;
  StreamSubscription<Uint8List>? _subscription;
  bool _enabled = false;

  Future<void> start({
    Function()? onStrike,
    Function()? onReset,
  }) async {
    _enabled = true;

    print("Checking USB devices...");
    final devices = await UsbSerial.listDevices();

    if (devices.isEmpty) {
      print("No USB devices found");
      return;
    }

    final device = devices.first;
    _port = await device.create(); 

    if (_port == null) {
      print("Failed to create USB port");
      return;
    }

    if (!await _port!.open()) {
      print("Failed to open USB port");
      return;
    }

    await _port!.setPortParameters(
      9600,
      UsbPort.DATABITS_8,
      UsbPort.STOPBITS_1,
      UsbPort.PARITY_NONE,
    );

    _subscription = _port!.inputStream?.listen((data) {
      if (!_enabled) return;

      final msg = String.fromCharCodes(data).trim();
      print("USB Data: $msg");

      if (msg == "STRIKE") onStrike?.call();
      if (msg == "OK") onReset?.call();
    });

    print("USB Cheat Detector ACTIVE!");
  }

  Future<void> stop() async {
    _enabled = false;
    await _subscription?.cancel();
    await _port?.close();
  }

  Future<void> send(String message) async {
    if (_port == null) return;
    await _port!.write(Uint8List.fromList("$message\n".codeUnits));
    print("Sent to Arduino: $message");
  }
}
