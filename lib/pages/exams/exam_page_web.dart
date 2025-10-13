// This file will only be used on web
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:async';

class WebLifecycleHandlers {
  StreamSubscription<html.Event>? _visibilitySub;
  StreamSubscription<html.Event>? _beforeUnloadSub;
  StreamSubscription<html.PopStateEvent>? _popStateSub;

  void setup(void Function() onCheat, bool Function() examFinished, void Function(String) showWarning) {
    // Tab visibility change
    _visibilitySub = html.document.onVisibilityChange.listen((_) {
      if ((html.document.hidden ?? false) && !examFinished()) {
        onCheat();
        showWarning("⚠️ You switched tabs. Stay focused!");
      }
    });

    // Before unload (refresh/close)
    _beforeUnloadSub = html.window.onBeforeUnload.listen((event) {
      if (!examFinished()) onCheat();
      (event as html.BeforeUnloadEvent).returnValue = ''; // Prevent silent close
    });

    // Prevent browser back/forward
    _popStateSub = html.window.onPopState.listen((event) {
      if (!examFinished()) {
        showWarning("Back/Forward navigation is disabled during the exam");
        html.window.history.pushState(null, "Exam", html.window.location.href);
      }
    });

    // Push initial state
    html.window.history.pushState(null, "Exam", html.window.location.href);
  }

  void dispose() {
    _visibilitySub?.cancel();
    _beforeUnloadSub?.cancel();
    _popStateSub?.cancel();
  }
}
