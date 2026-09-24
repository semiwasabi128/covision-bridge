// task_progress_card.dart
// [隊友訊息流 第 1 刀 C3 2026-09-08]
// 進行中任務卡——訊息流末端的 sticky 卡。設計稿 §5：
// 收合態（預設，安靜原則）：夥伴頭像+任務標題+狀態燈+當前步驟一行
// 展開態：步驟時間軸（直播）+查看畫布+取消
//
// 設計原則：
// - 直播是旁觀不是控制（不中斷鐵則）——想介入走取消
// - widget 是觀察者：監聽 TaskDispatcher（ChangeNotifier），死了重來照樣顯示
// - BridgeDS tier 系統鎖樣式（禁寫死顏色）

import 'package:flutter/material.dart';
import 'package:bridge_app/services/tasks/task_dispatcher.dart';
import 'package:bridge_app/services/tasks/task_session.dart';
import 'package:bridge_app/services/conversation_store.dart'; // [刀 4] 對話流象限
import 'package:bridge_app/models/conversation.dart'; // [刀 4] Message
import 'package:bridge_app/services/budget_ledger.dart'; // [刀 4] 審計象限
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

class TaskProgressCard extends StatefulWidget {
  const TaskProgressCard({
    super.key,
    required this.session,
    required this.onViewCanvas,
    required this.onCancel,
  });

  final TaskSession session;

  /// 查看工作畫布（直播視圖第 2 層——跳 Tab 1 loadCanvasById）
  final void Function(String workCanvasId) onViewCanvas;

  final void Function(String sessionId) onCancel;

  @override
  State<TaskProgressCard> createState() => _TaskProgressCardState();
}

