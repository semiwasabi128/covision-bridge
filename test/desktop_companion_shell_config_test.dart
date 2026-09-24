import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shell service builds desktop capability plan', () {
    final plan = const DesktopCompanionShellService().buildPlan();

    expect(plan.config.runtimeChannel, 'bridge.runtime.v1');
    expect(
      plan.capabilities.map((item) => item.id),
      contains('runtime-channel'),
    );
    expect(plan.capabilities.map((item) => item.id), contains('always-on-top'));
    expect(plan.simulatedCount, 3);
    expect(plan.nativeRequiredCount, 3);
    expect(plan.toJson()['summary']['capabilities'], plan.capabilities.length);
  });

  test('shell config copyWith updates only selected fields', () {
    final config = const DesktopCompanionShellConfig().copyWith(
      alwaysOnTop: false,
      width: 260,
    );

    expect(config.alwaysOnTop, isFalse);
    expect(config.width, 260);
    expect(config.trayEnabled, isTrue);
    expect(config.runtimeChannel, 'bridge.runtime.v1');
  });

  test('shell config restores from json with safe fallbacks', () {
    final config = DesktopCompanionShellConfig.fromJson({
      'alwaysOnTop': false,
      'trayEnabled': false,
      'width': 252,
      'height': 'bad',
    });

    expect(config.alwaysOnTop, isFalse);
    expect(config.trayEnabled, isFalse);
    expect(config.width, 252);
    expect(config.height, 286);
    expect(config.draggable, isTrue);
  });
}
