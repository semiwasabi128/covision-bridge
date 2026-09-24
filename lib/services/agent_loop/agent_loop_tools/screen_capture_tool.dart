/// screen_capture 工具——截取指定視窗的螢幕截圖
///
/// Phase 1.5 A3（S24d）：Agent Loop 新增螢幕感知能力。
/// 設計參考：open-canvas-unified-design.md §5（螢幕感知技術路線）
///
/// 技術迴路：
/// 1. Screen Capture：CGWindowListCreateImage → 指定視窗截圖（不是全螢幕）
/// 2. Vision Analysis：Agent Loop 呼叫 vision 工具 → LLM 分析截圖內容
/// 3. Context Extraction：視窗標題 + App bundleId + 截圖理解 → 產生 ScreenCapture Entity
///
/// 隱私設計（D2/D3）：
/// - 預設關閉（screen_capture_enabled = false）
/// - 截取指定視窗，不是全螢幕
/// - 使用者主動開啟後才可用
///
/// 原生層：macOS 用 MethodChannel → CGWindowListCreateImage
/// 目前為 stub 實作（擲 UnsupportedError），原生實作待 TODO 完成。

import '../agent_tool.dart';

/// screen_capture 工具的執行結果資料
class ScreenCaptureResult {
  final String screenshotPath;
  final String windowTitle;
  final String appBundleId;

  const ScreenCaptureResult({
    required this.screenshotPath,
    required this.windowTitle,
    required this.appBundleId,
  });

  Map<String, dynamic> toJson() => {
        'screenshotPath': screenshotPath,
        'windowTitle': windowTitle,
        'appBundleId': appBundleId,
      };
}

/// screen_capture 工具的執行器介面
///
/// 實作類別負責呼叫原生層（MethodChannel → CGWindowListCreateImage）。
/// 目前只有 stub 實作，原生層待實作。
abstract class ScreenCaptureExecutor {
  /// 截取指定視窗
  ///
  /// [windowTitle] — 視窗標題（可選，模糊匹配）
  /// [appId] — App bundleId（可選，如 com.apple.Safari）
  /// 都不傳則截取當前焦點視窗
  ///
  /// 回傳 [ScreenCaptureResult]，含截圖檔案路徑、視窗標題、appBundleId
  Future<ScreenCaptureResult> capture({
    String? windowTitle,
    String? appId,
  });
}

/// Stub 實作——未啟用或原生層未實作時使用
class StubScreenCaptureExecutor implements ScreenCaptureExecutor {
  final String reason;

  StubScreenCaptureExecutor({this.reason = 'screen_capture 未啟用或原生層未實作'});

  @override
  Future<ScreenCaptureResult> capture({
    String? windowTitle,
    String? appId,
  }) async {
    throw UnsupportedError(reason);
  }
}

/// screen_capture AgentTool
///
/// 讓 LLM 自主截取螢幕視窗。
/// 需要透過 feature flag（screen_capture_enabled）啟用。
class ScreenCaptureTool extends AgentTool {
  final ScreenCaptureExecutor _executor;
  final bool _enabled;

  /// [_enabled] — 是否啟用（feature flag screen_capture_enabled）
  ScreenCaptureTool({
    required ScreenCaptureExecutor executor,
    bool enabled = false,
  })  : _executor = executor,
        _enabled = enabled;

  @override
  String get name => 'screen_capture';

  @override
  String get description =>
      '截取指定視窗的螢幕截圖。用於查看使用者目前正在看的內容、分析螢幕上的資訊。'
      '可指定視窗標題或 App bundleId，不指定則截取當前焦點視窗。'
      '注意：此工具涉及隱私，需要使用者明確啟用。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'windowTitle',
          description: '要截取的視窗標題（模糊匹配）。不傳則使用 appId 或焦點視窗。',
        ),
        AgentToolParamSpec(
          name: 'appId',
          description: '目標 App 的 bundleId（如 com.apple.Safari）。不傳則使用 windowTitle 或焦點視窗。',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    if (!_enabled) {
      return AgentToolResult.failure(
        'screen_capture 工具未啟用。此功能涉及螢幕截圖隱私，需要使用者在設定中主動開啟。',
      );
    }

    final windowTitle = args['windowTitle']?.toString();
    final appId = args['appId']?.toString();

    try {
      final result = await _executor.capture(
        windowTitle: windowTitle?.isNotEmpty == true ? windowTitle : null,
        appId: appId?.isNotEmpty == true ? appId : null,
      );
      return AgentToolResult.success(
        '截圖完成。視窗：${result.windowTitle}（${result.appBundleId}）。截圖路徑：${result.screenshotPath}',
        mediaUrl: result.screenshotPath,
        metadata: result.toJson(),
      );
    } on UnsupportedError catch (e) {
      return AgentToolResult.failure('screen_capture 原生層未實作：$e');
    } catch (e) {
      return AgentToolResult.failure('截圖失敗：$e');
    }
  }
}