class _TaskProgressCardState extends State<TaskProgressCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    // 即時讀 dispatcher 記憶體態（widget.session 只是初始錨點）
    final live = TaskDispatcher.instance.activeSessions
        .firstWhere((s) => s.id == widget.session.id,
            orElse: () => widget.session);

    final latestStep = live.steps.isNotEmpty ? live.steps.last : null;

    return AnimatedBuilder(
      animation: TaskDispatcher.instance,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: ds.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: live.status == TaskStatus.working
                  ? ds.accentBlue
                  : ds.borderDefault,
              width: live.status == TaskStatus.working ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 收合列（永遠顯示）──
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      // 狀態燈
                      _StatusDot(status: live.status),
                      const SizedBox(width: 10),
                      // 標題（滿行）
                      Expanded(
                        child: Text(
                          live.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TierStyle.of(context, Tier.cardTitle)
                              .toTextStyle(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 當前步驟（收合也看得到——安靜但知情）
                      if (latestStep != null && !_expanded)
                        Flexible(
                          child: Text(
                            latestStep.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TierStyle.of(context, Tier.cardBody)
                                .toTextStyle()
                                .copyWith(color: ds.textMuted),
                          ),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 18,
                        color: ds.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
              // ── 展開：步驟直播 + 動作 ──
              if (_expanded) ...[
                const Divider(height: 1),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: live.steps.length,
                    itemBuilder: (context, i) {
                      final step = live.steps[i];
                      return _StepRow(step: step, isLatest: i == live.steps.length - 1);
                    },
                  ),
                ),
                const Divider(height: 1),
                // ── [刀 4] 房間視圖——一件工作的全部同屏共居 ──
                _buildRoomView(context, ds, live),
                const Divider(height: 1),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => widget.onViewCanvas(live.workCanvasId),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('查看畫布'),
                      ),
                      const Spacer(),
                      if (live.isActive)
                        TextButton.icon(
                          onPressed: () => widget.onCancel(live.id),
                          icon: Icon(Icons.stop_circle_outlined,
                              size: 16, color: ds.accentRed),
                          label: Text('取消',
                              style: TextStyle(color: ds.accentRed)),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
  /// [刀 4 D4.1] 房間視圖——2×2 四象限：對話流/畫布/產出物/審計同屏共居。
  /// 「人類看到的不是 N 個視窗，是一個房間裡的協作實況。」
  Widget _buildRoomView(BuildContext context, BridgeDSColors ds, TaskSession live) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🏠 房間',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle()),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _roomChatQuadrant(context, ds, live)),
              const SizedBox(width: 8),
              Expanded(child: _roomCanvasQuadrant(context, ds, live)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _roomDeliverablesQuadrant(context, ds, live)),
              const SizedBox(width: 8),
              Expanded(child: _roomAuditQuadrant(context, ds, live)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roomQuadrantShell(
    BuildContext context,
    BridgeDSColors ds, {
    required String label,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ds.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TierStyle.of(context, Tier.cardCaptionBold)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  /// 📝 對話流象限——該任務對話最近 3 則（D4.2）
  Widget _roomChatQuadrant(
      BuildContext context, BridgeDSColors ds, TaskSession live) {
    return _roomQuadrantShell(
      context,
      ds,
      label: '📝 對話流',
      child: FutureBuilder<List<Message>>(
        future: _fetchRecentMessages(live.conversationId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5));
          }
          final msgs = snap.data!;
          if (msgs.isEmpty) {
            return Text('尚無訊息',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textMuted));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final m in msgs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.role == 'user' ? 'Blue' : (m.speakerId != null ? '🤖' : '夥伴'),
                        style: TierStyle.of(context, Tier.cardCaptionBold)
                            .toTextStyle()
                            .copyWith(color: ds.accentBlue),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          m.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle(),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<List<Message>> _fetchRecentMessages(String conversationId) async {
    try {
      final conv = await ConversationStore.getById(conversationId);
      if (conv == null) return [];
      final msgs = conv.messages
          .where((m) => m.content.trim().isNotEmpty)
          .toList();
      if (msgs.length <= 3) return msgs;
      return msgs.sublist(msgs.length - 3);
    } catch (_) {
      return [];
    }
  }

  /// ▦ 畫布象限——工作畫布開啟卡（D4.3）
  Widget _roomCanvasQuadrant(
      BuildContext context, BridgeDSColors ds, TaskSession live) {
    return _roomQuadrantShell(
      context,
      ds,
      label: '▦ 工作畫布',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.dashboard_outlined,
                  size: 20, color: ds.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  live.workCanvasId.isEmpty ? '未建畫布' : '過程紀錄畫布',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (live.workCanvasId.isNotEmpty)
            SizedBox(
              height: 26,
              child: OutlinedButton(
                onPressed: () => widget.onViewCanvas(live.workCanvasId),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 26),
                ),
                child: Text('開啟',
                    style: TierStyle.of(context, Tier.cardCaptionBold)
                        .toTextStyle()),
              ),
            ),
        ],
      ),
    );
  }

  /// 📦 產出物象限——deliverables 縮圖列（D4.4）
  Widget _roomDeliverablesQuadrant(
      BuildContext context, BridgeDSColors ds, TaskSession live) {
    final items = live.deliverables;
    return _roomQuadrantShell(
      context,
      ds,
      label: '📦 產出物（${items.length}）',
      child: items.isEmpty
          ? Text(live.isActive ? '工作中，還沒有產出' : '無產出物',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted))
          : SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, i) {
                  final d = items[i];
                  final isImage = d.kind == 'image' && d.ref.isNotEmpty;
                  return Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: ds.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: ds.borderDefault),
                    ),
                    child: isImage
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Image.network(
                              d.ref,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                  color: ds.textMuted),
                            ),
                          )
                        : Icon(
                            d.kind == 'canvas'
                                ? Icons.dashboard_outlined
                                : Icons.description_outlined,
                            size: 18,
                            color: ds.textMuted,
                          ),
                  );
                },
              ),
            ),
    );
  }

  /// 🛡️ 審計象限——該夥伴的記帳統計＋小信任條（D4.5）
  Widget _roomAuditQuadrant(
      BuildContext context, BridgeDSColors ds, TaskSession live) {
    return _roomQuadrantShell(
      context,
      ds,
      label: '🛡️ 審計',
      child: FutureBuilder<({int total, int ok, int failed})>(
        future: BudgetLedger.instance.todayStats(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5));
          }
          final s = snap.data!;
          final rate = s.total == 0 ? 0.0 : s.ok / s.total;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('今日 ${s.total} 筆 · 成功 ${s.ok} · 失敗 ${s.failed}',
                  style: TierStyle.of(context, Tier.cardCaption).toTextStyle()),
              const SizedBox(height: 4),
              Stack(
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: ds.borderDefault,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: rate.clamp(0.0, 1.0),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: rate >= 0.8
                            ? ds.accentGreen
                            : (rate >= 0.5 ? ds.accentYellow : ds.accentRed),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 既有：步驟直播 ──
}

/// 狀態燈——working 呼吸動畫（有條件 AnimationController，08-20 教訓）
class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.status});
  final TaskStatus status;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _ensureAnim() {
    // 只有 working 才有動畫（條件式 repeat——GC 雪崩教訓）
    if (widget.status == TaskStatus.working && _ctrl == null) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200),
      )..repeat(reverse: true);
    } else if (widget.status != TaskStatus.working) {
      _ctrl?.dispose();
      _ctrl = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    _ensureAnim();

    final color = switch (widget.status) {
      TaskStatus.dispatched => ds.textMuted,
      TaskStatus.working => ds.accentBlue,
      TaskStatus.awaitingReview => ds.accentYellow,
      TaskStatus.delivered => ds.accentGreen,
      TaskStatus.failed => ds.accentRed,
      TaskStatus.cancelled => ds.textMuted,
    };

    if (_ctrl == null) {
      return Container(
          width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
    }
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
          CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut)),
      child: Container(
          width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    );
  }
}

/// 步驟列——直播時間軸的一格
class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isLatest});
  final TaskStep step;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final ts = TierStyle.of(context, Tier.cardBody).toTextStyle();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '${step.at.hour.toString().padLeft(2, '0')}:'
              '${step.at.minute.toString().padLeft(2, '0')}:'
              '${step.at.second.toString().padLeft(2, '0')}',
              style: ts.copyWith(color: ds.textMuted, fontSize: 11),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 110,
            child: Text(step.tool,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts.copyWith(
                    color: isLatest ? ds.accentBlue : ds.textMuted,
                    fontSize: 11)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              step.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ts.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
