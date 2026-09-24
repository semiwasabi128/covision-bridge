// brain_container.dart
// Sprint 0 — 大腦容器的管線介面 + BrainContainerService adapter
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// CEO 修正 1（checkpoint）：不建 InMemoryBrainContainer。
// BrainContainerService（1A 產出）已存在，這裡用 adapter pattern 包裝它。
// Sprint 2 的 IntentionRecord 透過此介面寫入大腦容器。
//
// 介面只暴露管線需要的方法；BrainContainerService 的完整 API 不洩漏給管線。

import '../brain_container/brain_container_service.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';

/// 管線專用的大腦容器介面。
///
/// 這是七層管線與大腦容器之間的合約。
/// 實作可以是 [BrainContainerServiceAdapter]（包裝 1A 的 BrainContainerService），
/// 未來也可以是測試用的 mock。
abstract class BrainContainer {
  /// 記錄一條宣告（Sprint 2 的 IntentionRecord）。
  Future<void> recordIntention({
    required String userMessage,
    String? contextSnapshot,
  });

  /// 記錄使用者確認了某條宣告。
  Future<void> recordConfirmation({
    required String intentionId,
    String? userReply,
  });

  /// 記錄某條宣告已付諸行動。
  Future<void> recordAction({
    required String intentionId,
    String? actionSummary,
  });

  /// 搜尋近期相關記憶（供 Sprint 2 的 ActionRouterAI 使用）。
  Future<List<String>> searchRecent({
    required String query,
    int limit = 5,
  });
}

/// 用 [BrainContainerService]（1A 產出）實作 [BrainContainer] 介面。
///
/// 1A 的大腦容器已有 writeMemory / retrieveMemories，
/// 這裡把它們映射到管線需要的語意化方法。
///
/// Sprint 2 會在 IntentionRouter 裡呼叫這些方法；
/// Sprint 0 只需要介面存在、可編譯。
class BrainContainerServiceAdapter implements BrainContainer {
  final BrainContainerService _service;

  /// 預設使用全域 singleton；測試可注入 mock。
  BrainContainerServiceAdapter([BrainContainerService? service])
      : _service = service ?? BrainContainerService.instance;

  @override
  Future<void> recordIntention({
    required String userMessage,
    String? contextSnapshot,
  }) async {
    final content = contextSnapshot != null
        ? '$userMessage (context: $contextSnapshot)'
        : userMessage;
    await _service.writeMemory(
      content: content,
      agent: 'pipeline',
      tags: const ['intention', 'brain-pipeline'],
      speaker: MemorySpeaker.user, // [出處戳] 意圖記錄源自使用者訊息
    );
  }

  @override
  Future<void> recordConfirmation({
    required String intentionId,
    String? userReply,
  }) async {
    await _service.writeMemory(
      content: 'Confirmed intention: $intentionId'
          '${userReply != null ? ' — $userReply' : ''}',
      agent: 'pipeline',
      tags: const ['confirmation', 'brain-pipeline'],
    );
  }

  @override
  Future<void> recordAction({
    required String intentionId,
    String? actionSummary,
  }) async {
    await _service.writeMemory(
      content: 'Action for intention: $intentionId'
          '${actionSummary != null ? ' — $actionSummary' : ''}',
      agent: 'pipeline',
      tags: const ['action', 'brain-pipeline'],
    );
  }

  @override
  Future<List<String>> searchRecent({
    required String query,
    int limit = 5,
  }) async {
    final results = await _service.retrieveMemories(
      query: query,
      limit: limit,
    );
    return results.map((r) => r.content).toList();
  }
}
