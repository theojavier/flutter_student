import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../utils/reload_stub.dart'
    if (dart.library.js_interop) '../utils/reload_web.dart';

class AppRefresh {
  AppRefresh._();

  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
}

class PullToRefreshShell extends StatefulWidget {
  const PullToRefreshShell({
    super.key,
    required this.child,
    this.enabled = true,
    this.reloadPageOnWeb = true,
  });

  final Widget child;
  final bool enabled;
  final bool reloadPageOnWeb;

  @override
  State<PullToRefreshShell> createState() => _PullToRefreshShellState();
}

class _PullToRefreshShellState extends State<PullToRefreshShell> {
  Future<void> _onRefresh() async {
    if (kIsWeb && widget.reloadPageOnWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      hardReload();
      return;
    }
    AppRefresh.tick.value++;
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color.fromARGB(255, 24, 39, 68),
      edgeOffset: kToolbarHeight,
      notificationPredicate: (notification) => notification.depth <= 1,
      child: widget.child,
    );
  }
}
