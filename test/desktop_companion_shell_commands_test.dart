import 'package:bridge_app/services/desktop_companion_shell_commands.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('command service builds shell startup queue from plan', () {
    final plan = const DesktopCompanionShellService().buildPlan();
    final queue = const DesktopShellCommandService().buildQueue(plan);

    expect(queue.commands.map((item) => item.id), [
      'runtime.subscribe',
      'window.shape',
      'window.drag-anchor',
      'window.wander-loop',
      'window.always-on-top',
      'tray.install',
      'login-item.configure',
    ]);
    expect(queue.nativeRequiredCount, 2);
    expect(queue.toJson()['summary']['commands'], queue.commands.length);
  });

  test('mock adapter marks runtime applied and native commands pending', () {
    final plan = const DesktopCompanionShellService().buildPlan();
    final queue = const DesktopShellCommandService().buildQueue(plan);
    final results = const DesktopShellMockCommandAdapter().dryRun(queue);

    expect(results.first.status, DesktopShellCommandStatus.applied);
    expect(
      results
          .where(
            (item) => item.status == DesktopShellCommandStatus.requiresNative,
          )
          .map((item) => item.command.id),
      ['window.always-on-top', 'tray.install'],
    );
    expect(
      results
          .where((item) => item.status == DesktopShellCommandStatus.simulated)
          .length,
      4,
    );
  });
}
