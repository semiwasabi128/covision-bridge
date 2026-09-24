// trio_m3_meeting_test.dart
// [TRIO M3 2026-09-22] 會議層驗收——假 runner 鎖引擎邏輯（不燒 token）
//
// 劇本：
//   MT1 完整會議流程：回報×3 → 挑戰×1（輪替）→ 情報處置 → 決議解析
//   MT2 紅隊輪替：兩場會議挑戰者不同
//   MT3 一人失聲不開天窗——會議照常完成
//   MT4 決議派工：RESOLUTION| 行 → TaskSession（派工出口）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/collab/meeting_layer.dart';
import 'package:bridge_app/services/collab/intel_pool.dart';
import 'package:bridge_app/services/collab/agent_status_store.dart';

void main() {
  setUp(() {
    TrioMeetingEngine.resetForTest();
    IntelPool.resetForTest();
    AgentStatusStore.resetForTest();
  });

  TrioMeetingEngine _wiredEngine({
    String failAgent = '___none___',
    List<String> moderatorLines = const ['RESOLUTION|agent-乙|整理情報池文件'],
  }) {
    final engine = TrioMeetingEngine.instance;
    engine.speakerRunner = (agentId, prompt) async {
      if (agentId == failAgent) throw Exception('模擬失聲');
      // 從 prompt 判斷階段，回應制式發言
      if (prompt.contains('第一段')) return '$agentId 回報：本週完成兩件事。';
      if (prompt.contains('第二段')) return '$agentId 挑戰：說做好但沒驗證。';
      if (prompt.contains('第三段')) return '$agentId 裁決：全數採納。';
      return '$agentId 發言';
    };
    engine.moderatorRunner = (transcript) async {
      return moderatorLines.join('\n');
    };
    return engine;
  }

  test('MT1 完整會議——四段議程走完、決議解析', () async {
    final engine = _wiredEngine();
    final m = await engine.hold(
      attendeeIds: ['agent-甲', 'agent-乙', 'agent-丙'],
      conversationId: 'conv-test',
    );

    // 三人回報 + 一人挑戰
    expect(
        m.turns.where((t) => t.phase == MeetingPhase.report).length, 3);
    expect(
        m.turns.where((t) => t.phase == MeetingPhase.challenge).length, 1);
    // 情報池空 → 情報段跳過（0 輪）
    expect(m.turns.where((t) => t.phase == MeetingPhase.intel).length, 0);
    // 決議解析
    expect(m.resolutions.length, 1);
    expect(m.resolutions.first.assigneeId, 'agent-乙');
    expect(m.resolutions.first.text, contains('情報池'));
  });

  test('MT2 紅隊輪替——兩場會議挑戰者不同', () async {
    final engine = _wiredEngine();
    final m1 = await engine.hold(
      attendeeIds: ['agent-甲', 'agent-乙', 'agent-丙'],
      conversationId: 'c',
    );
    final m2 = await engine.hold(
      attendeeIds: ['agent-甲', 'agent-乙', 'agent-丙'],
      conversationId: 'c',
    );
    expect(m1.challengerId, isNot(equals(m2.challengerId)),
        reason: '輪替制——不固化同一人當挑戰者');
  });

  test('MT3 一人失聲不開天窗', () async {
    final engine = _wiredEngine(failAgent: 'agent-丙');
    final m = await engine.hold(
      attendeeIds: ['agent-甲', 'agent-乙', 'agent-丙'],
      conversationId: 'c',
    );
    // 丙失聲，甲乙照常——回報段仍有 2 輪
    expect(
        m.turns.where((t) => t.phase == MeetingPhase.report).length, 2);
    // 挑戰者若正好是丙也失聲——挑戰段 0 輪，會議仍完成
    expect(m.turns, isNotEmpty);
  });

  test('MT3b 失聲者挑戰段照樣失聲，情報段裁決照樣跳過', () async {
    final engine = _wiredEngine(failAgent: 'agent-丙');
    // 先種情報讓第三段有事做
    await IntelPool.instance.share(
        fromAgent: 'agent-甲',
        kind: IntelKind.pit,
        content: '測試坑');
    final m = await engine.hold(
      attendeeIds: ['agent-甲', 'agent-乙', 'agent-丙'],
      conversationId: 'c',
    );
    // 丙是第一場挑戰者（rotation=0 → attendees[0]=甲；rotation 每場+1）
    // 不論挑戰者是誰，會議都完成
    expect(m.id, isNotEmpty);
    // 會議後情報已全員消化
    final left = await IntelPool.instance.unconsumedBy('agent-乙');
    expect(left, isEmpty, reason: '會議攤開過=全員消化');
  });

  test('MT4 決議派工出口存在（RESOLUTION 解析無誤即可派）', () async {
    final engine = _wiredEngine();
    final m = await engine.hold(
      attendeeIds: ['agent-甲', 'agent-乙'],
      conversationId: 'c',
    );
    expect(m.resolutions.length, 1);
    expect(m.resolutions.first.taskId, isNull,
        reason: '尚未派工——dispatchResolutions 才回填');
  });
}
