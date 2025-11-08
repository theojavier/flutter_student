import 'dart:async';
import 'dart:html' as html;

StreamSubscription<html.Event>? setupWebLifecycleHandlers({
  required bool examFinished,
  required void Function() onCheatingDetected,
  required void Function(String) showWarning,
}) {
  final visibilitySub = html.document.onVisibilityChange.listen((_) {
    if ((html.document.hidden ?? false) && !examFinished) {
      onCheatingDetected();
    }
  });

  html.window.onBeforeUnload.listen((event) {
    if (!examFinished) onCheatingDetected();
    (event as dynamic).returnValue = '';
  });

  html.window.history.pushState(null, "Exam", html.window.location.href);
  html.window.onPopState.listen((event) {
    if (!examFinished) {
      showWarning("Back/Forward navigation is disabled during the exam");
      html.window.history.pushState(null, "Exam", html.window.location.href);
    }
  });

  return visibilitySub;
}
