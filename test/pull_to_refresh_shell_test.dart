import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_flutter_app/widgets/pull_to_refresh_shell.dart';

void main() {
  testWidgets('pulling at the top triggers a soft refresh', (tester) async {
    final tick = AppRefresh.tick.value;

    await tester.pumpWidget(
      MaterialApp(
        home: PullToRefreshShell(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [SizedBox(height: 1000)],
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(AppRefresh.tick.value, tick + 1);
  });
}
