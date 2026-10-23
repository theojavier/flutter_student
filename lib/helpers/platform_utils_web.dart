import 'dart:html' as html;

bool isPageReload() {
  final nav = html.window.performance.getEntriesByType('navigation');
  return nav.isNotEmpty &&
      (nav.first as html.PerformanceNavigationTiming).type == 'reload';
}

void setReloadingFlag(bool isReload) {
  if (isReload) {
    html.window.sessionStorage['isReloading'] = 'true';
  } else {
    html.window.sessionStorage.remove('isReloading');
  }
}

void clearReloadingFlag() => html.window.sessionStorage.remove('isReloading');

void clearStaleExamStorage() {
  for (final k in ['examStarted', 'is_unloading', 'gazeOnlineClicks']) {
    html.window.sessionStorage.remove(k);
  }
  for (final k in ['cheatingCount', 'cheatClipIndex', 'pendingCheatStill']) {
    html.window.localStorage.remove(k);
  }
}
