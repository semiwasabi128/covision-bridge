// heart_mind_dialogue_card.dart
// Sprint 9 — 心腦合一對話獨立卡片
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 顯示邏輯：
// - idle：不顯示
// - offeringSplit：顯示引導句 + 「先聽心」/「先聽腦」按鈕
// - awaitingUser：顯示「正在整合…」
// - integrated/written：顯示整合 statement
// - 清晨確認：獨立區塊顯示昨晚整合 statement

import 'package:flutter/material.dart';

import '../../services/brain_pipeline/heart_mind/heart_mind_dialogue.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 心腦合一對話獨立卡片。
class HeartMindDialogueCard extends StatelessWidget {
  final HeartMindDialogue dialogue;

  /// 清晨確認句子（從 dialogue.getMorningAffirmation() 取得，由上層傳入）
  final String? morningAffirmation;

  /// 使用者點選「先聽心」/「先聽腦」時的回呼
  final void Function(String reply)? onUserReply;

  /// 使用者關閉對話時的回呼
  final VoidCallback? onDismiss;

  const HeartMindDialogueCard({
    super.key,
    required this.dialogue,
    this.morningAffirmation,
    this.onUserReply,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final session = dialogue.session;
    final state = dialogue.state;

    // 清晨確認（獨立於狀態機，只要有就顯示）
    final showMorning = morningAffirmation != null && state == HeartMindDialogueState.idle;

    // idle 且無清晨確認 → 不顯示
    if (state == HeartMindDialogueState.idle && !showMorning) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 清晨確認
        if (showMorning) _MorningAffirmationCard(text: morningAffirmation!),

        // 對話卡片
        if (state != HeartMindDialogueState.idle) ...[
          if (showMorning) const SizedBox(height: 6),
          _DialogueContent(
            session: session!,
            state: state,
            onUserReply: onUserReply,
            onDismiss: onDismiss,
          ),
        ],
      ],
    );
  }
}

/// 對話主內容。
class _DialogueContent extends StatelessWidget {
  final HeartMindSession session;
  final HeartMindDialogueState state;
  final void Function(String reply)? onUserReply;
  final VoidCallback? onDismiss;

  const _DialogueContent({
    required this.session,
    required this.state,
    this.onUserReply,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題列
          Row(
            children: [
              Icon(
                Icons.psychology_outlined,
                size: 14,
                color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text(
                '心腦合一',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                  color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.7),),
              ),
              const Spacer(),
              if (onDismiss != null)
                GestureDetector(
                  onTap: onDismiss,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: BridgeDSColors.of(context).textMuted.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),

          // 依狀態顯示不同內容
          if (state == HeartMindDialogueState.offeringSplit)
            _OfferingSplitContent(
              session: session,
              onUserReply: onUserReply,
            )
          else if (state == HeartMindDialogueState.awaitingUser)
            _AwaitingContent()
          else if (state == HeartMindDialogueState.integrated ||
              state == HeartMindDialogueState.written)
            _IntegratedContent(session: session),
        ],
      ),
    );
  }
}

/// offeringSplit：顯示分裂 + 引導句 + 選邊按鈕。
class _OfferingSplitContent extends StatelessWidget {
  final HeartMindSession session;
  final void Function(String reply)? onUserReply;

  const _OfferingSplitContent({required this.session, this.onUserReply});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 心 vs 腦
        if (session.heartStatement != null && session.heartStatement!.isNotEmpty) ...[
          Text(
            '心：${session.heartStatement}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.7),
              height: 1.4,),
          ),
          const SizedBox(height: 2),
        ],
        if (session.mindStatement != null && session.mindStatement!.isNotEmpty) ...[
          Text(
            '腦：${session.mindStatement}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.7),
              height: 1.4,),
          ),
          const SizedBox(height: 6),
        ],
        // 引導句
        if (session.integrationPrompt != null &&
            session.integrationPrompt!.isNotEmpty) ...[
          Text(
            session.integrationPrompt!,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              height: 1.4,),
          ),
          const SizedBox(height: 8),
        ],
        // 選邊按鈕
        Row(
          children: [
            _ReplyButton(
              label: '先聽心',
              color: BridgeDSColors.of(context).accentPurple,
              onTap: () => onUserReply?.call('先聽心'),
            ),
            const SizedBox(width: 6),
            _ReplyButton(
              label: '先聽腦',
              color: BridgeDSColors.of(context).accentBlue,
              onTap: () => onUserReply?.call('先聽腦'),
            ),
            const SizedBox(width: 6),
            _ReplyButton(
              label: '都聽',
              color: BridgeDSColors.of(context).accentPurple,
              onTap: () => onUserReply?.call('兩邊都聽'),
            ),
          ],
        ),
      ],
    );
  }
}

/// awaitingUser：正在整合。
class _AwaitingContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: BridgeDSColors.of(context).accentPurple,
          ),
        ),
        SizedBox(width: 8),
        Text(
          '正在整合…',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
        ),
      ],
    );
  }
}

/// integrated/written：顯示整合 statement。
class _IntegratedContent extends StatelessWidget {
  final HeartMindSession session;

  const _IntegratedContent({required this.session});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          session.integratedStatement ?? '',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w500,
            color: BridgeDSColors.of(context).textPrimary,
            height: 1.5,),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 12,
              color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 3),
            Text(
              '已寫入大腦容器',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.5),),
            ),
          ],
        ),
      ],
    );
  }
}

/// 清晨確認卡片。
class _MorningAffirmationCard extends StatelessWidget {
  final String text;

  const _MorningAffirmationCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.wb_sunny_outlined,
            size: 14,
            color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '今日清晨確認',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                    color: BridgeDSColors.of(context).accentYellow,),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                    height: 1.4,),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 選邊按鈕。
class _ReplyButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ReplyButton({
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w500,
            color: color,),
        ),
      ),
    );
  }
}
