// [教練 Agent Sprint 17 Step 2 2026-07-07]
// ChatMemoryHandler — 記憶/第二大腦回饋邏輯，從 chat_screen.dart _ChatScreenState 拆出。
//
// 職責：
//   1. 第二大腦記憶回饋（useful/irrelevant/pin/mute）
//   2. 記憶房間移動、撤回校正
//   3. 關聯回饋
//   4. 答案回饋（標記回答準確/不準確/先別採用）
//   5. 隱式回饋推斷（從使用者回覆文字推斷）
//   6. 記憶來源開啟/複製
//   7. 記憶 Dialog UI
//
// 設計：
// - 回饋追蹤狀態（_secondBrainMemoryFeedbacks 等）搬入 handler
// - flash UI 狀態透過 onFlash 回調通知 ChatScreen 做 setState
// - agentMotivation 透過回調更新
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/brain_container/memory_source.dart';
import '../../../models/chat_card_data.dart';
import '../../../models/companion.dart';
import '../../../models/conversation.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../models/second_brain_trace.dart';
import '../../../services/agent_motivation_engine.dart';
import '../../../services/brain_container/brain_container_service.dart';
import '../../../services/brain_progress_store.dart';
import '../../../services/conversation_store.dart';
import '../../../services/memory_store.dart';
import '../../../services/second_brain_file_index_store.dart';
import '../../../controllers/chat_controller.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/bridge_design_system.dart';
import '../../../widgets/transurfing_insight_library.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 記憶 Dialog 載入結果
class MemoryDialogData {
  final List<String> memories;
  final List<TransurfingInsightRecord> insightRecords;
  final BrainProgressSnapshot? progress;

  const MemoryDialogData({
    this.memories = const [],
    this.insightRecords = const [],
    this.progress,
  });
}

typedef MemoryFlashCallback = void Function({
  String? flashText,
  required bool showFlash,
  required bool brainPulse,
  AgentMotivationSnapshot? motivation,
});

/// 第二大腦回饋狀態變更回調（讓 ChatScreen 同步 message bubble 的回饋標記）
typedef FeedbackStateCallback = void Function();

class ChatMemoryHandler {
  ChatMemoryHandler({
    required AgentMotivationEngine motivationEngine,
    required SecondBrainFileIndexStore fileIndexStore,
    required ChatController controller,
    required Companion? Function() activeCompanionGetter,
    required Conversation? Function() currentConversationGetter,
    required void Function(Conversation) onConversationUpdated,
    required MemoryFlashCallback onFlash,
    required FeedbackStateCallback onFeedbackStateChanged,
    required void Function(String) onError,
  })  : _engine = motivationEngine,
        _fileIndexStore = fileIndexStore,
        _controller = controller,
        _getActiveCompanion = activeCompanionGetter,
        _getCurrentConversation = currentConversationGetter,
        _onConversationUpdated = onConversationUpdated,
        _onFlash = onFlash,
        _onFeedbackStateChanged = onFeedbackStateChanged,
        _onError = onError;

  final AgentMotivationEngine _engine;
  final SecondBrainFileIndexStore _fileIndexStore;
  final ChatController _controller;
  final Companion? Function() _getActiveCompanion;
  final Conversation? Function() _getCurrentConversation;
  final void Function(Conversation) _onConversationUpdated;
  final MemoryFlashCallback _onFlash;
  final FeedbackStateCallback _onFeedbackStateChanged;
  final void Function(String) _onError;

  // ── 回饋追蹤狀態（S18: 委派到 controller）──
  Map<String, SecondBrainMemoryFeedback> get secondBrainMemoryFeedbacks =>
      _controller.secondBrainMemoryFeedbacks;
  set secondBrainMemoryFeedbacks(Map<String, SecondBrainMemoryFeedback> value) =>
      _controller.secondBrainMemoryFeedbacks = value;

  Map<String, SecondBrainAssociationFeedback>
      get secondBrainAssociationFeedbacks =>
          _controller.secondBrainAssociationFeedbacks;
  set secondBrainAssociationFeedbacks(
          Map<String, SecondBrainAssociationFeedback> value) =>
      _controller.secondBrainAssociationFeedbacks = value;

  Map<String, SecondBrainRoom> get secondBrainMemoryRoomOverrides =>
      _controller.secondBrainMemoryRoomOverrides;
  set secondBrainMemoryRoomOverrides(Map<String, SecondBrainRoom> value) =>
      _controller.secondBrainMemoryRoomOverrides = value;

