// Mobile/Desktop - screen sharing not supported
class ScreenShare {
  static const bool supported = false;
  bool handedOff = false;
  
  Future<void> request() async =>
      throw UnsupportedError('Screen sharing is not supported on this platform.');
  
  void stop() {}
  void exposeToExam() {}
}
