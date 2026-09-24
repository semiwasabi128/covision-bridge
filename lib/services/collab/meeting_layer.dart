// meeting_layer.dart
// [TRIO M3 2026-09-22] 會議層——三 Agent 開會/檢討/互相挑戰/複盤/情報處置
//
// Blue 9/22 令：「他們三個要能開會要能檢討要能互相挑戰互相複盤互相分享情報」
//
// 設計（AGENT_TRIO_COLLAB_SPEC §三層三）：
//   會議 = 一種特殊的 TaskSession（不另建通道——三鐵則一的勝利）
//   議程固定四段：回報 → 挑戰（紅隊輪替）→ 情報處置 → 決議派工
//   決議直接變成新任務——會議不是聊天，是派工的前置
//
// 執行模式：sequenced AgentLoop 輪次——每個 agent 輪流以「與會者」身份
// 跑一輪 loop（看到議程+前一位的發言+情報池+自己的 ledger 摘要），
// 產出發言；主持人（腦）彙整成會議紀錄。全程走同一個 conversation。
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:bridge_app/services/collab/intel_pool.dart';
import 'package:bridge_app/services/collab/agent_status_store.dart';
import 'package:bridge_app/services/companion_store.dart';
import 'package:bridge_app/services/tasks/task_dispatcher.dart';

/// 一場會議
class TrioMeeting {
  final String id;
  final DateTime at;
  final List<String> attendeeIds;
  String? challengerId; // 本場紅隊挑戰者（輪替）
  final List<MeetingTurn> turns = [];
  final List<MeetingResolution> resolutions = [];

  TrioMeeting({required this.id, required this.attendeeIds})
      : at = DateTime.now();
}

/// 一輪發言
class MeetingTurn {
  final String agentId;
  final MeetingPhase phase;
  final String content;
  final DateTime at;
  MeetingTurn({
    required this.agentId,
    required this.phase,
    required this.content,
  }) : at = DateTime.now();
}

/// 決議（→ 透過 TaskDispatcher 變成新任務）
class MeetingResolution {
  final String text;
  final String? assigneeId; // null = 主持人（腦）自己帶
  String? taskId; // 派工後回填
  MeetingResolution({required this.text, this.assigneeId, this.taskId});
}

/// 議程四段
enum MeetingPhase { report, challenge, intel, resolve }

extension MeetingPhaseLabel on MeetingPhase {
  String get label => switch (this) {
        MeetingPhase.report => '回報',
        MeetingPhase.challenge => '挑戰',
        MeetingPhase.intel => '情報',
        MeetingPhase.resolve => '決議',
      };
}

/// 會議引擎（singleton——TaskDispatcher 同模式）
///
/// 引擎不直接呼叫 AgentLoop——靠 [speakerRunner] 注入（與 dispatcher 的
/// agentRunner 同注入模式）：controller 層把「以某夥伴身份跑一輪」接上來。
/// 這樣會議層保持純邏輯、可測試、不綁 UI。
class TrioMeetingEngine extends ChangeNotifier {
  TrioMeetingEngine._();
  static TrioMeetingEngine? _instance;
  static TrioMeetingEngine get instance =>
      _instance ??= TrioMeetingEngine._();

  @visibleForTesting
  static void resetForTest() => _instance = TrioMeetingEngine._();

  /// 與會者發言引擎——由 controller 注入：
  /// 以 agentId 的身份對 meetingPrompt 跑一輪 loop，回傳發言文字
  Future<String> Function(String agentId, String meetingPrompt)? speakerRunner;

  /// 主持人（腦）彙整引擎——由 controller 注入：
  /// 拿到全部發言，產出會議紀錄＋決議清單（JSON lines，方便解析）
  Future<String> Function(String transcript)? moderatorRunner;

  /// 紅隊輪替種子——每場會議挑戰者換人（公平輪替不固化）
  int _challengerRotation = 0;