  List<String> get recalledBrainInsights => _controller.recalledBrainInsights;
  set recalledBrainInsights(List<String> value) =>
      _controller.recalledBrainInsights = value;

  Map<String, TransurfingInsightFeedback> get insightFeedbacks =>
      _controller.insightFeedbacks;
  set insightFeedbacks(Map<String, TransurfingInsightFeedback> value) =>
      _controller.insightFeedbacks = value;

  ProjectDoorCardData? get lastProjectDoorJudgement =>
      _controller.lastProjectDoorJudgement;
  set lastProjectDoorJudgement(ProjectDoorCardData? value) =>
      _controller.lastProjectDoorJudgement = value;

  // ── 共用 ──

  bool _containsAny(String text, List<String> needles) {
    for (final needle in needles) {
      if (text.contains(needle)) return true;
    }
    return false;
  }

  String _secondBrainMemoryFeedbackKey(SecondBrainMemoryTrace memory) {
    final source = memory.sourcePath?.trim().isNotEmpty == true
        ? memory.sourcePath!.trim()
        : memory.sourceLabel.trim();
    return '$source|${memory.content.trim()}';
  }

  Future<AgentMotivationChange?> applyInsightFeedback(
    String insight,
    TransurfingInsightFeedback feedback,
  ) async {
    return _engine.applyInsightFeedback(
      agentName: _getActiveCompanion()?.name,
      insight: insight,
      feedback: feedback,
    );
  }

  // ── flash helper ──

  void _triggerFlash({
    required String flashText,
    bool brainPulse = true,
    AgentMotivationSnapshot? motivation,
  }) {
    _onFlash(
      flashText: flashText,
      showFlash: true,
      brainPulse: brainPulse,
      motivation: motivation,
    );
  }

  // ── 隱式回饋 ──

  Future<void> applyImplicitRecalledInsightFeedback(String reply) async {
    final feedback = _inferRecalledInsightFeedback(reply);
    if (feedback == null || recalledBrainInsights.isEmpty) return;

    for (final insight in recalledBrainInsights.take(3)) {
      if (insightFeedbacks[insight] == feedback) continue;
      await applyInsightFeedback(insight, feedback);
    }
  }

  Future<void> applyImplicitProjectDoorJudgementFeedback(String reply) async {
    final card = lastProjectDoorJudgement;
    if (card == null) return;
    final feedback = _inferRecalledInsightFeedback(reply);
    if (feedback == null) return;

    final signal =
        '專案門判斷｜${card.title}｜${card.sourceIntent}｜信心 ${(card.confidence * 100).round()}%';
    final progressChange = await applyInsightFeedback(signal, feedback);
    final motivation = await _engine.getSnapshot(
      _getActiveCompanion()?.name,
    );

    if (feedback == TransurfingInsightFeedback.muted) {
      lastProjectDoorJudgement = null;
    }
    _triggerFlash(
      flashText: switch (feedback) {
        TransurfingInsightFeedback.accurate =>
          '專案門判斷 +${progressChange?.brainProgressChange?.awardedXp ?? 0} XP：這次分流被確認',
        TransurfingInsightFeedback.inaccurate => '專案門判斷已校正：下次會更保守',
        TransurfingInsightFeedback.muted => '專案門判斷已收斂：先別沿用這次分流',
      },
      motivation: motivation,
    );
  }

  TransurfingInsightFeedback? _inferRecalledInsightFeedback(String reply) {
    final normalized = reply.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    const muteSignals = [
      '完全不對', '整個不對', '根本不對', '不是我的意思',
      '先別用', '不要再引用', '不要用', '別採用', '胡說', '亂講', '離題',
    ];
    const inaccurateSignals = [
      '不太對', '有點不對', '不是很準', '不準', '我懷疑',
      '有疑問', '怪怪的', '可能不是', '不確定', '再想想',
    ];
    const accurateSignals = [
      '沒錯', '正確', '準確', '很準', '合理',
      '同意', '就是這樣', '對的', '很好', '太好了', '我喜歡',
    ];

    if (_containsAny(normalized, muteSignals)) {
      return TransurfingInsightFeedback.muted;
    }
    if (_containsAny(normalized, inaccurateSignals)) {
      return TransurfingInsightFeedback.inaccurate;
    }
    if (_containsAny(normalized, accurateSignals)) {
      return TransurfingInsightFeedback.accurate;
    }
    return null;
  }

  // ── 第二大腦記憶回饋 ──

