import 'package:bridge_app/services/desktop_companion_shell_commands.dart';
import 'package:bridge_app/services/desktop_companion_shell_config.dart';
import 'package:bridge_app/services/macos_desktop_shell_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MacosDesktopShellChannel.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'inspect returns connected response from native method channel',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'inspect');
            return {
              'connected': true,
              'platform': 'macos',
              'message': 'ready',
              'lastCommandCount': 3,
              'nativePanelAvailable': true,
            };
          });

      final connection = await const MacosDesktopShellChannel().inspect();

      expect(connection.connected, isTrue);
      expect(connection.platform, 'macos');
      expect(connection.message, 'ready');
      expect(connection.lastCommandCount, 3);
      expect(connection.nativePanelAvailable, isTrue);
    },
  );

  test(
    'inspect safely falls back when native method channel is absent',
    () async {
      final connection = await const MacosDesktopShellChannel().inspect();

      expect(connection.connected, isFalse);
      expect(connection.platform, 'macos');
    },
  );

  test('apply sends shell command queue to native method channel', () async {
    final plan = const DesktopCompanionShellService().buildPlan();
    final queue = const DesktopShellCommandService().buildQueue(plan);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'applyCommands');
          final payload = call.arguments as Map<Object?, Object?>;
          expect(payload['commands'], isA<List<Object?>>());
          return [
            {'id': 'runtime.subscribe', 'status': 'applied'},
          ];
        });

    final results = await const MacosDesktopShellChannel().apply(queue);

    expect(results, [
      {'id': 'runtime.subscribe', 'status': 'applied'},
    ]);
  });

  test('lastResults reads latest native command results', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'lastResults');
          return [
            {'id': 'window.shape', 'status': 'accepted'},
          ];
        });

    final results = await const MacosDesktopShellChannel().lastResults();

    expect(results, [
      {'id': 'window.shape', 'status': 'accepted'},
    ]);
  });

  test('snapshot parses native shell state safely', () {
    final snapshot = MacosDesktopShellSnapshot.fromJson({
      'transparent': true,
      'visible': false,
      'paused': true,
      'frameless': true,
      'alwaysOnTop': true,
      'draggable': true,
      'trayEnabled': true,
      'launchAtLogin': false,
      'runtimeSynced': true,
      'companionName': '星槌',
      'companionRole': '自由侍機',
      'statusText': '正在分析',
      'width': 260,
      'height': 320,
      'commandCount': 7,
      'lastAction': 'installStatusItem',
    });

    expect(snapshot.alwaysOnTop, isTrue);
    expect(snapshot.visible, isFalse);
    expect(snapshot.paused, isTrue);
    expect(snapshot.trayEnabled, isTrue);
    expect(snapshot.runtimeSynced, isTrue);
    expect(snapshot.width, 260);
    expect(snapshot.height, 320);
    expect(snapshot.commandCount, 7);
    expect(snapshot.lastAction, 'installStatusItem');
    expect(snapshot.companionName, '星槌');
    expect(snapshot.companionRole, '自由侍機');
    expect(snapshot.statusText, '正在分析');
  });

  test('snapshot uses fallbacks for partial native state', () {
    final snapshot = MacosDesktopShellSnapshot.fromJson({
      'width': 'bad',
      'lastAction': 'configureDragAnchor',
    });

    expect(snapshot.transparent, isTrue);
    expect(snapshot.alwaysOnTop, isFalse);
    expect(snapshot.width, 228);
    expect(snapshot.height, 286);
    expect(snapshot.lastAction, 'configureDragAnchor');
  });

  test('snapshot reads native shell state from method channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'snapshot');
          return {
            'alwaysOnTop': true,
            'width': 244,
            'height': 300,
            'commandCount': 4,
            'lastAction': 'configureAlwaysOnTop',
          };
        });

    final snapshot = await const MacosDesktopShellChannel().snapshot();

    expect(snapshot, isNotNull);
    expect(snapshot!.alwaysOnTop, isTrue);
    expect(snapshot.width, 244);
    expect(snapshot.commandCount, 4);
  });

  test('syncRuntime sends companion runtime payload to native shell', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'syncRuntime');
          final payload = call.arguments as Map<Object?, Object?>;
          expect(payload['schema'], 'bridge.companion.runtime.v1');
          return {
            'runtimeSynced': true,
            'companionName': '星槌',
            'statusText': '自由待機',
            'lastAction': 'syncRuntime',
          };
        });

    final snapshot = await const MacosDesktopShellChannel().syncRuntime({
      'schema': 'bridge.companion.runtime.v1',
      'runtime': {'activeCompanionName': '星槌'},
    });

    expect(snapshot, isNotNull);
    expect(snapshot!.runtimeSynced, isTrue);
    expect(snapshot.companionName, '星槌');
    expect(snapshot.lastAction, 'syncRuntime');
  });

  test('lifecycle sends native shell lifecycle action', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'lifecycle');
          final payload = call.arguments as Map<Object?, Object?>;
          expect(payload['action'], 'hide');
          return {
            'visible': false,
            'paused': false,
            'lastAction': 'hideWindow',
          };
        });

    final snapshot = await const MacosDesktopShellChannel().lifecycle('hide');

    expect(snapshot, isNotNull);
    expect(snapshot!.visible, isFalse);
    expect(snapshot.paused, isFalse);
    expect(snapshot.lastAction, 'hideWindow');
  });

  test('hardwareProfile reads native desktop hardware profile', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'hardwareProfile');
          return {
            'source': 'macos-method-channel',
            'ramGb': 32,
            'vramGb': 8,
            'chipLabel': 'Test Mac · 32GB RAM',
            'desktopConnected': true,
          };
        });

    final profile = await const MacosDesktopShellChannel().hardwareProfile();

    expect(profile, isNotNull);
    expect(profile!.source, 'macos-method-channel');
    expect(profile.ramGb, 32);
    expect(profile.vramGb, 8);
    expect(profile.chipLabel, 'Test Mac · 32GB RAM');
    expect(profile.desktopConnected, isTrue);
  });

  test(
    'hardwareProfile safely falls back when native channel is absent',
    () async {
      final profile = await const MacosDesktopShellChannel().hardwareProfile();

      expect(profile, isNull);
    },
  );

  test(
    'localRuntime sends Bridge Local Runtime action to native shell',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'localRuntime');
            final payload = call.arguments as Map<Object?, Object?>;
            expect(payload['action'], 'prepareRuntime');
            return {
              'phase': 'installed',
              'title': 'Bridge Local Runtime',
              'detail': 'ready for model download',
              'primaryActionLabel': '下載模型',
              'primaryActionEnabled': true,
            };
          });

      final state = await const MacosDesktopShellChannel().localRuntime({
        'action': 'prepareRuntime',
      });

      expect(state, isNotNull);
      expect(state!['phase'], 'installed');
      expect(state['primaryActionLabel'], '下載模型');
    },
  );
}
