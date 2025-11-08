import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:usb_serial/usb_serial.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// =======================================================
// ===============  ARDUINO COMMUNICATION  ===============
// =======================================================
class ArduinoSerial {
  UsbPort? _port;
  bool _connected = false;

  Future<bool> connect() async {
    try {
      final devices = await UsbSerial.listDevices();
      if (devices.isEmpty) {
        print("⚠️ No Arduino devices found");
        return false;
      }

      final device = devices.first;
      _port = await device.create();
      if (!await _port!.open()) return false;

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        9600,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _connected = true;
      print("✅ Arduino connected");
      return true;
    } catch (e) {
      print("⚠️ Arduino connection failed: $e");
      return false;
    }
  }

  Future<void> send(String message) async {
    if (!_connected || _port == null) return;
    final data = Uint8List.fromList((message + "\n").codeUnits);
    await _port!.write(data);
    print("📤 Sent to Arduino: $message");
  }

  Future<void> disconnect() async {
    await _port?.close();
    _connected = false;
    print("🔌 Disconnected");
  }

  bool get isConnected => _connected;
}
// =======================================================
// ================= STRIKE / CHEATING ===================
// =======================================================
class StrikeSystem {
  int strikes = 0;
  bool blocked = false;
  DateTime _lastStrikeTime = DateTime.now();

  final int maxStrikes;
  final Duration cooldown;

  StrikeSystem({this.maxStrikes = 3, this.cooldown = const Duration(milliseconds: 1200)});

  bool registerStrike() {
    final now = DateTime.now();
    if (now.difference(_lastStrikeTime) < cooldown) return false;
    _lastStrikeTime = now;

    strikes++;
    print("🚨 Strike registered ($strikes/$maxStrikes)");

    if (strikes >= maxStrikes) {
      blocked = true;
      print("❌ User blocked — Too many strikes");
    }
    return true;
  }

  void reset() {
    strikes = 0;
    blocked = false;
    print("🔄 Strike system reset");
  }
}

// =======================================================
// =============== FACE DETECTION LOGIC ==================
// =======================================================
class FaceTracker {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  bool verified = false;
  DateTime _lastChange = DateTime.now();
  final int stableMs;
  final StrikeSystem strikes;
  final ArduinoSerial? arduino;

  FaceTracker({
    required this.strikes,
    this.arduino,
    this.stableMs = 300,
  });

  /// Analyze each camera frame
  Future<void> process(InputImage image) async {
    final faces = await _detector.processImage(image);
    if (faces.isEmpty) {
      _setVerified(false, "Face not found");
      strikes.registerStrike();
      await arduino?.send("STRIKE");
      return;
    }

    // One face found — consider verified
    _setVerified(true, "Face centered");
    await arduino?.send("OK");
  }

  void _setVerified(bool ok, String reason) {
    final now = DateTime.now();
    if (ok != verified && now.difference(_lastChange).inMilliseconds < stableMs) return;

    verified = ok;
    _lastChange = now;
    print(ok ? "✅ $reason" : "⚠️ $reason");
  }

  void dispose() => _detector.close();
}

// =======================================================
// ================== GAZE DETECTION =====================
// =======================================================
class GazeTracker {
  final double sensitivity;
  final StrikeSystem strikes;
  final ArduinoSerial? arduino;

  GazeTracker({
    required this.strikes,
    this.arduino,
    this.sensitivity = 10.4,
  });

  // Simulated check: if eyes leave safe zone → strike
  Future<void> checkGaze({required bool isLookingAway}) async {
    if (isLookingAway) {
      print("⚠️ Looking away detected");
      strikes.registerStrike();
      await arduino?.send("STRIKE");
    } else {
      await arduino?.send("OK");
    }
  }
}