  Future<void> markSecondBrainMemoryFeedback(
    SecondBrainMemoryTrace memory,
    SecondBrainMemoryFeedback feedback,
  ) async {
    final mappedFeedback = switch (feedback) {
      SecondBrainMemoryFeedback.useful => TransurfingInsightFeedback.accurate,
      SecondBrainMemoryFeedback.pin => TransurfingInsightFeedback.accurate,
      SecondBrainMemoryFeedback.irrelevant =>
        TransurfingInsightFeedback.inaccurate,
      SecondBrainMemoryFeedback.mute => TransurfingInsightFeedback.muted,
    };
    final signal =
        '${memory.sourceLabel}｜${memory.content}｜第二大腦回饋：${feedback.label}';
    final progressChange = await applyInsightFeedback(signal, mappedFeedback);
    await _fileIndexStore.applyMemoryFeedback(memory, feedback);
    final motivation = await _engine.getSnapshot(
      _getActiveCompanion()?.name,
    );

    secondBrainMemoryFeedbacks = {
      ...secondBrainMemoryFeedbacks,
      _secondBrainMemoryFeedbackKey(memory): feedback,
    };
    _onFeedbackStateChanged();

    _triggerFlash(
      flashText: _secondBrainFeedbackFlashText(feedback, progressChange),
      motivation: motivation,
    );
  }

  Future<void> moveSecondBrainMemoryRoom(
    SecondBrainMemoryTrace memory,
    SecondBrainRoom room,
  ) async {
    final signal =
        '${memory.sourceLabel}｜${memory.content}｜第二大腦房間校準：移到${room.zhLabel}';
    final progressChange = await applyInsightFeedback(
      signal,
      TransurfingInsightFeedback.inaccurate,
    );
    await _fileIndexStore.moveMemoryToRoom(memory, room);
    final motivation = await _engine.getSnapshot(
      _getActiveCompanion()?.name,
    );

    secondBrainMemoryRoomOverrides = {
      ...secondBrainMemoryRoomOverrides,
      _secondBrainMemoryFeedbackKey(memory): room,
    };
    _onFeedbackStateChanged();

    _triggerFlash(
      flashText:
          '這筆記憶已移到${room.zhLabel}${progressChange?.brainProgressChange == null ? '' : ' +${progressChange!.brainProgressChange!.awardedXp} XP'}',
      motivation: motivation,
    );
  }

  Future<void> undoSecondBrainMemoryCorrection(
    SecondBrainMemoryTrace memory,
  ) async {
    await _fileIndexStore.clearMemoryCorrection(memory);

    final key = _secondBrainMemoryFeedbackKey(memory);
    secondBrainMemoryFeedbacks = {...secondBrainMemoryFeedbacks}..remove(key);
    secondBrainMemoryRoomOverrides = {...secondBrainMemoryRoomOverrides}
      ..remove(key);
    _onFeedbackStateChanged();

    _triggerFlash(
      flashText: '已撤回這筆記憶的本輪校正，下一次會回到中性檢索。',
    );
  }

  Future<void> markSecondBrainAssociationFeedback(
    String association,
    SecondBrainAssociationFeedback feedback,
  ) async {
    await MemoryStore.markSecondBrainAssociationFeedback(association, feedback);
    final mappedFeedback = switch (feedback) {
      SecondBrainAssociationFeedback.useful =>
        TransurfingInsightFeedback.accurate,
      SecondBrainAssociationFeedback.wrong =>
        TransurfingInsightFeedback.inaccurate,
    };
    final signal = '第二大腦關聯回饋：$association｜${feedback.label}';
    final progressChange = await applyInsightFeedback(signal, mappedFeedback);
    final motivation = await _engine.getSnapshot(
      _getActiveCompanion()?.name,
    );

    secondBrainAssociationFeedbacks = {
      ...secondBrainAssociationFeedbacks,
      association: feedback,
    };
    _onFeedbackStateChanged();

    _triggerFlash(
      flashText:
          _secondBrainAssociationFeedbackFlashText(feedback, progressChange),
      motivation: motivation,
    );
  }

  // ── 答案回饋 ──

