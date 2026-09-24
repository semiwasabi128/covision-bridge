// l2_embedding_stub.dart
// L2 嵌入引擎 stub——v2 擴展點，目前不實作。
// 未來可用 embedding 相似度做中等信心判斷，介於 L1 正則與 L3 LLM 之間。

import 'semantic_result.dart';

class L2EmbeddingEngine {
  /// v2 擴展點——目前永遠回傳 null。
  /// 未來實作：用 embedding 相似度比對已知門意圖，回傳中等信心結果。
  Future<DoorIntentResult?> detectDoorIntent({
    required String message,
    required List<({String role, String content})> history,
    String? activeDoorTitle,
  }) async {
    // TODO(v2): 實作 embedding 相似度匹配
    return null;
  }
}
