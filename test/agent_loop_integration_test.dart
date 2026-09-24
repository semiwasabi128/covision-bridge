/// Agent Loop 整合測試 — Headless 測試執行者
///
/// [小葵 2026-08-07] P0.5c：headless agent loop test
/// 取代「請 Blue 實機測試 + 回報」的低效率循環。
///
/// 設計：
/// - 這個測試可以在背景跑，不需要 UI 互動
/// - 直接呼叫 ChatController 內部方法，模擬使用者送出訊息
/// - 觀察 ~/Documents/bridge_app_logs/agent_loop_model.log
/// - 觀察 _runAgentLoopIfNeeded 的內部 state
/// - 產出結構化報告
///
/// 使用情境：
/// 1. 修了一個 bug（例如「inspectBridgeRuntime 自動覆寫 provider」）
/// 2. 跑 `flutter test test/agent_loop_integration_test.dart`
/// 3. 看報告：每輪 LLM 呼叫用了什麼 model、有沒有切換、有沒有卡住
/// 4. 通過才請 Blue 實機確認；不通過就繼續修
///
/// 這個測試還沒實作，這是骨架。
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Agent Loop headless test', () {
    test('scenario: user selects gemini → send message → verify stays gemini', () async {
      // TODO:
      // 1. Set StorageService provider = 'gemini'
      // 2. Set StorageService api_model_v2_gemini = 'gemini-3.5-flash'
      // 3. Build ChatController
      // 4. Call sendDirectMessage('查 Gemini Imagen API 文件然後生成一張圖')
      // 5. Wait up to 60s for completion
      // 6. Read ~/Documents/bridge_app_logs/agent_loop_model.log
      // 7. Assert:
      //    - 至少有一輪 log entry 是 user_locked + provider=gemini
      //    - 沒有任何 router_default + provider=local 的 entry
      //    - 沒有任何 provider=local 的 entry
      // 8. Print summary
    });

    test('scenario: user selects default → can dispatch sub-agent', () async {
      // TODO:
      // 1. Set StorageService provider = 'default'
      // 2. Call sendDirectMessage('分析這個...') triggering delegate_subagent
      // 3. Verify delegate_subagent was called (not blocked)
      // 4. Verify at least one LLM call used a different model
    });

    test('scenario: provider exhausted → returns error not fallback', () async {
      // TODO:
      // 1. Set StorageService provider = 'gemini'
      // 2. Inject a fake ApiService that returns 429 quota exceeded
      // 3. Send message
      // 4. Verify error message contains "額度耗盡" not silent fallback
    });
  });
}