  Future<void> markAnswerFeedback(
    Message message,
    TransurfingInsightFeedback feedback,
  ) async {
    final conv = _getCurrentConversation();
    if (conv == null) return;
    final index = conv.messages.indexWhere((item) => item.id == message.id);
    if (index < 0) return;

    final feedbackValue = switch (feedback) {
      TransurfingInsightFeedback.accurate => 'accurate',
      TransurfingInsightFeedback.inaccurate => 'inaccurate',
      TransurfingInsightFeedback.muted => 'muted',
    };
    final signal = '回答回饋｜${message.content}';
    final progressChange = await applyInsightFeedback(signal, feedback);
    final motivation = await _engine.getSnapshot(
      _getActiveCompanion()?.name,
    );

    final updatedMessages = List<Message>.of(conv.messages);
    final currentMetadata = Map<String, dynamic>.from(
      updatedMessages[index].metadata ?? const {},
    );
    currentMetadata['answerFeedback'] = feedbackValue;
    currentMetadata['answerFeedbackAt'] = DateTime.now().toIso8601String();
    updatedMessages[index] = updatedMessages[index].copyWith(
      metadata: currentMetadata,
    );
    final updatedConv = conv.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );
    await ConversationStore.save(updatedConv);
    _onConversationUpdated(updatedConv);

