// move_memory_bridge.dart
// [Blue 令 2026-09-12] 招式與記憶的橋樑——「學會的招式永不遺忘」。
//
// Blue 的願景：記憶永不刪除、永不失憶，但 Agent 不用負載全部記憶——
// 靈活調尋、快速回憶。招式（程序性記憶）存進 agent_memories
// （經驗表——天生不跑衰減），用 embedding 檢索找得回來。

import 'package:bridge_app/services/routines/system_routine_store.dart';
import 'package:bridge_app/services/agent_loop/agent_knowledge_service.dart';
import 'package:bridge_app/services/brain_container/brain_database.dart';

class MoveMemoryBridge {
  MoveMemoryBridge._();
  static final MoveMemoryBridge instance = MoveMemoryBridge._();

  /// 存招式時自動寫一條程序性記憶（memory_type: skill）
  ///
  /// 內容格式讓檢索時 Agent 一看就懂怎麼用：
  ///   招式「發票歸檔」· 12 步
  ///   摘要：在 Safari 開發票系統→點匯出→選資料夾
  ///   使出：use_move(move_name: "發票歸檔") 或畫布🥋節點
  Future<bool> onMoveSaved(SavedRoutine move) async {
    try {
      final summary = move.events.take(5).map((e) => e.story).join('；');
      final content = StringBuffer()
        ..write('招式「${move.name}」· ${move.stepCount} 步\n')
        ..write('摘要：${summary.isEmpty ? "（看操作故事）" : summary}\n')
        ..write('使出：use_move(move_name: "${move.name}") 或畫布🥋招式節點\n')
        ..write('學會日期：${move.recordedAt.year}/${move.recordedAt.month}/${move.recordedAt.day}');
      AgentKnowledgeService.instance.createMemory(
        title: '招式：${move.name}',
        content: content.toString(),
        tags: 'skill, move, 招式, 代操作',
        memoryType: 'skill',
      );
      return true;
    } catch (_) {
      return false; // 記憶寫入失敗不阻斷招式存檔（誠實降級）
    }
  }

  /// 招式重播完成後寫自傳記憶（memory_type: experience）
  ///
  /// 「自己藉由經驗記憶成長升級」——重播結果（成功幾步/跳過幾步）
  /// 變成夥伴的經歷，下次同類任務 Agent 檢索得到「上次這招 10/12」。
  Future<bool> onMoveReplayed({
    required SavedRoutine move,
    required int played,
    required int skipped,
  }) async {
    try {
      final verdict = skipped == 0
          ? '全數命中'
          : (played > skipped ? '大致成功' : '值得重錄');
      final content = StringBuffer()
        ..write('使出「${move.name}」：${played} 步執行、${skipped} 步跳過（$verdict）\n')
        ..write(switch (verdict) {
          '全數命中' => '這招狀態良好，可放心再用。',
          '大致成功' => '部分步驟落空（畫面變了？）——下次使出前可提醒使用者確認。',
          _ => '這招已過時（目標軟體改版？）——建議重錄。',
        })
        ..write('\n時間：${DateTime.now().month}/${DateTime.now().day}');
      AgentKnowledgeService.instance.createMemory(
        title: '經驗：使出「${move.name}」（$verdict）',
        content: content.toString(),
        tags: 'experience, move, 招式經驗, $verdict',
        memoryType: 'experience',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 招式刪除時同步移除記憶（避免 Agent 檢索到已刪招式）
  /// [Blue 令 2026-09-12] 誠實同步——記憶裡不留指向虛空的手
  Future<bool> onMoveDeleted(SavedRoutine move) async {
    try {
      final db = BrainDatabase.instance.db;
      db.execute(
          "UPDATE agent_memories SET is_archived = 1 WHERE title LIKE ?",
          ['招式：${move.name}%']);
      db.execute(
          "UPDATE agent_memories SET is_archived = 1 WHERE title LIKE ?",
          ['經驗：使出「${move.name}%']);
      return true;
    } catch (_) {
      return false;
    }
  }
}
