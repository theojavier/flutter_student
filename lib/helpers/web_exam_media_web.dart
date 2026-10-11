import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

Future<Object> requestFullScreenShare() async {
  final options = web.DisplayMediaStreamOptions(
    video: {'displaySurface': 'monitor'}.jsify()!,
    audio: false.toJS,
  );
  final stream = await web.window.navigator.mediaDevices
      .getDisplayMedia(options)
      .toDart;

  final tracks = stream.getVideoTracks().toDart;
  var surface = '';
  if (tracks.isNotEmpty) {
    final value = tracks.first.getSettings()['displaySurface'];
    if (value.isA<JSString>()) surface = (value as JSString).toDart;
  }

  if (tracks.isEmpty || (surface.isNotEmpty && surface != 'monitor')) {
    stopStream(stream);
    throw Exception(
      'Please choose "Entire Screen" when prompted — sharing a window or browser tab is not allowed.',
    );
  }
  return stream;
}

void stopStream(Object? stream) {
  if (stream == null) return;
  for (final track in (stream as web.MediaStream).getTracks().toDart) {
    track.stop();
  }
}

void handOffExamStreams({Object? screen, Object? camera, required bool isPc}) {
  final window = web.window as JSObject;
  window['__examIsPc'] = isPc.toJS;
  if (screen != null) window['__examScreenStream'] = screen as JSObject;
  if (camera != null) window['__examCameraStream'] = camera as JSObject;
}

void clearExamHandOff() {
  final window = web.window as JSObject;
  window['__examScreenStream'] = null;
  window['__examCameraStream'] = null;
  window['__examIsPc'] = null;
}

void clearStaleExamStorage() {
  for (final key in const [
    'examId',
    'examStarted',
    'is_unloading',
    'gazeOnlineClicks',
  ]) {
    web.window.sessionStorage.removeItem(key);
  }
  for (final key in const ['cheatingCount', 'cheatClipIndex']) {
    web.window.localStorage.removeItem(key);
  }
}
