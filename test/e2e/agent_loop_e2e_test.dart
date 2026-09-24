// ignore_for_file: avoid_print
//
// [小葵 2026-08-08] L3: Agent Loop 端到端測試
//
// 這是小葵↔小橋直接溝通的核心機制。
// 不需要 UI、不需要螢幕、不需要 Blue 介入。
// 直接建構 AgentLoop、送訊息、收回應、驗證。
//
// 用法：flutter test test/e2e/agent_loop_e2e_test.dart
//
// 產出：JSON 報告寫到 test/reports/agent_loop_e2e_report.json
// 小葵用 read_file 讀報告判斷 pass/fail。
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bridge_app/services/storage_service.dart';
import 'package:bridge_app/services/agent_loop/agent_loop.dart';
import 'package:bridge_app/services/agent_loop/agent_tool_registry.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_prompt_builder.dart';
import 'package:bridge_app/services/agent_loop/production_agent_loop_llm_client.dart';

/// 測試報告結構
class TestReport {
  String testName;
  String scenario;
  String? providerSetting;
  String userMessage;
  List<Map<String, dynamic>> stages = [];
  String? finalReply;
  int turnCount = 0;
  Duration? elapsed;
  bool passed = false;
  String? failureReason;

  TestReport({
    required this.testName,
    required this.scenario,
    this.providerSetting,
    required this.userMessage,
  });

