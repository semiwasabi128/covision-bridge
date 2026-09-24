/// 🥋 招式工具 [Blue 拍板 2026-09-12]
///
/// 「可以在聊天對話中忽然讓 agent 執行某個腳本嗎？」——可以。
/// 招式＝訓練AI夥伴錄製的操作序列（全電腦代操作）。
///
/// 兩個工具：
///   use_move   —— 使出招式（重播；含 gate 圍欄與 Esc 急停）
///   list_moves —— 列出夥伴會的招式（Agent 自己查菜單）

import '../agent_tool.dart';
import '../../routines/system_routine_store.dart';
import '../../routines/system_routine_player.dart';
import '../../routines/move_memory_bridge.dart';

class UseMoveTool extends AgentTool {
  @override
  String get name => 'use_move';

  @override
  String get description =>
      '使出招式：重播使用者訓練AI夥伴錄製的操作序列（全電腦代操作）。'
      '適用場景：使用者說「用OO那招」「照之前錄的做」「把發票處理一下」'
      '且招式庫有對應招式時。執行前先跟使用者確認（招式會真的動電腦）；'
      '執行中使用者按住 Esc 1.5 秒可隨時急停。若使用者意圖與單一招式'
      '不完全匹配，先問清楚最終目標——可能需要組合多個招式。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        AgentToolParamSpec(
          name: 'move_name',
          description: '招式名稱（模糊匹配，例如「發票」匹配「發票歸檔」）',
          required: true,
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final moveName = args['move_name']?.toString() ?? '';
    if (moveName.isEmpty) {
      return AgentToolResult.failure('move_name 參數為空');
    }
    final routines = await SystemRoutineStore.instance.list();
    if (routines.isEmpty) {
      return AgentToolResult.failure(
          '招式庫是空的——使用者還沒用「訓練AI夥伴」錄過任何招式。'
          '請引導使用者到首頁 > 訓練AI夥伴錄製。');
    }
    final move = routines
        .where((r) => r.name.contains(moveName) || moveName.contains(r.name))
        .firstOrNull;
    if (move == null) {
      final names = routines.map((r) => r.name).join('、');
      return AgentToolResult.failure(
          '找不到招式「$moveName」。目前招式庫：$names。');
    }
    final res = await SystemRoutinePlayer.instance.replay(move.events);
    // [Blue 令] 自傳記憶——使出結果變成夥伴的經歷（經驗成長）
    await MoveMemoryBridge.instance.onMoveReplayed(
        move: move, played: res.played, skipped: res.skipped);
    return AgentToolResult.success(
      '招式「${move.name}」執行完成：${res.played} 步執行、'
      '${res.skipped} 步跳過。',
    );
  }
}

class ListMovesTool extends AgentTool {
  @override
  String get name => 'list_moves';

  @override
  String get description =>
      '列出夥伴會的所有招式（訓練AI夥伴錄製的操作序列）。'
      '在使用者提到「那招」「之前錄的」「訓練」但名稱不明確時先查這個。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final routines = await SystemRoutineStore.instance.list();
    if (routines.isEmpty) {
      return AgentToolResult.success(
          '招式庫是空的（使用者尚未訓練任何招式）。');
    }
    final lines = routines
        .map((r) => '· ${r.name}（${r.stepCount} 步，'
            '錄於 ${r.recordedAt.month}/${r.recordedAt.day}）')
        .join('\n');
    return AgentToolResult.success('夥伴會的招式：\n$lines');
  }
}
