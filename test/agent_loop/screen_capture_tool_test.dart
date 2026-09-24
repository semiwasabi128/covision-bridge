// screen_capture_tool_test.dart
// Phase 1.5 A3 (S24d) — screen_capture 工具測試
//
// 測試：
// 1. 工具介面定義正確（name, description, paramSpecs）
// 2. 未啟用時回傳適當錯誤（不 crash）
// 3. 啟用但用 stub executor → 回傳 UnsupportedError 訊息
// 4. 啟用且用 mock executor → 正確回傳截圖資訊

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/agent_tool.dart';
import 'package:bridge_app/services/agent_loop/agent_loop_tools/screen_capture_tool.dart';

/// Mock executor——模擬成功截圖
class _MockScreenCaptureExecutor implements ScreenCaptureExecutor {
  @override
  Future<ScreenCaptureResult> capture({
    String? windowTitle,
    String? appId,
  }) async {
    return ScreenCaptureResult(
      screenshotPath: '/tmp/screenshot_001.png',
      windowTitle: windowTitle ?? 'Safari — Google',
      appBundleId: appId ?? 'com.apple.Safari',
    );
  }
}

void main() {
  group('ScreenCaptureTool — 介面定義', () {
    test('name 是 screen_capture', () {
      final tool = ScreenCaptureTool(
        executor: StubScreenCaptureExecutor(),
        enabled: false,
      );
      expect(tool.name, 'screen_capture');
    });

    test('description 非空且包含關鍵詞', () {
      final tool = ScreenCaptureTool(
        executor: StubScreenCaptureExecutor(),
        enabled: false,
      );
      expect(tool.description, isNotEmpty);
      expect(tool.description.toLowerCase(), contains('截圖'));
      expect(tool.description.toLowerCase(), contains('視窗'));
    });

    test('paramSpecs 有 windowTitle 和 appId 兩個選填參數', () {
      final tool = ScreenCaptureTool(
        executor: StubScreenCaptureExecutor(),
        enabled: false,
      );
      expect(tool.paramSpecs.length, 2);

      final windowTitleSpec = tool.paramSpecs
          .firstWhere((p) => p.name == 'windowTitle');
      expect(windowTitleSpec.required, isFalse);

      final appIdSpec = tool.paramSpecs.firstWhere((p) => p.name == 'appId');
      expect(appIdSpec.required, isFalse);
    });

    test('toPromptDescription 產生有效描述', () {
      final tool = ScreenCaptureTool(
        executor: StubScreenCaptureExecutor(),
        enabled: false,
      );
      final desc = tool.toPromptDescription();
      expect(desc, contains('screen_capture'));
      expect(desc, contains('windowTitle'));
      expect(desc, contains('appId'));
    });
  });

  group('ScreenCaptureTool — 未啟用行為', () {
    test('enabled=false 時回傳失敗結果，不 crash', () async {
      final tool = ScreenCaptureTool(
        executor: StubScreenCaptureExecutor(),
        enabled: false,
      );
      final result = await tool.execute({});

      expect(result.success, isFalse);
      expect(result.content, contains('未啟用'));
    });

    test('未啟用時即使傳了參數也回傳失敗', () async {
      final tool = ScreenCaptureTool(
        executor: StubScreenCaptureExecutor(),
        enabled: false,
      );
      final result = await tool.execute({
        'windowTitle': 'Safari',
        'appId': 'com.apple.Safari',
      });

      expect(result.success, isFalse);
      expect(result.content, contains('未啟用'));
    });
  });

  group('ScreenCaptureTool — stub executor 行為', () {
    test('啟用但用 stub executor → 失敗訊息含原生層未實作', () async {
      final tool = ScreenCaptureTool(
        executor: StubScreenCaptureExecutor(),
        enabled: true,
      );
      final result = await tool.execute({});

      expect(result.success, isFalse);
      expect(result.content, contains('未實作'));
    });
  });

  group('ScreenCaptureTool — mock executor 行為', () {
    test('啟用 + mock executor → 成功回傳截圖資訊', () async {
      final tool = ScreenCaptureTool(
        executor: _MockScreenCaptureExecutor(),
        enabled: true,
      );
      final result = await tool.execute({
        'windowTitle': 'Xcode',
        'appId': 'com.apple.dt.Xcode',
      });

      expect(result.success, isTrue);
      expect(result.content, contains('截圖完成'));
      expect(result.content, contains('Xcode'));
      expect(result.content, contains('com.apple.dt.Xcode'));
      expect(result.mediaUrl, isNotNull);
      expect(result.metadata, isNotNull);
      expect(result.metadata!['screenshotPath'], isNotEmpty);
    });

    test('不傳參數 → 截取焦點視窗（mock 回傳預設值）', () async {
      final tool = ScreenCaptureTool(
        executor: _MockScreenCaptureExecutor(),
        enabled: true,
      );
      final result = await tool.execute({});

      expect(result.success, isTrue);
      expect(result.content, contains('截圖完成'));
    });

    test('傳空字串參數 → 當作不傳處理（mock 回傳預設值）', () async {
      final tool = ScreenCaptureTool(
        executor: _MockScreenCaptureExecutor(),
        enabled: true,
      );
      final result = await tool.execute({
        'windowTitle': '',
        'appId': '',
      });

      expect(result.success, isTrue);
    });
  });

  group('StubScreenCaptureExecutor', () {
    test('capture 擲 UnsupportedError', () async {
      final executor = StubScreenCaptureExecutor();
      expect(
        () => executor.capture(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
