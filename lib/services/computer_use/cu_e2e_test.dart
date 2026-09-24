// 橋樑 Computer Use P1a — App 內真實 E2E 測試（--cu-e2e 啟動參數觸發）
//
// 鐵則「終端測通≠App內通」：本檔在真實 App 環境跑 platform channel 閉環，
// 結果寫 /tmp/bridge_cu_e2e.log，跑完即退出（不留視窗垃圾）。
// 觸發：./bridge_app --cu-e2e
import 'dart:io';

import 'computer_use_service.dart';

Future<void> runComputerUseE2E() async {
  final log = StringBuffer();
  void t(String s) {
    log.writeln(s);
    debugPrint2(s);
  }

  final cu = ComputerUseService.instance;
  try {
    t('[T1] 初始狀態: ${(await cu.refresh()).state.name}');
    final tcc = await cu.tccStatus();
    t('[T2] TCC: accessibility=${tcc.accessibility} screen=${tcc.screen}');

    // arm（無 TCC 權限時會拿到失敗原因——這也是要驗證的路徑）
    final armErr = await cu.arm('e2e-test');
    t('[T3] arm: ${armErr == null ? "OK" : "FAIL: $armErr"}');

    if (armErr == null) {
      final activated = await cu.activate();
      t('[T4] activate: $activated');

      // 注入：滑鼠移動（無點擊 = 無破壞性）
      final moved = await ComputerUseService.instance
          .click(-1, -1, count: 0); // 座標 -1 會被 AX 圍欄擋下？先驗 move
      t('[T5] click(-1,-1,count=0) 回傳: $moved（預期 false=圍欄或座標拒絕）');

      final status = await cu.refresh();
      t('[T6] 注入後狀態: ${status.state.name}');

      await cu.disarm();
      t('[T7] disarm 後: ${(await cu.refresh()).state.name}');

      // AX 樹（有權限才有內容）
      final tree = await cu.windowTree(maxDepth: 2);
      t('[T8] ax.windowTree: ${tree == null ? "null" : "${tree.toString().length} chars"}');
      if (tree != null) {
        final s = tree.toString();
        t('      前250字: ${s.substring(0, s.length > 250 ? 250 : s.length)}');
      }
    }
    t('=== CU E2E DONE（exit 0）===');
    File('/tmp/bridge_cu_e2e.log').writeAsStringSync(log.toString());
    exit(0);
  } catch (e) {
    t('CU E2E ERROR: $e');
    File('/tmp/bridge_cu_e2e.log').writeAsStringSync(log.toString());
    exit(1);
  }
}

// ignore: avoid_print
void debugPrint2(String s) => print('[CU-E2E] $s');