  /// 舉行會議（sequenced——一次一人發言，不並行：會議本來就是輪流的）
  ///
  /// [attendeeIds] 與會者（預設全部夥伴）
  /// [conversationId] 會議 conversation（紀錄注入用）
  /// [agendaExtra] Blue 隨時加議題（自由輸入）
  Future<TrioMeeting> hold({
    List<String>? attendeeIds,
    required String conversationId,
    String? agendaExtra,
  }) async {
    final attendees = attendeeIds ??
        CompanionStore().all.map((c) => c.id).toList();
    if (attendees.length < 2) {
      throw StateError('會議至少需要兩位與會者（目前：$attendees）');
    }

    final meeting = TrioMeeting(
      id: 'meeting-${DateTime.now().millisecondsSinceEpoch}',
      attendeeIds: attendees,
    );

    // 紅隊輪替：本場挑戰者 = 依序輪
    meeting.challengerId =
        attendees[_challengerRotation % attendees.length];
    _challengerRotation++;

    final speak = speakerRunner;
    final moderate = moderatorRunner;
    if (speak == null || moderate == null) {
      throw StateError('會議引擎未接線——speakerRunner/moderatorRunner 未注入');
    }

    // ── 第一段：回報 ──
    for (final agentId in attendees) {
      final prompt = _reportPrompt(meeting, agentId);
      final speech = await _speakSafe(speak, agentId, prompt, meeting,
          MeetingPhase.report);
      if (speech != null) {
        meeting.turns.add(MeetingTurn(
            agentId: agentId, phase: MeetingPhase.report, content: speech));
        notifyListeners();
      }
    }

    // ── 第二段：挑戰（紅隊輪替）──
    final challenger = meeting.challengerId!;
    final reportTranscript = _transcriptOf(meeting, MeetingPhase.report);
    final challengePrompt = _challengePrompt(meeting, reportTranscript);
    final challengeSpeech = await _speakSafe(
        speak, challenger, challengePrompt, meeting, MeetingPhase.challenge);
    if (challengeSpeech != null) {
      meeting.turns.add(MeetingTurn(
          agentId: challenger,
          phase: MeetingPhase.challenge,
          content: challengeSpeech));
      notifyListeners();
    }

    // ── 第三段：情報處置 ──
    // 全體未消化情報一次攤開，逐條請挑戰者裁決（採納/歸檔/丟棄→refute）
    final allIntel = <IntelEntry>[];
    for (final a in attendees) {
      allIntel.addAll(await IntelPool.instance.unconsumedBy(a));
    }
    if (allIntel.isNotEmpty) {
      final intelPrompt = _intelPrompt(meeting, allIntel);
      final intelSpeech = await _speakSafe(
          speak, challenger, intelPrompt, meeting, MeetingPhase.intel);
      if (intelSpeech != null) {
        meeting.turns.add(MeetingTurn(
            agentId: challenger,
            phase: MeetingPhase.intel,
            content: intelSpeech));
        notifyListeners();
      }
      // 全員標記消化（會議上攤開過就算消化——會議本身就是情報處置場合）
      for (final e in allIntel) {
        for (final a in attendees) {
          await IntelPool.instance.markConsumed(e.id, a);
        }
      }
    }

    // ── 第四段：決議 ──
    final transcript = _fullTranscript(meeting);
    // minutes 同時解析進 meeting.resolutions（RESOLUTION| 行）
    // ignore: unused_local_variable
    final minutes = await _moderateSafe(moderate, transcript, meeting);

    notifyListeners();
    debugPrint('[TrioMeeting] ${meeting.id} 完成——${meeting.turns.length} '
        '輪發言，${meeting.resolutions.length} 項決議');
    return meeting;
  }

  /// 決議派工——會議的出口（決議變任務）
  Future<void> dispatchResolutions(
    TrioMeeting meeting, {
    required String conversationId,
  }) async {
    for (final r in meeting.resolutions) {
      if (r.assigneeId == null) continue; // 主持人自己帶的不派
      final session = await TaskDispatcher.instance.dispatch(
        conversationId: conversationId,
        companionId: r.assigneeId!,
        instruction: r.text,
        title: '〔會議決議〕${r.text.length > 18 ? r.text.substring(0, 18) : r.text}',
      );
      r.taskId = session.id;
    }
    notifyListeners();
  }

  // ── prompt 組裝 ──

