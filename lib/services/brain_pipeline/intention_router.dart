// intention_router.dart
// Sprint 2 — 宣告/確認/行動閉環的狀態機路由器
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// IntentionRouter 是 chat_controller 內的純邏輯層。
// 它不直接操作 UI，只負責：
// 1. 偵測使用者訊息中的「宣告」觸發詞 → 產生 declareIntention move
// 2. 偵測「確認」觸發詞 → 把 open IntentionRecord → confirmed
// 3. 偵測「完成」觸發詞 → 把 confirmed IntentionRecord → acted
// 4. 透過 BrainContainer 介面寫入記錄
//
// 設計原則：
// - 純函式，不持有 UI 狀態
// - InMemory 保存 open/confirmed intentions（session 內有效）
// - BrainContainer 寫入是 async fire-and-forget（不阻塞聊天）
// - 觸發詞清單可擴充

import '../../models/intention_record.dart';
import '../../models/transurfing_brain.dart';
import '../brain_pipeline/brain_container.dart';
import '../brain_pipeline/text_utils.dart';

/// 宣告觸發詞：使用者訊息含這些詞時，route 成 declareIntention
const _declareTriggers = [
  '宣告',
  '我要做',
  '我打算',
  '從今天起',
  '從現在起',
  '我決定',
  '我承諾',
  '我立志',
  '定目標',
];

/// 確認觸發詞：把 open intention 推到 confirmed
const _confirmTriggers = [
  '確認',
  '對',
  '就是',
  '去吧',
  '沒問題',
  '好',
  '好的',
  'ok',
  '可以',
  '沒錯',
  '同意',
  '開始吧',
];

/// 完成/行動觸發詞：把 confirmed intention 推到 acted
const _actTriggers = [
  '做完',
  '已執行',
  '完成',
  '搞定了',
  '做完了',
  '已完成',
  '已執行',
  'done',
  'finished',
];

/// IntentionRouter 的處理結果。
///
/// chat_controller 拿到這個結果後，可以決定要不要覆寫 recommendedMove、
/// 更新 BrainReflectionStore、或顯示 UI 提示。
class IntentionRouterResult {
  /// 路由後的最終 move（可能與 pipeline 原始結果不同）
  final RecommendedMove move;

  /// 如果建立了新 intention，這是它的 ID
  final String? newIntentionId;

  /// 如果確認/完成了某條 intention，這是它的 ID
  final String? affectedIntentionId;

  /// 給 UI 顯示的摘要文字
  final String? statusMessage;

  const IntentionRouterResult({
    required this.move,
    this.newIntentionId,
    this.affectedIntentionId,
    this.statusMessage,
  });
}

/// 宣告/確認/行動閉環路由器。
///
/// 在 chat_controller 的 sendMessage 流程中，pipeline 跑完之後呼叫。
/// 它會根據使用者訊息和當前 intention 狀態，決定是否覆寫 move 或推進狀態機。
class IntentionRouter {
  final BrainContainer _container;

  /// 當前 session 內的 intentions（InMemory，不跨 session）
  final List<IntentionRecord> _intentions = [];

  IntentionRouter(this._container);

  /// 目前所有 intentions（供 Panel 顯示）
  List<IntentionRecord> get intentions => List.unmodifiable(_intentions);

  /// 開放中的 intentions（status == open）
  List<IntentionRecord> get openIntentions =>
      _intentions.where((i) => i.isOpen).toList();

  /// 今日已行動的 intentions
  List<IntentionRecord> get todayActions {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return _intentions
        .where((i) => i.isActed && i.updatedAtMs >= todayStart)
        .toList();
  }

  /// 處理一輪使用者訊息。
  ///
  /// [message] 是使用者的原始訊息。
  /// [pipelineMove] 是 pipeline 跑出來的原始 recommendedMove。
  /// [contextSnapshot] 是當時的上下文快照（可選）。
  ///
  /// 回傳 [IntentionRouterResult]，chat_controller 用它決定後續動作。
  Future<IntentionRouterResult> handleMove({
    required String message,
    required RecommendedMove pipelineMove,
    String? contextSnapshot,
  }) async {
    final text = normalize(message);

    // 1. 偵測宣告觸發詞 → 建立 IntentionRecord
    if (containsAny(text, _declareTriggers)) {
      final intention = IntentionRecord.create(
        userMessage: message,
        contextSnapshot: contextSnapshot,
      );
      _intentions.add(intention);

      // fire-and-forget 寫入 BrainContainer
      _container.recordIntention(
        userMessage: message,
        contextSnapshot: contextSnapshot,
      );

      return IntentionRouterResult(
        move: RecommendedMove.declareIntention,
        newIntentionId: intention.id,
        statusMessage: '已記錄宣告，等待確認',
      );
    }

    // 2. 偵測確認觸發詞 → 把最近的 open intention → confirmed
    if (containsAny(text, _confirmTriggers)) {
      final openOnes = _intentions.where((i) => i.isOpen).toList();
      if (openOnes.isNotEmpty) {
        final target = openOnes.last;
        final confirmed = target.confirm(message);
        final idx = _intentions.indexOf(target);
        _intentions[idx] = confirmed;

        _container.recordConfirmation(
          intentionId: target.id,
          userReply: message,
        );

        return IntentionRouterResult(
          move: pipelineMove,
          affectedIntentionId: target.id,
          statusMessage: '已確認：${target.userMessage}',
        );
      }
    }

    // 3. 偵測完成觸發詞 → 把最近的 confirmed intention → acted
    if (containsAny(text, _actTriggers)) {
      final confirmedOnes = _intentions.where((i) => i.isConfirmed).toList();
      if (confirmedOnes.isNotEmpty) {
        final target = confirmedOnes.last;
        final acted = target.markActed(message);
        final idx = _intentions.indexOf(target);
        _intentions[idx] = acted;

        _container.recordAction(
          intentionId: target.id,
          actionSummary: message,
        );

        return IntentionRouterResult(
          move: RecommendedMove.recordWaterAction,
          affectedIntentionId: target.id,
          statusMessage: '已記錄行動：${target.userMessage}',
        );
      }
    }

    // 4. 沒命中任何觸發詞 → 回傳原始 move
    return IntentionRouterResult(move: pipelineMove);
  }

  /// 清除所有 intentions（供測試或重置用）
  void clear() {
    _intentions.clear();
  }
}
