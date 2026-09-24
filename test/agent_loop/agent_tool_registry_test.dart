// agent_tool_registry_test.dart
// Phase 1.5 A3 (S24d) — AgentToolRegistry 測試
//
// 確認：
// 1. withDefaults 正確註冊 screen_capture 和 canvas_place
// 2. 現有 9 個工具不被破壞
// 3. screen_capture 預設未啟用
// 4. feature flag 可以啟用 screen_capture

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_registry.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';

void main() {
  group('AgentToolRegistry.withDefaults — A3 新工具註冊', () {
    test('包含 screen_capture 工具', () {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
      );

      expect(registry.has('screen_capture'), isTrue);
    });

    test(
      'canvas_place 已拔除（2026-08-21 永遠失敗的 stub，佔名額誤導 LLM）',
      () {
        final registry = AgentToolRegistry.withDefaults(
          bridgeActionExecutor: BridgeActionExecutor(),
          brainContainerService: null,
        );

        // [教練 Agent 2026-08-21] 畫布能力盤點整頓：canvas_place 是 B1
        // 未實作的永遠失敗 stub → 拔。放節點改由 canvas_look/canvas 系
        // 工具與 compass_toolseek 動態武器箱接手。
        expect(registry.has('canvas_place'), isFalse);
      },
    );

    test('現有工具仍存在（5 BridgeAction + 1 memory_search）', () {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
      );

      expect(registry.has('web_search'), isTrue);
      expect(registry.has('image_recognition'), isTrue);
      expect(registry.has('generate_image'), isTrue);
      expect(registry.has('create_document'), isTrue);
      expect(registry.has('desktop_files'), isTrue);
      expect(registry.has('memory_search'), isTrue);
    });

    test('總工具數 ≥ 12（無 browser，持續新增工具）', () {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
      );

      // 最初 12 個：5 BridgeAction + 1 memory_search + 2 A3 + 2 S18 + 2 P0b
      // 之後持續新增：local_vision_analyze, video_download, frame_extract,
      // audio_transcribe, local_code_generate, delegate_subagent,
      // read_source_file, patch_source_file, run_terminal, read_app_log,
      // restart_app, ui_* (3), vault_* (2+), knowledge_* (3), workflow_* (2)
      // 不固定精確數字，只確保 ≥ 12 且包含 delegate_subagent
      expect(registry.all.length, greaterThanOrEqualTo(12));
      expect(registry.has('delegate_subagent'), isTrue);
    });

    test('toPromptSection 是動態武器箱指引（compass_toolseek）', () {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
      );

      // [向量工作流] 不預載工具清單——prompt 只有一行通行證：
      // compass_toolseek 帶意圖查工具。canvas_place 在常用快捷列。
      final prompt = registry.toPromptSection();
      expect(prompt, contains('compass_toolseek'));
      expect(prompt, contains('canvas_place')); // 常用快捷（免查）列
    });

    test('P0b: 包含 check_capability_status 和 open_setting 工具', () {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
      );

      expect(registry.has('check_capability_status'), isTrue);
      expect(registry.has('open_setting'), isTrue);
    });

    test('S18: canvas_remove 存在（canvas_connect 已拔——EntityGraph 版與 MCP 版撞名，改走 MCP）', () {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
      );

      // [教練 Agent 2026-08-21] canvas_connect 撞名整頓：EntityGraph 版與
      // MCP 版同名不同參數，後註冊蓋前面的、行為取決於註冊順序不可靠
      // → 拔 EntityGraph 版，畫布連線一律走 MCP（= UI 真實顯示狀態）。
      expect(registry.has('canvas_connect'), isFalse);
      expect(registry.has('canvas_remove'), isTrue);
    });

    test('screen_capture_enabled 預設 false → 執行時回傳未啟用', () async {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
        // screenCaptureEnabled 不傳 → 預設 false
      );

      final tool = registry.get('screen_capture')!;
      final result = await tool.execute({});

      expect(result.success, isFalse);
      expect(result.content, contains('未啟用'));
    });

    test('screen_capture_enabled=true → 執行時回傳未實作（stub）', () async {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
        screenCaptureEnabled: true,
      );

      final tool = registry.get('screen_capture')!;
      final result = await tool.execute({});

      expect(result.success, isFalse);
      expect(result.content, contains('未實作'));
    });

    test('canvas_place 已拔除 → get 回傳 null（不再是 stub）', () async {
      final registry = AgentToolRegistry.withDefaults(
        bridgeActionExecutor: BridgeActionExecutor(),
        brainContainerService: null,
      );

      // [教練 Agent 2026-08-21] canvas_place stub 已整個拔除
      expect(registry.get('canvas_place'), isNull);
    });
  });
}
