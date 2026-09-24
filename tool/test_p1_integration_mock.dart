// [小葵 P1 2026-08-08] Integration test with mock
// 測試三件事：
// 1. Gemini adapter 請求格式正確（Nano Banana Interactions API）
// 2. ProgressStream 事件序列
// 3. CapabilityRouter：指定 provider 不會跑到別家 + 沒 token 正確報錯

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/services/bridge_action_progress.dart';
import 'package:bridge_app/services/bridge_adapters/bridge_adapter_registry.dart';
import 'package:bridge_app/services/bridge_adapters/gemini_image_adapter.dart';
import 'package:bridge_app/services/capability_router.dart';

// ──────────────────────────────────────────────
// Mock Dio（用 interceptor 攔截請求）
// ──────────────────────────────────────────────

Dio createMockDio(MockResponder responder) {
  final dio = Dio();
 dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final response = responder.respond(options.path, options.data);
      handler.resolve(response);
    },
  ));
  return dio;
}

class MockResponder {
  final Response<dynamic> Function(String path, dynamic data) respond;
  final List<RequestLog> logs = [];
  MockResponder(this.respond);

  factory MockResponder.geminiNanoBanana() {
    return MockResponder((path, data) {
      if (!path.contains('/interactions')) {
        throw Exception('Expected /interactions but got $path');
      }
      return Response(
        data: {
          'output_image': {
            'data': 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ',
          },
        },
        statusCode: 200,
        requestOptions: RequestOptions(path: path),
      );
    });
  }
}

class RequestLog {
  final String path;
  final dynamic data;
  RequestLog(this.path, this.data);
}

/// 包裝 MockResponder，同時記錄所有請求
Dio createRecordingMockDio(MockResponder responder) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      responder.logs.add(RequestLog(options.path, options.data));
      final response = responder.respond(options.path, options.data);
      handler.resolve(response);
    },
  ));
  return dio;
}

// ──────────────────────────────────────────────
// Tests
// ──────────────────────────────────────────────

