import 'dart:async' show unawaited;
import 'dart:io' show Platform, File, FileMode;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'services/agent_loop/app_log_buffer.dart';
import 'services/sovereignty/trace_scrubber.dart';
import 'services/computer_use/cu_e2e_test.dart';
import 'services/system/tray_service.dart';
import 'services/api_usage_tracker.dart'; // [小葵 2026-09-21 收尾驗收] token 歷史載入
import 'services/trust/trust_loop.dart'; // [刀 6 K6.4]

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // [小葵 2026-09-06 Computer Use P1a] --cu-e2e：App 內真實環境 E2E 測試
  // （鐵則「終端測通≠App內通」——flutter test 是 fake channel 環境測不到）
  if (Platform.environment.containsKey('BRIDGE_CU_E2E') ||
      (Platform.environment['ARGS'] ?? '').contains('--cu-e2e')) {
    await runComputerUseE2E();
    return;
  }

  // [教練 Agent 2026-08-22] profile 模式灰屏驗屍器——build 例外在 profile 下
  // 不顯示紅屏（ErrorWidget 變灰），把完整堆疊寫 /tmp/bridge_ui_crash.log
  // 才能對症下藥（使用者 抓包：點農場日記IG合集節點→整頁灰）。
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    try {
            final f = File('/tmp/bridge_ui_crash.log');
            f.writeAsStringSync(
              '[${DateTime.now()}] ${details.exception}\n${details.stack}\n${'=' * 60}\n',
              mode: FileMode.append,
            );
    } catch (_) {}
  };

  // [Phase 1 2026-07-17] 安裝 App Log Ring Buffer
  appLogBuffer.install();

  // [小葵 2026-09-21 收尾驗收] API token 歷史載入（jsonl 持久化，
  // 7 天內）——儀表板重啟不洗牌
  try {
    await ApiUsageTracker.instance.loadPersisted();
  } catch (_) {}

  // [教練 Agent 2026-07-24] P4: 初始化視窗管理 + 系統列圖示
  // [教練 Agent 2026-07-30] iOS/Web 跳過 window_manager（無實作）
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1440, 900),
      // [教練 Agent 2026-08-14] 最小寬度 1280，防止頂部按鈕被擠壓產生黃黑警示條
      minimumSize: Size(1280, 720),
      titleBarStyle: TitleBarStyle.normal,
      skipTaskbar: false,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // 啟動系統列圖示（桌面限定）
    await TrayService().init();
    // [刀 6 K6.4] 信任 loop 引擎上線——做事→回報→檢討→升級（事件流供
    // 跑馬燈/TrustMeterCard/托盤摘要三個介面消費）
    TrustLoop.instance.wire();

    // [資料主權 P1 2026-09-14] 自動除痕上線——預設啟用（Blue 拍板）、
    // 每天一次、閒置時執行、2hr 年齡門檻；只清外傳暫存不碰任何資產。
    unawaited(TraceScrubber.instance.start());
  }

  runApp(const BridgeApp());
}
