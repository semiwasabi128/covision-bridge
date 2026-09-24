import 'package:bridge_app/services/local_model_runtime_service.dart';
import 'package:bridge_app/services/local_model_catalog_service.dart';
import 'package:bridge_app/services/macos_desktop_shell_channel.dart';
import 'package:bridge_app/services/companion_runtime_store.dart';
import 'package:bridge_app/services/storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(MacosDesktopShellChannel.channelName);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    CompanionRuntimeStore.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('detects and saves Ollama local model runtime', () async {
    final service = LocalModelRuntimeService(
      probe: (_) async => {
        'models': [
          {'name': 'llama3.1:8b'},
          {'name': 'qwen2.5:7b'},
        ],
      },
    );

    // [2026-09-22] detectAndSave 的 endpoint 預設值已改為 Bridge 本地引擎
    // 18789（launchd 常駐 llama-server）；要驗證 Ollama 偵測需明確指定 11434。
    final profile = await service.detectAndSave(
      endpoint: 'http://127.0.0.1:11434',
    );

    expect(profile.connected, isTrue);
    expect(profile.runtimeLabel, 'Ollama');
    expect(profile.selectedModel, 'llama3.1:8b');
    expect(profile.models, contains('qwen2.5:7b'));
    expect(
      await StorageService.getLocalModelEndpoint(),
      'http://127.0.0.1:11434',
    );
    expect(await StorageService.getLocalModelName(), 'llama3.1:8b');
  });

  test('activates detected runtime as local brain provider', () async {
    final service = LocalModelRuntimeService();
    const profile = LocalModelRuntimeProfile(
      endpoint: 'http://127.0.0.1:11434',
      connected: true,
      runtimeLabel: 'Ollama',
      models: ['llama3.1:8b'],
      selectedModel: 'llama3.1:8b',
      detail: 'ready',
    );

    await service.activateAsBrain(profile);
    final runtimeState = await service.inspectBridgeRuntime();

    expect(await StorageService.getProvider(), 'local');
    expect(await StorageService.getGatewayUrl(), 'http://127.0.0.1:11434');
    expect(
      await StorageService.getToken(provider: 'local'),
      'bridge-local-runtime',
    );
    expect(await StorageService.getLocalModelName(), 'llama3.1:8b');
    expect(runtimeState.phase, BridgeLocalRuntimePhase.running);
    expect(runtimeState.running, isTrue);
  });

  test('prepares Bridge Local Runtime through desktop channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'localRuntime');
          final payload = call.arguments as Map<Object?, Object?>;
          expect(payload['action'], 'prepareRuntime');
          return {
            'phase': 'installed',
            'title': 'Bridge Local Runtime',
            'detail': 'runtime installer ready',
            'primaryActionLabel': '下載推薦模型',
            'primaryActionEnabled': true,
            'runtimePath':
                '/Users/test/Library/Application Support/Bridge/LocalRuntime',
            'expectedRuntimeExecutablePath':
                '/Users/test/Library/Application Support/Bridge/LocalRuntime/runtime/bin/llama-server',
          };
        });

    final state = await LocalModelRuntimeService().prepareBridgeRuntime();

    expect(state.phase, BridgeLocalRuntimePhase.installed);
    expect(state.installed, isTrue);
    expect(state.primaryActionLabel, '下載推薦模型');
    expect(
      state.expectedRuntimeExecutablePath,
      endsWith('runtime/bin/llama-server'),
    );
  });

  test(
    'sends recommended model download payload through desktop channel',
    () async {
      const recommendation = LocalModelRecommendation(
        model: LocalModelCatalogEntry(
          id: 'local-7b-q4',
          name: '平衡 7B 指令模型',
          sizeClass: '7B',
          quantization: 'Q4',
          minRamGb: 16,
          recommendedRamGb: 24,
          recommendedVramGb: 6,
          downloadSize: '約 4-6 GB',
          runtime: 'Bridge Local Runtime',
          sourceLabel: 'SemiDAO curated mirror',
          licenseLabel: '依模型原始授權顯示',
          manifestUrl: 'bridge://models/local-7b-q4/manifest.json',
          checksumSha256: 'pending-source-verification',
          fileName: 'local-7b-q4.gguf',
          bestFor: [LocalModelTask.quickChat],
        ),
        fit: LocalModelFit.good,
        reason: '硬體條件適合，可作為本地模型候選。',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'localRuntime');
            final payload = call.arguments as Map<Object?, Object?>;
            expect(payload['action'], 'downloadModel');
            expect(payload['fit'], 'good');
            final model = payload['model'] as Map<Object?, Object?>;
            expect(model['id'], 'local-7b-q4');
            expect(model['downloadSize'], '約 4-6 GB');
            final sourceManifest =
                model['sourceManifest'] as Map<Object?, Object?>;
            expect(sourceManifest['sourceLabel'], 'SemiDAO curated mirror');
            expect(sourceManifest['fileName'], 'local-7b-q4.gguf');
            return {
              'phase': 'downloading',
              'title': 'Bridge Local Runtime',
              'detail': 'downloading model',
              'primaryCommand': 'status',
              'primaryActionLabel': '下載中',
              'primaryActionEnabled': false,
              'progress': 0.05,
              'modelId': 'local-7b-q4',
              'taskPath': '/tmp/local-7b-q4.download.json',
              'expectedModelFilePath':
                  '/tmp/models/local-7b-q4/local-7b-q4.gguf',
            };
          });

      final state = await LocalModelRuntimeService().downloadModel(
        recommendation,
      );

      expect(state.phase, BridgeLocalRuntimePhase.downloading);
      expect(state.primaryCommand, BridgeLocalRuntimeCommand.status);
      expect(state.progress, 0.05);
      expect(state.modelId, 'local-7b-q4');
      expect(state.taskPath, endsWith('local-7b-q4.download.json'));
      expect(state.expectedModelFilePath, endsWith('local-7b-q4.gguf'));
      expect(
        CompanionRuntimeStore.instance.current.latestLocalRuntimeSignal?.phase,
        'downloading',
      );
      expect(
        CompanionRuntimeStore.instance.current.statusText,
        '我正在替你準備本地主腦 5%。',
      );
    },
  );

  test('stops Bridge Local Runtime server through desktop channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'localRuntime');
          final payload = call.arguments as Map<Object?, Object?>;
          expect(payload['action'], 'stopServer');
          return {
            'phase': 'installed',
            'title': 'Bridge Local Runtime',
            'detail': 'server stopped',
            'primaryCommand': 'startServer',
            'primaryActionLabel': '啟動本地 server',
            'primaryActionEnabled': true,
          };
        });

    final state = await LocalModelRuntimeService().stopServer();

    expect(state.phase, BridgeLocalRuntimePhase.installed);
    expect(state.primaryCommand, BridgeLocalRuntimeCommand.startServer);
    expect(state.primaryActionLabel, '啟動本地 server');
  });

  test(
    'activates Bridge Local Runtime as local brain after server starts',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'localRuntime');
            final payload = call.arguments as Map<Object?, Object?>;
            expect(payload['action'], 'startServer');
            return {
              'phase': 'running',
              'title': 'Bridge Local Runtime',
              'detail': 'server started',
              'primaryCommand': 'stopServer',
              'primaryActionLabel': '停止本地 server',
              'primaryActionEnabled': true,
              'serverUrl': 'http://127.0.0.1:18789',
              'activeModelName': '入門 0.5B 測試模型',
              'modelFilePath': '/tmp/qwen.gguf',
            };
          });

      final state = await LocalModelRuntimeService(
        healthProbe: (_) async => {
          'data': [
            {'id': '入門 0.5B 測試模型'},
          ],
        },
      ).startServer();

      expect(state.running, isTrue);
      expect(state.serverHealthy, isTrue);
      expect(state.healthDetail, contains('健康檢查通過'));
      expect(await StorageService.getProvider(), 'local');
      expect(await StorageService.getGatewayUrl(), 'http://127.0.0.1:18789');
      expect(
        await StorageService.getToken(provider: 'local'),
        'bridge-local-runtime',
      );
      expect(
        await StorageService.getLocalModelEndpoint(),
        'http://127.0.0.1:18789',
      );
      expect(await StorageService.getLocalModelName(), '入門 0.5B 測試模型');
    },
  );

  test(
    'does not activate Bridge Local Runtime when health check fails',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'localRuntime');
            final payload = call.arguments as Map<Object?, Object?>;
            expect(payload['action'], 'startServer');
            return {
              'phase': 'running',
              'title': 'Bridge Local Runtime',
              'detail': 'server process started',
              'primaryCommand': 'stopServer',
              'primaryActionLabel': '停止本地 server',
              'primaryActionEnabled': true,
              'serverUrl': 'http://127.0.0.1:18789',
              'activeModelName': '入門 0.5B 測試模型',
            };
          });

      final state = await LocalModelRuntimeService(
        healthProbe: (_) async => throw StateError('not ready'),
      ).startServer();

      expect(state.running, isTrue);
      expect(state.serverHealthy, isFalse);
      expect(state.healthDetail, contains('健康檢查失敗'));
      expect(await StorageService.getProvider(), isNull);
      expect(await StorageService.getGatewayUrl(), isNull);
      expect(await StorageService.getLocalModelName(), isNull);
    },
  );
}
