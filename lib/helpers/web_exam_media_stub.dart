Future<Object> requestFullScreenShare() async =>
    throw UnsupportedError('Screen sharing is only available on web.');

void stopStream(Object? stream) {}

void handOffExamStreams({
  Object? screen,
  Object? camera,
  required bool isPc,
}) {}

void clearExamHandOff() {}

void clearStaleExamStorage() {}