  String _reportPrompt(TrioMeeting m, String agentId) {
    final name = _nameOf(agentId);
    return '''
你是 $name，正在參加團隊會議（${m.id}）。

## 第一段：回報（每人 30 秒）
請簡短回報：
1. 自上次會議以來你做了什麼（查你的對話與任務）
2. 遇到的坑（有的話用 intel_share 寫進情報池）
3. 進行中的事

誠實原則：不誇大、不假裝做過沒做的事。沒有就說沒有。
只輸出你的回報內容（不要工具呼叫以外的長篇大論）。
''';
  }

  String _challengePrompt(TrioMeeting m, String transcript) {
    final name = _nameOf(m.challengerId!);
    return '''
你是 $name，本場會議你是紅隊挑戰者（輪替制——這場輪到你）。

## 第二段：挑戰
以下是隊友的回報：

$transcript

你的職責（Blue 紅隊哲學）：
- 質疑含糊的宣稱（「做好了」——驗證過嗎？）
- 指出被忽略的風險
- 挑戰不合理的做法

要求：對事不對人，具體指出哪句話有問題、為什麼、建議怎麼改。
只輸出你的挑戰內容。
''';
  }

  String _intelPrompt(TrioMeeting m, List<IntelEntry> intel) {
    final name = _nameOf(m.challengerId!);
    final buf = StringBuffer();
    for (final e in intel) {
      buf.writeln('- ${e.id}［${e.kind.label}］${e.content}');
    }
    return '''
你是 $name（紅隊挑戰者，兼本場情報裁決）。

## 第三段：情報處置
情報池有 ${intel.length} 筆未消化情報：
$buf

逐條裁決：採納（進誰的任務）/ 歸檔（留著不動）/ 丟棄（用 intel_refute
標記——錯誤或過期）。給出理由。
''';
  }

  String _fullTranscript(TrioMeeting m) {
    final buf = StringBuffer();
    for (final t in m.turns) {
      buf.writeln('【${_nameOf(t.agentId)}·${t.phase.label}】');
      buf.writeln(t.content);
      buf.writeln();
    }
    return buf.toString();
  }

  Future<String?> _speakSafe(
    Future<String> Function(String, String) speak,
    String agentId,
    String prompt,
    TrioMeeting m,
    MeetingPhase phase,
  ) async {
    AgentStatusStore.instance.setLive(agentId,
        sessionId: m.id, detail: '會議${phase.label}');
    try {
      return await speak(agentId, prompt);
    } catch (e) {
      debugPrint('[TrioMeeting] $agentId ${phase.label} 發言失敗: $e');
      return null; // 一人失聲不開天窗——會議繼續
    } finally {
      AgentStatusStore.instance.setExited(agentId,
          sessionId: m.id, detail: '會議${phase.label}完成');
    }
    // 註：會議中 exited 是「發言結束」不是「死亡」——
    // 下一輪 setLive 會再亮。三態詞彙表仍成立（不在場）。
  }

  Future<String> _moderateSafe(
    Future<String> Function(String) moderate,
    String transcript,
    TrioMeeting m,
  ) async {
    final moderatorPrompt = '''
你是會議主持人（腦）。以下是團隊會議全程發言：

$transcript

## 第四段：決議
1. 彙整會議紀錄（三句話以內）
2. 列出決議——每項格式嚴格如下（一行一項，方便解析）：
RESOLUTION|執行者id或ME|決議內容
（執行者是與會者 id；主持人的事寫 ME；沒有決議就寫 NONE）
''';
    final raw = await moderate(moderatorPrompt);
    // 解析決議行
    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.startsWith('RESOLUTION|')) {
        final parts = t.split('|');
        if (parts.length >= 3) {
          final assignee = parts[1] == 'ME' ? null : parts[1];
          m.resolutions.add(MeetingResolution(
              text: parts.sublist(2).join('|'), assigneeId: assignee));
        }
      }
    }
    return raw;
  }

  String _nameOf(String agentId) {
    final c = CompanionStore().getById(agentId);
    return c?.name ?? agentId;
  }

  /// 某階段的發言逐字稿（挑戰段 prompt 用）
  String _transcriptOf(TrioMeeting m, MeetingPhase phase) {
    final buf = StringBuffer();
    for (final t in m.turns.where((t) => t.phase == phase)) {
      buf.writeln('【${_nameOf(t.agentId)}】');
      buf.writeln(t.content);
      buf.writeln();
    }
    return buf.toString();
  }
}
