import 'dart:async'; 

StreamSubscription? setupWebLifecycleHandlers({
  required bool examFinished,
  required void Function() onCheatingDetected,
  required void Function(String) showWarning,
}) {
  // No-op on non-web platforms
  return null;
}