  Map<String, dynamic> toJson() => {
    'testName': testName,
    'scenario': scenario,
    'providerSetting': providerSetting,
    'userMessage': userMessage,
    'stages': stages,
    'finalReply': finalReply,
    'turnCount': turnCount,
    'elapsedMs': elapsed?.inMilliseconds,
    'passed': passed,
    'failureReason': failureReason,
    'timestamp': DateTime.now().toIso8601String(),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('L3: Agent Loop E2E', () {
    test('場景 1: 指定 Gemini → 簡單對話 → 全程鎖定 Gemini', () async {
      final report = TestReport(
        testName: 'gemini_lock_simple_chat',
        scenario: '使用者選 Gemini，送簡單訊息，驗證全程用 Gemini',
        providerSetting: 'gemini',
        userMessage: '你好，請用一句話介紹自己',
      );

      // 設定 provider = gemini
      SharedPreferences.setMockInitialValues({
        'provider': 'gemini',
        'api_token_v2_gemini': const String.fromEnvironment(
          'GEMINI_API_KEY',
          defaultValue: '',
        ),
        'api_model_v2_gemini': 'gemini-2.5-flash',
      });

      final provider = await StorageService.getProvider();
      print('Provider: $provider');

      // 檢查 token 是否存在
      final token = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
      if (token.isEmpty) {
        print('⚠️ 跳過：GEMINI_API_KEY 環境變數未設定');
        print('   要跑這個測試：flutter test --dart-define=GEMINI_API_KEY=xxx');
        report.passed = false;
        report.failureReason = 'GEMINI_API_KEY 未設定';
        _writeReport(report);
        return;
      }

      // 建構 AgentLoop
      final toolRegistry = AgentToolRegistry();

      final systemPrompt = AgentLoopPromptBuilder.build(
        toolRegistry: toolRegistry,
        lockedProvider: 'gemini',
      );

      // 建構 LLM client
      final llmClient = ProductionAgentLoopLLMClient(
        model: 'gemini-2.5-flash',
      );

      final loop = AgentLoop(
        toolRegistry: toolRegistry,
        llmClient: llmClient,
      );

      // Stage callback 捕獲
      final stages = <Map<String, dynamic>>[];

      // 執行
      final result = await loop.run(
        systemPrompt: systemPrompt,
        userMessage: report.userMessage,
        maxTurns: 3,
        onStage: (stage, {toolName, detail}) {
          final entry = {
            'stage': stage,
            'toolName': toolName,
            'detail': detail,
            'timestamp': DateTime.now().toIso8601String(),
          };
          stages.add(entry);
          print('  [$stage] ${toolName ?? ''} ${detail ?? ''}');
        },
        onProgress: (turn, max, toolCall, toolResult, llmOutput) {
          print('  [progress] turn=$turn/$max tool=${toolCall?.name}');
        },
      ).timeout(const Duration(seconds: 90), onTimeout: () {
        throw TimeoutException('Agent Loop 90 秒內未完成');
      });

      // 記錄結果
      report.stages = stages;
      report.finalReply = result.reply;
      report.turnCount = result.turns.length;
      report.elapsed = result.elapsed;

      print('');
      print('=== 結果 ===');
      print('回應：${result.reply}');
      print('Turns：${result.turns.length}');
      print('耗時：${result.elapsed.inSeconds}秒');
      print('Stages：${stages.length} 個事件');

      // 驗證
      bool allPassed = true;
      String? failure;

      // 1. 回應不為空
      if (result.reply.isEmpty) {
        allPassed = false;
        failure = '回應為空';
      }

      // 2. 至少有一個 thinking stage
      final hasThinking = stages.any((s) => s['stage'] == 'thinking');
      if (!hasThinking) {
        allPassed = false;
        failure = '沒有觸發 thinking stage';
      }

      // 3. 沒有 timeout 或 error
      final hasTimeout = stages.any((s) => s['stage'] == 'timeout');
      final hasError = stages.any((s) => s['stage'] == 'error');
      if (hasTimeout) {
        allPassed = false;
        failure = '發生 timeout';
      }
      if (hasError) {
        allPassed = false;
        failure = '發生 error';
      }

      // 4. 沒有 delegate_subagent 被呼叫（鎖定模式下）
      final hasDelegate = stages.any((s) =>
        s['stage'] == 'tool_start' && s['toolName'] == 'delegate_subagent');
      if (hasDelegate) {
        allPassed = false;
        failure = '鎖定模式下呼叫了 delegate_subagent';
      }

      report.passed = allPassed;
      report.failureReason = failure;

      _writeReport(report);

      expect(allPassed, isTrue, reason: failure ?? '未知原因');
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('場景 2: 指定 Gemini → 請求上網搜尋 → 不切換 provider', () async {
      final report = TestReport(
        testName: 'gemini_lock_web_search',
        scenario: '使用者選 Gemini，要求搜尋，驗證不切到 local',
        providerSetting: 'gemini',
        userMessage: '請幫我查一下今天是幾月幾號',
      );

      final token = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
      if (token.isEmpty) {
        print('⚠️ 跳過：GEMINI_API_KEY 未設定');
        report.passed = false;
        report.failureReason = 'GEMINI_API_KEY 未設定';
        _writeReport(report);
        return;
      }

      SharedPreferences.setMockInitialValues({
        'provider': 'gemini',
        'api_token_v2_gemini': token,
        'api_model_v2_gemini': 'gemini-2.5-flash',
      });

      final toolRegistry = AgentToolRegistry();

      final systemPrompt = AgentLoopPromptBuilder.build(
        toolRegistry: toolRegistry,
        lockedProvider: 'gemini',
      );

      // 建構 LLM client
      final llmClient = ProductionAgentLoopLLMClient(
        model: 'gemini-2.5-flash',
      );

      final loop = AgentLoop(
        toolRegistry: toolRegistry,
        llmClient: llmClient,
      );

      final stages = <Map<String, dynamic>>[];

      final result = await loop.run(
        systemPrompt: systemPrompt,
        userMessage: report.userMessage,
        maxTurns: 5,
        onStage: (stage, {toolName, detail}) {
          stages.add({
            'stage': stage,
            'toolName': toolName,
            'detail': detail,
          });
          print('  [$stage] ${toolName ?? ''} ${detail ?? ''}');
        },
      ).timeout(const Duration(seconds: 120), onTimeout: () {
        throw TimeoutException('Agent Loop 120 秒內未完成');
      });

      report.stages = stages;
      report.finalReply = result.reply;
      report.turnCount = result.turns.length;
      report.elapsed = result.elapsed;

      print('');
      print('=== 結果 ===');
      print('回應：${result.reply}');
      print('Turns：${result.turns.length}');

      // 驗證：不呼叫 delegate_subagent
      final hasDelegate = stages.any((s) =>
        s['stage'] == 'tool_start' && s['toolName'] == 'delegate_subagent');
      expect(hasDelegate, isFalse,
        reason: '鎖定 Gemini 模式下不應該呼叫 delegate_subagent');

      report.passed = !hasDelegate;
      _writeReport(report);
    }, timeout: const Timeout(Duration(seconds: 150)));
  });
}

void _writeReport(TestReport report) {
  final dir = Directory('test/reports');
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  final file = File('test/reports/agent_loop_e2e_report.json');

  // 如果檔案已存在，讀取後 append
  List<dynamic> reports = [];
  if (file.existsSync()) {
    try {
      reports = json.decode(file.readAsStringSync()) as List<dynamic>;
    } catch (_) {}
  }

  // 移除同名的舊報告
  reports.removeWhere((r) => r['testName'] == report.testName);
  reports.add(report.toJson());

  file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(reports));
  print('');
  print('📄 報告已寫入 test/reports/agent_loop_e2e_report.json');
}
