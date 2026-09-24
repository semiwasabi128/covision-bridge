// [教練 Agent Sprint 17 Step 5 — 2026-07-07]
// 空對話狀態 widget：首次引導卡 + 快捷按鈕。
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../services/companion_runtime_store.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 空對話狀態：顯示首次引導卡或快捷按鈕。
class EmptyChatState extends StatelessWidget {
  /// 點擊快捷按鈕時的 callback，參數為 prompt 文字。
  final void Function(String prompt) onQuickPromptTap;

  /// 點擊 first action CTA 時的 callback。
  final void Function(String prompt) onApplyFirstAction;

  const EmptyChatState({
    super.key,
    required this.onQuickPromptTap,
    required this.onApplyFirstAction,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: CompanionRuntimeStore.instance.state,
      builder: (context, runtime, _) {
        final firstAction = runtime.firstAction;
        if (firstAction == null) {
          // [以利沙 P0 首次引導卡 2026-06-26]
          // [以利沙 P1 修復十輪 2026-06-27] 更新 chip 文案以觸發 capability gap
          final quickPrompts = [
            '設提醒',
            '搜最新消息',
            '寫文案、企劃書、報告書',
          ];
          // [教練 Agent 2026-07-01] 角色浮層在右下，空狀態內容靠左+上偏，避免被遮擋
          return Align(
            alignment: const Alignment(-0.6, -0.35),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chat, size: 48, color: BridgeDS.grey600),
                    const SizedBox(height: 12),
                    const Text(
                      '開始你的第一個對話',
                      style: TextStyle(color: BridgeDS.grey600),
                    ),
                    const SizedBox(height: 24),
                    // 引導卡 — IntrinsicWidth 確保只包內容，不撐滿
                    IntrinsicWidth(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusLarge),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '需要我幫您做什麼？',
                              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                height: 1.4,),
                            ),
                            const SizedBox(height: 10),
                            // [教練 Agent 2026-07-01] 三按鈕：第一行兩個各佔一半，第三行跨滿
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              spacing: 6,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: _QuickPromptButton(
                                        prompt: quickPrompts[0],
                                        onTap: () =>
                                            onQuickPromptTap(quickPrompts[0]),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _QuickPromptButton(
                                        prompt: quickPrompts[1],
                                        onTap: () =>
                                            onQuickPromptTap(quickPrompts[1]),
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  width: double.infinity,
                                  child: _QuickPromptButton(
                                    prompt: quickPrompts[2],
                                    onTap: () =>
                                        onQuickPromptTap(quickPrompts[2]),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.28),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.auto_awesome,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                runtime.activeCompanionName,
                                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w700,),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                runtime.statusText,
                                style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w800,),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      firstAction.title,
                      style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      firstAction.detail,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        height: 1.55,),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.background.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusMedium,
                        ),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Text(
                        firstAction.prompt,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textPrimary,
                          height: 1.5,),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () =>
                              onApplyFirstAction(firstAction.prompt),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(firstAction.ctaLabel),
                        ),
                        const SizedBox(width: 10),
                        TextButton.icon(
                          onPressed: () =>
                              CompanionRuntimeStore.instance.clearFirstAction(),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('先自己聊'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 快捷按鈕 chip。
class _QuickPromptButton extends StatelessWidget {
  final String prompt;
  final VoidCallback onTap;

  const _QuickPromptButton({required this.prompt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(
        prompt,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.primary,),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
      side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.30)),
      onPressed: onTap,
    );
  }
}