void main() {
  // [小葵 2026-08-08] Flutter binding 初始化——StorageService 用 SharedPreferences 需要
  TestWidgetsFlutterBinding.ensureInitialized();
  // 設定假 token 讓 adapter 通過 token 檢查
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'api_token_v2_gemini': 'test-gemini-key',
    });
  });

  group('P1: Gemini adapter (Nano Banana)', () {
    test('送出到 /interactions endpoint，不是 /models/:predict', () async {
      final responder = MockResponder.geminiNanoBanana();
      final dio = createRecordingMockDio(responder);
      final adapter = GeminiImageAdapter(dio: dio);

      // 執行可能因為 persistImageDataUrl 需要 path_provider 而失敗，
      // 但我們只關心請求格式——用 try/catch 捕獲
      try {
        await adapter.execute(
          const BridgeAction(
            type: BridgeActionType.generateImage,
            prompt: 'a cute shiba inu',
            provider: 'gemini',
          ),
        );
      } catch (_) {}

      expect(responder.logs, isNotEmpty, reason: '應該發出 HTTP 請求');
      expect(responder.logs.first.path, contains('/interactions'),
          reason: 'Nano Banana 用 Interactions API，不是 :predict');
    });

    test('request body 包含 model 和 input array', () async {
      final responder = MockResponder.geminiNanoBanana();
      final dio = createRecordingMockDio(responder);
      final adapter = GeminiImageAdapter(dio: dio);

      await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'test prompt',
          provider: 'gemini',
        ),
      );

      final data = responder.logs.first.data as Map<String, dynamic>;
      expect(data['model'], 'gemini-3.1-flash-image',
          reason: 'model 必須是 Nano Banana 2');
      expect(data['input'], isA<List>(),
          reason: 'input 必須是 array 格式');
      final input = data['input'] as List;
      expect(input.first['type'], 'text',
          reason: 'input block type 必須是 text');
      expect(input.first['text'], 'test prompt',
          reason: 'input block text 必須是使用者的 prompt');
    });

    test('不使用舊 Imagen 的 instances/parameters 格式', () async {
      final responder = MockResponder.geminiNanoBanana();
      final dio = createRecordingMockDio(responder);
      final adapter = GeminiImageAdapter(dio: dio);

      await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'test',
          provider: 'gemini',
        ),
      );

      final data = responder.logs.first.data as Map<String, dynamic>;
      expect(data.containsKey('instances'), isFalse,
          reason: 'Nano Banana 不用 instances');
      expect(data.containsKey('parameters'), isFalse,
          reason: 'Nano Banana 不用 parameters');
    });
  });

  group('P1: ProgressStream 事件', () {
    test('BridgeActionProgressEvent.userLabel 不含 raw API data', () {
      final event = BridgeActionProgressEvent(
        actionType: BridgeActionType.generateImage,
        stage: BridgeActionProgressStage.requestAboutToSend,
        occurredAt: DateTime.now(),
        provider: 'Gemini',
      );
      final label = event.userLabel;
      expect(label, contains('Gemini'));
      expect(label, isNot(contains('http')));
      expect(label, isNot(contains('api_key')));
      expect(label, isNot(contains('{')));
    });

    test('4 個 stage 的 userLabel 都有中文描述', () {
      for (final stage in BridgeActionProgressStage.values) {
        final event = BridgeActionProgressEvent(
          actionType: BridgeActionType.generateImage,
          stage: stage,
          occurredAt: DateTime.now(),
          provider: 'Test',
        );
        expect(event.userLabel, isNotEmpty,
            reason: '$stage 的 userLabel 不能是空的');
        expect(event.userLabel.length, greaterThan(3),
            reason: '$stage 的 userLabel 要有合理長度');
      }
    });

    test('事件序列：adapterSelected → requestAboutToSend → responseReceived → mediaPersisted', () {
      // 驗證 enum 順序與設計文件一致
      final stages = BridgeActionProgressStage.values;
      expect(stages[0], BridgeActionProgressStage.adapterSelected);
      expect(stages[1], BridgeActionProgressStage.requestAboutToSend);
      expect(stages[2], BridgeActionProgressStage.responseReceived);
      expect(stages[3], BridgeActionProgressStage.mediaPersisted);
    });
  });

  group('P1: CapabilityRouter 路由', () {
    test('指定 gemini → 路由到 gemini adapter', () async {
      final registry = BridgeAdapterRegistry();
      final router = CapabilityRouter(registry: registry);

      final route = await router.route(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'test',
          provider: 'gemini',
        ),
      );

      expect(route.provider, 'gemini');
      expect(route.adapter?.id, 'gemini');
    });

    test('指定 openai → 路由到 openai adapter', () async {
      final registry = BridgeAdapterRegistry();
      final router = CapabilityRouter(registry: registry);

      final route = await router.route(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'test',
          provider: 'openai',
        ),
      );

      expect(route.provider, 'openai');
      expect(route.adapter?.id, 'openai');
    });

    test('指定 gemini → 不會跑到 openai', () async {
      final registry = BridgeAdapterRegistry();
      final router = CapabilityRouter(registry: registry);

      final route = await router.route(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'test',
          provider: 'gemini',
        ),
      );

      expect(route.adapter?.id, isNot('openai'),
          reason: '指定 gemini 就不能跑到 openai');
    });

    test('沒有任何 token → reason 不是 ready 狀態', () async {
      // 不設任何 token——清空 mock
      SharedPreferences.setMockInitialValues({});

      final registry = BridgeAdapterRegistry();
      final router = CapabilityRouter(registry: registry);

      // 不指定 provider，讓它自動找
      final route = await router.route(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'test',
        ),
      );

      // 沒 token 時應該回報 provider_not_configured 或 no_adapter
      expect(
        route.reason,
        anyOf('provider_not_configured', 'no_adapter'),
        reason: '沒 token 時不能回報 ready 狀態',
      );
    });

    test('不支援的能力類型 → adapter 為 null', () async {
      final registry = BridgeAdapterRegistry();
      final router = CapabilityRouter(registry: registry);

      final route = await router.route(
        const BridgeAction(
          type: BridgeActionType.generateAnimation,
          prompt: 'test',
        ),
      );

      expect(route.adapter, isNull,
          reason: '動畫生成沒有 adapter');
    });

    test('candidateProviders 包含所有圖片 adapter', () async {
      final registry = BridgeAdapterRegistry();
      final router = CapabilityRouter(registry: registry);

      final route = await router.route(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'test',
        ),
      );

      expect(route.candidateProviders, contains('openai'));
      expect(route.candidateProviders, contains('gemini'));
      expect(route.candidateProviders, contains('minimax'));
      expect(route.candidateProviders, contains('replicate'));
    });
  });
}
