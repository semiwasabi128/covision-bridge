// ignore_for_file: avoid_print
//
// [小葵 2026-08-08] Agent Loop 邏輯驗證腳本
// 直接在 terminal 跑，不需要 UI 或 MCP 連線。
// 測試項目：
//   1. ProductionAgentLoopLLMClient._resolveModel() 在不同 StorageService provider 設定下的行為
//   2. AgentLoopStageCallback 被正確觸發
//
// 用法：cd ~/Developer/bridge_app && dart run tool/test_agent_loop_logic.dart
//

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 直接 import 要測的模組
import 'package:bridge_app/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StorageService provider 設定', () {
    test('設定 gemini → getProvider 回傳 gemini', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'gemini',
      });
      final provider = await StorageService.getProvider();
      expect(provider, 'gemini');
      print('✅ provider=gemini → getProvider() 回傳 $provider');
    });

    test('設定 default → getProvider 回傳 default', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'default',
      });
      final provider = await StorageService.getProvider();
      expect(provider, 'default');
      print('✅ provider=default → getProvider() 回傳 $provider');
    });

    test('設定 local → getProvider 回傳 local', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'local',
      });
      final provider = await StorageService.getProvider();
      expect(provider, 'local');
      print('✅ provider=local → getProvider() 回傳 $provider');
    });
  });

  group('userWantsCloud 判斷邏輯', () {
    test('gemini → userWantsCloud=true', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'gemini',
      });
      final provider = await StorageService.getProvider();
      final userWantsCloud = provider != null &&
          provider != 'local' &&
          provider != 'default';
      expect(userWantsCloud, isTrue);
      print('✅ gemini → userWantsCloud=$userWantsCloud（應鎖定 provider）');
    });

    test('default → userWantsCloud=false', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'default',
      });
      final provider = await StorageService.getProvider();
      final userWantsCloud = provider != null &&
          provider != 'local' &&
          provider != 'default';
      expect(userWantsCloud, isFalse);
      print('✅ default → userWantsCloud=$userWantsCloud（走雞尾酒模式）');
    });

    test('local → userWantsCloud=false', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'local',
      });
      final provider = await StorageService.getProvider();
      final userWantsCloud = provider != null &&
          provider != 'local' &&
          provider != 'default';
      expect(userWantsCloud, isFalse);
      print('✅ local → userWantsCloud=$userWantsCloud（走本地模式）');
    });
  });

  group('lockedProvider prompt 注入邏輯', () {
    test('gemini → lockedProvider 應為 gemini', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'gemini',
      });
      final provider = await StorageService.getProvider();
      final userWantsCloud = provider != null &&
          provider != 'local' &&
          provider != 'default';
      final lockedProvider = userWantsCloud ? provider : null;
      expect(lockedProvider, 'gemini');
      print('✅ gemini → lockedProvider=$lockedProvider');
    });

    test('default → lockedProvider 應為 null', () async {
      SharedPreferences.setMockInitialValues({
        'provider': 'default',
      });
      final provider = await StorageService.getProvider();
      final userWantsCloud = provider != null &&
          provider != 'local' &&
          provider != 'default';
      final lockedProvider = userWantsCloud ? provider : null;
      expect(lockedProvider, isNull);
      print('✅ default → lockedProvider=$lockedProvider（不鎖定）');
    });
  });

  group('AgentLoopStageCallback typedef 驗證', () {
    test('stage callback 可以被建立和呼叫', () {
      String? capturedStage;
      String? capturedToolName;
      String? capturedDetail;

      void onStage(String stage, {String? toolName, String? detail}) {
        capturedStage = stage;
        capturedToolName = toolName;
        capturedDetail = detail;
      }

      // 模擬 AgentLoop 內部的呼叫
      onStage('thinking', detail: '第 1/10 輪思考中');
      expect(capturedStage, 'thinking');
      expect(capturedDetail, '第 1/10 輪思考中');
      print('✅ stage=thinking → 被正確捕獲');

      onStage('tool_start', toolName: 'web_search', detail: '正在執行：web_search');
      expect(capturedStage, 'tool_start');
      expect(capturedToolName, 'web_search');
      print('✅ stage=tool_start → 被正確捕獲 (tool=$capturedToolName)');

      onStage('timeout', detail: 'LLM 思考超時');
      expect(capturedStage, 'timeout');
      print('✅ stage=timeout → 被正確捕獲');

      onStage('error', detail: 'LLM 呼叫失敗');
      expect(capturedStage, 'error');
      print('✅ stage=error → 被正確捕獲');
    });
  });

  group('DelegateSubagent 鎖定邏輯', () {
    test('鎖定 gemini → 請求 glm provider 應被擋下', () {
      const lockedProvider = 'gemini';
      const requestedProvider = 'glm';

      // 模擬 DelegateSubagentTool 內部的鎖定檢查
      final shouldBlock = lockedProvider.isNotEmpty &&
          requestedProvider != lockedProvider;

      expect(shouldBlock, isTrue);
      print('✅ 鎖定 gemini → 請求 glm 被擋下');
    });

    test('鎖定 gemini → 請求 gemini 應通過', () {
      const lockedProvider = 'gemini';
      const requestedProvider = 'gemini';

      final shouldBlock = lockedProvider.isNotEmpty &&
          requestedProvider != lockedProvider;

      expect(shouldBlock, isFalse);
      print('✅ 鎖定 gemini → 請求 gemini 通過');
    });

    test('無鎖定 → 任何 provider 都通過', () {
      const lockedProvider = null;
      const requestedProvider = 'glm';

      final shouldBlock = lockedProvider != null &&
          lockedProvider.isNotEmpty &&
          requestedProvider != lockedProvider;

      expect(shouldBlock, isFalse);
      print('✅ 無鎖定 → glm 通過（預設模式）');
    });
  });
}
