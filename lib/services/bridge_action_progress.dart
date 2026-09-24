import '../models/bridge_action.dart';

/// BridgeAction 執行中可顯示給使用者的事實事件。
///
/// 不用來傳 LLM 中間輸出。每個 stage 都必須有對應的真實執行邊界。
enum BridgeActionProgressStage {
  adapterSelected,
  requestAboutToSend,
  responseReceived,
  mediaPersisted,
}

class BridgeActionProgressEvent {
  final BridgeActionType actionType;
  final BridgeActionProgressStage stage;
  final DateTime occurredAt;
  final String? provider;
  final String? model;
  final String? prompt;

  const BridgeActionProgressEvent({
    required this.actionType,
    required this.stage,
    required this.occurredAt,
    this.provider,
    this.model,
    this.prompt,
  });

  /// 只有圖片生成才有 P0.5b 的 UI 文案；其他 action 暫時不顯示。
  String get userLabel {
    switch (stage) {
      case BridgeActionProgressStage.adapterSelected:
        return provider == null ? '已選定圖片服務' : '已選定圖片服務：$provider';
      case BridgeActionProgressStage.requestAboutToSend:
        return provider == null ? '正在送出圖片請求' : '正在送出至 $provider';
      case BridgeActionProgressStage.responseReceived:
        return provider == null ? '已收到圖片服務回應' : '已收到 $provider 回應';
      case BridgeActionProgressStage.mediaPersisted:
        return '圖片已保存，準備顯示於對話';
    }
  }
}
