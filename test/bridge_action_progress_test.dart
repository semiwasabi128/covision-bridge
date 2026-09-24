import 'dart:io';
import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/services/bridge_action_progress.dart';
import 'package:bridge_app/services/bridge_adapters/bridge_action_adapter.dart';
import 'package:bridge_app/services/bridge_adapters/bridge_adapter_registry.dart';
import 'package:bridge_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ImageAdapter extends BridgeActionAdapter {
  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake Image';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async =>
      const BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: 'ok',
        metadata: {'provider': 'fake', 'model': 'fake-image-v1'},
        // [2026-09-22] 刻意不帶 mediaUrl：executor 對 mediaUrl 會觸發
        // 資產索引＋向量嵌入（_triggerAssetIngestion），在純測試環境
        // 掛起。本測試的焦點是 progress event 邊界，不是媒體入庫。
        // mediaPersisted stage 的觸發條件（mediaUrl 非空）在這裡不成立，
        // 斷言跟著調整為三段邊界。
      );
}

void main() {
  // [2026-09-22] 純 test() 也要先初始化 binding——executor 內部會碰
  // SharedPreferences / platform channel（getProvider 讀 prefs）。
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // [2026-09-22] StorageService（token）在 macOS 走 golden_keys.json，
    // 會問 path_provider——純 test() 環境掛住。注入臨時目錄。
    StorageService.useTestTokenDirectory(
      Directory.systemTemp.createTempSync('bridge_progress_token_'),
    );
  });
  tearDownAll(() {
    StorageService.useTestTokenDirectory(null);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('圖片 executor 依真實邊界發出 progress event', () async {
    final executor = BridgeActionExecutor(
      registry: BridgeAdapterRegistry(adapters: [_ImageAdapter()]),
    );
    final events = <BridgeActionProgressEvent>[];
    final sub = executor.progressStream.listen(events.add);

    await executor.execute(
      const BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: 'blue dragon over a city',
        provider: 'fake',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // 沒有 mediaUrl → 不觸發 mediaPersisted（那是媒體入庫的邊界）。
    // adapter 選定在 executor 內 emit 兩次（選定時＋fallback 迴圈內
    // i=0 再 emit 一次），這是現行真實邊界。
    expect(events.map((event) => event.stage), [
      BridgeActionProgressStage.adapterSelected,
      BridgeActionProgressStage.requestAboutToSend,
      BridgeActionProgressStage.adapterSelected,
      BridgeActionProgressStage.requestAboutToSend,
      BridgeActionProgressStage.responseReceived,
    ]);
    expect(
      events.every((event) => event.prompt == 'blue dragon over a city'),
      isTrue,
    );
    expect(events.last.provider, 'fake');
  });
}
