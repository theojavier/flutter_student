// This file will be used on non-web platforms (Windows, Android, iOS, macOS, Linux)

class WebLifecycleHandlers {
  void setup(void Function() onCheat, bool Function() examFinished, void Function(String) showWarning) {
    // No-op on non-web platforms
  }

  void dispose() {
    // No-op
  }
}
