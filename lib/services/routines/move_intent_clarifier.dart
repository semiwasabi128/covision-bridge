/// 🥋 招式意圖釐清 [Blue 拍板 2026-09-12]
///
/// 「讓夥伴重播確認時同時要先跳出全域對話，Agent 先問使用者問題，
///   搞清楚使用者要夥伴使用這招是希望幫做什麼？招式打完收工後要得到
///   什麼？搞清楚需求與意圖後再動手——搞不好問完才知道必須打組合招。」
///
/// 流程：
///   1. 使用者在訓練頁點「讓夥伴重播」
///   2. 本服務跳全域對話（送到當前對話），Agent 以釐清模式提問：
///      - 這招打完你想得到什麼？（目標）
///      - 有沒有這招覆蓋不到的部分？（邊界）
///      - 需不需要接其他招式？（組合）
///   3. 使用者回答 → Agent 判斷：單招 / 組合招 / 需重錄
///   4. 確認後才使出（use_move / 依序 use_move）

import 'package:flutter/foundation.dart';
import 'package:bridge_app/services/routines/system_routine_store.dart';

class MoveIntentClarifier {
  MoveIntentClarifier._();
  static final MoveIntentClarifier instance = MoveIntentClarifier._();

  /// 送到全域對話的回調——由 chat 層掛上（service 不反向依賴 UI）
  /// (message) → 送出至當前對話並觸發 Agent 回應
  static void Function(String message)? onSendToGlobalChat;

  /// 開始釐清——跳全域對話，Agent 接手提問
  ///
  /// [moveName] 使用者點的招式
  /// 回傳 true=已成功送進對話
  Future<bool> clarify({
    required SavedRoutine move,
    String? userHint,
  }) async {
    if (onSendToGlobalChat == null) {
      debugPrint('[MoveIntentClarifier] 沒有掛 onSendToGlobalChat——直接回 false');
      return false;
    }
    final msg = StringBuffer();
    msg.write('我想讓夥伴使出招式「${move.name}」（${move.stepCount} 步）。\n');
    if (userHint != null && userHint.isNotEmpty) {
      msg.write('我的目的：$userHint\n');
    }
    msg.write('\n請先別急著執行——用下面的問題搞清楚我的需求與意圖：\n'
        '1. 這招打完收工，我希望得到什麼？（確認目標）\n'
        '2. 這招的 ${move.stepCount} 步有沒有覆蓋不到我需求的部分？\n'
        '3. 需不需要組合其他招式才能滿足我的最終目標？\n'
        '搞清楚之後，跟我確認執行計畫（單招或組合招），我點頭才動手。');
    onSendToGlobalChat!(msg.toString());
    return true;
  }
}