    _triggerFlash(
      flashText: _answerFeedbackFlashText(feedback, progressChange),
      motivation: motivation,
    );
  }

  // ── 記憶來源操作 ──

  Future<void> openSecondBrainMemorySource(
    SecondBrainMemoryTrace memory, {
    required BuildContext context,
  }) async {
    final path = memory.sourcePath?.trim();
    if (path == null || path.isEmpty) {
      _onError('這筆記憶沒有可開啟的來源路徑。');
      return;
    }
    if (path.startsWith('local://')) {
      _onError('這是本地記憶庫內部來源，目前可先複製路徑追蹤。');
      return;
    }
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: path));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已複製來源路徑')));
      return;
    }

    final target = File(path).existsSync() || Directory(path).existsSync()
        ? path
        : File(path).parent.path;
    try {
      final result = await Process.run('open', [target]);
      if (!context.mounted) return;
      if (result.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已開啟來源：${memory.sourceLabel}')));
      } else {
        _onError('開啟來源失敗，已找不到可開啟的位置。');
      }
    } catch (_) {
      _onError('開啟來源失敗，請改用複製路徑。');
    }
  }

  Future<void> copySecondBrainMemorySource(
    SecondBrainMemoryTrace memory, {
    required BuildContext context,
  }) async {
    final path = memory.sourcePath?.trim();
    if (path == null || path.isEmpty) {
      _onError('這筆記憶沒有可複製的來源路徑。');
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已複製來源路徑：${memory.sourceLabel}')));
  }

  // ── Flash text helpers ──

  String _answerFeedbackFlashText(
    TransurfingInsightFeedback feedback,
    AgentMotivationChange? motivationChange,
  ) {
    if (motivationChange?.didLevelUp == true) {
      return '${motivationChange!.after.agentName} Drive Lv ${motivationChange.after.driveLevel}';
    }
    final xpSuffix = motivationChange?.brainProgressChange == null
        ? ''
        : ' +${motivationChange!.brainProgressChange!.awardedXp} XP';
    return switch (feedback) {
      TransurfingInsightFeedback.accurate => '這輪回答已標記準確$xpSuffix',
      TransurfingInsightFeedback.inaccurate => '這輪回答已標記不準確，夥伴會修正判斷',
      TransurfingInsightFeedback.muted => '這輪回答已標記先別採用，夥伴會降低引用',
    };
  }

  String _secondBrainFeedbackFlashText(
    SecondBrainMemoryFeedback feedback,
    AgentMotivationChange? motivationChange,
  ) {
    if (motivationChange?.didLevelUp == true) {
      return '${motivationChange!.after.agentName} Drive Lv ${motivationChange.after.driveLevel}';
    }
    final xpSuffix = motivationChange?.brainProgressChange == null
        ? ''
        : ' +${motivationChange!.brainProgressChange!.awardedXp} XP';
    return switch (feedback) {
      SecondBrainMemoryFeedback.useful => '這筆記憶已標記有用$xpSuffix',
      SecondBrainMemoryFeedback.irrelevant => '這筆記憶已標記不相關，夥伴會修正調閱',
      SecondBrainMemoryFeedback.pin => '這筆記憶已標記之後常引用$xpSuffix',
      SecondBrainMemoryFeedback.mute => '這筆記憶已標記不要再引用',
    };
  }

  String _secondBrainAssociationFeedbackFlashText(
    SecondBrainAssociationFeedback feedback,
    AgentMotivationChange? motivationChange,
  ) {
    if (motivationChange?.didLevelUp == true) {
      return '${motivationChange!.after.agentName} Drive Lv ${motivationChange.after.driveLevel}';
    }
    final xpSuffix = motivationChange?.brainProgressChange == null
        ? ''
        : ' +${motivationChange!.brainProgressChange!.awardedXp} XP';
    return switch (feedback) {
      SecondBrainAssociationFeedback.useful => '這條記憶關聯已確認$xpSuffix',
      SecondBrainAssociationFeedback.wrong => '這條記憶關聯已校正，夥伴會降低誤連',
    };
  }

  // ── 記憶 Dialog ──

  Future<MemoryDialogData> loadMemoryDialogData() async {
    final memories = await MemoryStore.getAll();
    final insightRecords = await MemoryStore.getTransurfingInsightRecords();
    final progress = await BrainProgressStore.getSnapshot();
    return MemoryDialogData(
      memories: memories,
      insightRecords: insightRecords,
      progress: progress,
    );
  }

  void showMemoriesDialog(BuildContext context) {
    if (!context.mounted) return;
    final newMemoryController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return FutureBuilder<MemoryDialogData>(
            future: loadMemoryDialogData(),
            builder: (context, snapshot) {
              final data = snapshot.data ?? const MemoryDialogData();
              final memories = data.memories;
              final generalMemories = memories
                  .where((memory) => !memory.startsWith('Transurfing洞察：'))
                  .toList();

              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.75,
                minChildSize: 0.4,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: BridgeDS.textOnAccent,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 拖把手
                          Container(
                            margin: const EdgeInsets.only(top: 10, bottom: 6),
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: BridgeDSColors.of(context).borderSubtle,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          // 標題列
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            child: Row(
                              children: [
                                const Icon(Icons.psychology,
                                    color: BridgeDS.successGreen),
                                const SizedBox(width: 8),
                                Text(
                                  '長期記憶與洞察',
                                  style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                                    color: BridgeDSColors.of(context).textPrimary,),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          // 內容（可捲動）
                          Flexible(
                            child: SingleChildScrollView(
                              controller: scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 12, 20, 8),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  TransurfingInsightLibrary(
                                    records: data.insightRecords,
                                    progress: data.progress,
                                    onFeedback: (insight, feedback) async {
                                      await applyInsightFeedback(
                                          insight, feedback);
                                      setDialogState(() {});
                                    },
                                    onDelete: (insight) async {
                                      await MemoryStore.removeTransurfingInsight(
                                          insight);
                                      setDialogState(() {});
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    '一般記憶',
                                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                                      color: BridgeDSColors.of(context).textPrimary,),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: newMemoryController,
                                          decoration: const InputDecoration(
                                            hintText: '手動新增記憶...',
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.add_circle,
                                          color: BridgeDS.successGreen,
                                        ),
                                        onPressed: () async {
                                          final text = newMemoryController.text
                                              .trim();
                                          if (text.isNotEmpty) {
                                            await MemoryStore.add(text);
                                            await BrainContainerService.instance
                                                .writeMemory(
                                              content: text,
                                              agent: _getActiveCompanion()?.name ?? '手動新增',
                                              companionId: _getActiveCompanion()?.id ?? '',
                                              source: MemorySource.idea,
                                              speaker: MemorySpeaker.user, // [出處戳] 使用者手動新增
                                            );
                                            newMemoryController.clear();
                                            setDialogState(() {});
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(height: 1),
                                  if (generalMemories.isEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.symmetric(vertical: 22),
                                      child: Column(
                                        children: [
                                          Icon(
                                            Icons.lightbulb_outline,
                                            size: 42,
                                            color: BridgeDSColors.of(context).textMuted,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '還沒有一般記憶',
                                            style:
                                                TextStyle(color: BridgeDSColors.of(context).textMuted),
                                          ),
                                          SizedBox(height: 6),
                                          Text(
                                            'App 夥伴會自動記住你說的「我是...」「我喜歡...」或你說「記住：...」的內容',
                                            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    ...generalMemories.map((memory) {
                                      return ExpansionTile(
                                        dense: true,
                                        tilePadding: EdgeInsets.zero,
                                        leading: const Icon(
                                          Icons.favorite_border,
                                          size: 18,
                                        ),
                                        title: Text(
                                          memory,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              TierStyle.of(context, Tier.cardBody).toTextStyle(),
                                        ),
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                                left: 42,
                                                right: 8,
                                                bottom: 8),
                                            child: Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    memory,
                                                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme
                                                            .textSecondary),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                    color: BridgeDS.red500,
                                                  ),
                                                  onPressed: () async {
                                                    await MemoryStore.remove(
                                                        memory);
                                                    setDialogState(() {});
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                ],
                              ),
                            ),
                          ),
                          // 底部按鈕列
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('關閉'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
