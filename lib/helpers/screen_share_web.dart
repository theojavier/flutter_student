import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class ScreenShare {
  static const bool supported = true;
  JSObject? _stream;
  bool handedOff = false;

  Future<void> request() async {
    final mediaDevices = web.window.navigator.mediaDevices;
    final options = {
      'video': {'displaySurface': 'monitor'},
      'audio': false,
    }.jsify();

    final promise = (mediaDevices as JSObject)
        .callMethod<JSPromise<JSObject>>('getDisplayMedia'.toJS, options);
    final stream = await promise.toDart;

    final videoTracks = stream.callMethod<JSArray>('getVideoTracks'.toJS);
    final count = (videoTracks.getProperty('length'.toJS) as JSNumber).toDartInt;
    String surface = '';
    if (count > 0) {
      final track = videoTracks.getProperty(0.toJS) as JSObject;
      final settings = track.callMethod<JSObject>('getSettings'.toJS);
      surface = (settings.getProperty('displaySurface'.toJS) as JSString?)?.toDart ?? '';
    }

    if (count == 0 || (surface.isNotEmpty && surface != 'monitor')) {
      _stopStream(stream);
      throw Exception('Please choose "Entire Screen" when prompted — sharing a window or browser tab is not allowed.');
    }
    _stream = stream;
  }

  void stop() {
    _stopStream(_stream);
    _stream = null;
  }

  void exposeToExam() {
    if (_stream != null) {
      (web.window as JSObject).setProperty('__examScreenStream'.toJS, _stream);
    }
  }

  static void _stopStream(JSObject? stream) {
    if (stream == null) return;
    try {
      final tracks = stream.callMethod<JSArray>('getTracks'.toJS);
      final len = (tracks.getProperty('length'.toJS) as JSNumber).toDartInt;
      for (var i = 0; i < len; i++) {
        (tracks.getProperty(i.toJS) as JSObject).callMethod('stop'.toJS);
      }
    } catch (e) {
      debugPrint('Failed to stop a media stream: $e');
    }
  }
}
