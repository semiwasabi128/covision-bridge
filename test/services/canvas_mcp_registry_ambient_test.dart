// canvas_mcp_registry_ambient_test.dart
// [隊友訊息流 C1 2026-09-08] ambient 覆寫堆疊測試
// 驗收合約：
// 1. ambient 空 → controller getter 回前景
// 2. push 後 → 回堆疊頂（任務工作畫布），前景指標不變
// 3. pop 後 → 還原前景
// 4. 多任務堆疊先進後出
// 5. dispose 判斷用 foregroundController（ambient 期間不誤清前景）

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_mcp_registry.dart';

CanvasController _newCtrl(String canvasId) =>
    CanvasController(entityGraph: null, canvasId: canvasId);

void main() {
  late CanvasMcpRegistry reg;

  setUp(() {
    reg = CanvasMcpRegistry.instance;
  });

  tearDown(() {
    // 清理：彈出所有殘留（tearDown 順序不可靠，用 while 保險）
    reg.controller = null;
  });

  test('ambient 空 → controller getter 回前景', () {
    final fg = _newCtrl('fg');
    reg.controller = fg;
    expect(identical(reg.controller, fg), isTrue);
    expect(reg.hasAmbientOverride, isFalse);
  });

  test('push 後工具路由到任務工作畫布，前景指標不變', () {
    final fg = _newCtrl('fg');
    final work = _newCtrl('task-canvas-1');
    reg.controller = fg;

    reg.pushAmbientCanvas(work);
    expect(identical(reg.controller, work), isTrue,
        reason: 'ambient 期間 canvas_* 工具應看到任務工作畫布');
    expect(identical(reg.foregroundController, fg), isTrue,
        reason: '前景指標不被污染');

    reg.popAmbientCanvas(work);
    expect(identical(reg.controller, fg), isTrue, reason: 'pop 後還原前景');
  });

  test('多任務堆疊先進後出', () {
    final fg = _newCtrl('fg');
    final w1 = _newCtrl('task-1');
    final w2 = _newCtrl('task-2');
    reg.controller = fg;

    reg.pushAmbientCanvas(w1);
    reg.pushAmbientCanvas(w2);
    expect(identical(reg.controller, w2), isTrue, reason: '堆疊頂=最後推入');

    reg.popAmbientCanvas(w2);
    expect(identical(reg.controller, w1), isTrue, reason: '彈出後回上一個任務');

    reg.popAmbientCanvas(w1);
    expect(identical(reg.controller, fg), isTrue);
  });

  test('dispose 判斷用前景原體——ambient 期間前景替換不誤清', () {
    final fgOld = _newCtrl('fg-old');
    final work = _newCtrl('task-1');
    final fgNew = _newCtrl('fg-new');
    reg.controller = fgOld;
    reg.pushAmbientCanvas(work);

    // 前景 workspace dispose：比對 foregroundController（不是 getter）
    final shouldClear = reg.foregroundController == fgOld;
    expect(shouldClear, isTrue, reason: 'ambient 期間仍能正確識別前景');

    reg.controller = fgNew; // 新前景注入
    expect(identical(reg.controller, work), isTrue,
        reason: '前景更新不影響 ambient 路由');

    reg.popAmbientCanvas(work);
    expect(identical(reg.controller, fgNew), isTrue);
  });
}
