import 'package:flutter/material.dart';

/// SemiDAO 與開源社群設定頁面——從 settings_screen.dart 抽出
///
/// 包含：
/// - 審查金鑰（SemiDAO 預審 Vision API）
/// - Pinata IPFS JWT
/// - 錢包連接（Reown AppKit）
///
/// 這三項都是 SemiDAO 鏈上資產發佈的依賴，目前功能保留但 UI 暫時隱藏，
/// 等到 SemiDAO [門] 正式啟動時再開放。
///
/// [教練 Agent 2026-08-10] 從 settings_screen.dart 抽出，伴隨 settings_screen.dart 刪除。
class SemidaoSettingsPage extends StatelessWidget {
  const SemidaoSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // TODO [SemiDAO]: SemiDAO [門] 正式啟動時，把審查金鑰、Pinata、錢包三項移植到此頁面
    // 目前回傳空容器，避免 settings_screen.dart 刪除後丟失程式碼
    return const Scaffold(
      body: Center(
        child: Text('SemiDAO 與開源社群——即將到來'),
      ),
    );
  }
}
