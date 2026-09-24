// system_routine_player.dart
// [刀 5 延伸 SR.4 2026-09-09] 全電腦示範重播——agent 的手。
//
// 重播策略（設計稿 §2）：
//   1. AX 錨點優先：事件帶 role+title → windowTree 找元素 → 精準動作
//   2. 座標退路：AX 找不到 → input.click 座標重現
//   （本版先座標重現——AX 錨點重播列 Phase 2，見誠實聲明）
//
// 安全：重播前必經 computer_use gate.arm（既有真人接管狀態機——Esc 隨時殺）

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:bridge_app/services/computer_use/computer_use_service.dart';
import 'package:bridge_app/services/routines/system_routine_recorder.dart';

class SystemRoutinePlayer {
  SystemRoutinePlayer._();
  static final SystemRoutinePlayer instance = SystemRoutinePlayer._();

  final _cu = ComputerUseService.instance;
  static const _ch = MethodChannel('bridge.system_routine.macos.v1');

  /// 單步重播策略（P2.2）：AX 錨點優先——press/setValue 直接對元素
  /// 下手（不怕視窗移位）；找不到才座標退路。
  /// 回傳 true=已執行。
  Future<bool> _replayStep(SystemRoutineEvent e) async {
    switch (e.action) {
      case 'click':
        // AX 錨點優先：有 role+title 就 press
        if (e.role.isNotEmpty && e.title.isNotEmpty && e.app.isNotEmpty) {
          try {
            final r = await _ch.invokeMethod('ax.press', {
              'app': e.app, 'role': e.role, 'title': e.title,
            });
            if ((r as Map)['ok'] == true) return true;
          } on PlatformException {
            // 落到座標退路
          }
        }
        // 座標退路
        if (e.x != null && e.y != null) {
          return await _cu.click(e.x!, e.y!);
        }
        return false;
      case 'key':
        if (e.keyCode != null) return await _cu.key(e.keyCode!);
        return false;
      case 'scroll':
        return false; // P3：座標系轉換需實測
      default:
        return false;
    }
  }

  /// 重播一組事件（帶步間延遲——模擬真人節奏）
  ///
  /// 回傳 (played, skipped)——重播幾步、跳過幾步（遮罩事件必跳）。
  Future<({int played, int skipped})> replay(
    List<SystemRoutineEvent> events, {
    Duration stepDelay = const Duration(milliseconds: 600),
  }) async {
    var played = 0;
    var skipped = 0;

    // 安全圍欄：arm gate（Esc 急停 + 真人接管由既有狀態機保障）
    final taskId = await _cu.arm('routine-replay-${DateTime.now().millisecondsSinceEpoch}');
    if (taskId == null) {
      debugPrint('[SystemRoutine] 重播被拒——gate arm 失敗（可能無權限或已在執行）');
      return (played: 0, skipped: events.length);
    }
    final activated = await _cu.activate();
    if (!activated) {
      debugPrint('[SystemRoutine] gate activate 失敗');
      await _cu.disarm();
      return (played: 0, skipped: events.length);
    }

    try {
      for (final e in events) {
        // 遮罩事件絕不重播（密碼框——隱私鐵則）
        if (e.masked) {
          skipped++;
          continue;
        }
        // 節奏
        await Future<void>.delayed(stepDelay);

        final ok = await _replayStep(e);
        if (ok) {
          played++;
        } else {
          skipped++;
        }
      }
    } finally {
      await _cu.disarm();
    }
    debugPrint('[SystemRoutine] 重播完成：$played 步、跳過 $skipped 步');
    return (played: played, skipped: skipped);
  }
}
