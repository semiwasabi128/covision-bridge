import 'package:flutter/material.dart';
import '../core/responsive.dart';
import 'package:go_router/go_router.dart';

import '../models/agent_activity.dart';
import '../models/companion.dart';
import '../services/companion_store.dart';
import '../services/summon_readiness_service.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart'; // [教練 Agent 2026-08-05] Step 3 完整化 — dynamic color
import '../widgets/companion_avatar_image.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class FirstSummonScreen extends StatefulWidget {
  const FirstSummonScreen({super.key});

  @override
  State<FirstSummonScreen> createState() => _FirstSummonScreenState();
}

class _FirstSummonScreenState extends State<FirstSummonScreen> {
  late final Future<_FirstSummonSnapshot> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _load();
  }

  Future<_FirstSummonSnapshot> _load() async {
    await CompanionStore().init();
    final readiness = await SummonReadinessService().inspect();
    return _FirstSummonSnapshot(readiness: readiness);
  }

  @override
  Widget build(BuildContext context) {
    final companion = CompanionStore().activeCompanion;
    final hasCompanion = companion != null;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('第一次召喚'),
        backgroundColor: AppTheme.background,
        actions: [
          IconButton(
            tooltip: '夥伴館',
            icon: const Icon(Icons.groups_2_outlined),
            onPressed: () => context.go('/companions'),
          ),
          // [P1-1 修復 2026-06-30] 未完成夥伴創建前隱藏桌面入口
          if (hasCompanion)
            IconButton(
              tooltip: '桌面橋樑',
              icon: const Icon(Icons.desktop_windows_outlined),
              onPressed: () => context.go('/bridge-desktop'),
            ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_FirstSummonSnapshot>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            final companion = CompanionStore().activeCompanion;
            final hasCompanion = companion != null;
            final readiness = snapshot.data?.readiness;

            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = Responsive.isDesktop(context) ||
                  constraints.maxWidth >= 900;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppTheme.spacingM),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - AppTheme.spacingM * 2,
                    ),
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 5,
                                child: _SummonHero(companion: companion),
                              ),
                              const SizedBox(width: AppTheme.spacingL),
                              Expanded(
                                flex: 6,
                                child: _FirstSummonPanel(
                                  companion: companion,
                                  hasCompanion: hasCompanion,
                                  readiness: readiness,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _SummonHero(companion: companion),
                              const SizedBox(height: AppTheme.spacingM),
                              _FirstSummonPanel(
                                companion: companion,
                                hasCompanion: hasCompanion,
                                readiness: readiness,
                              ),
                            ],
                          ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _FirstSummonSnapshot {
  final SummonReadiness readiness;

  const _FirstSummonSnapshot({required this.readiness});
}

class _SummonHero extends StatelessWidget {
  final Companion? companion;

  const _SummonHero({required this.companion});

  @override
  Widget build(BuildContext context) {
    final companion = this.companion;
    final hasCompanion = companion != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      // [教練 Agent 2026-07-03] 背景從 teal 漸層改為米色，與夥伴館一致
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: AppTheme.primary, size: 15),
                const SizedBox(width: 7),
                Text(
                  '第一天的山門',
                  style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: AppTheme.primary,
                    fontWeight: FontWeight.w900,),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            hasCompanion ? '你的夥伴已經成形' : '先創造第一位夥伴',
            style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle().copyWith(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
              height: 1.08,),
          ),
          const SizedBox(height: 10),
          Text(
            hasCompanion
                ? '接下來讓手機與桌面打開第一座橋，讓夥伴可以跨裝置替你行動。'
                : '設定一位 AI 助理的名字和個性，之後就能在手機和電腦上跟他對話，讓他幫你處理事情。',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
              height: 1.5,
              fontWeight: FontWeight.w700,),
          ),
          const SizedBox(height: 24),
          Center(
            child: hasCompanion
                ? CompanionAvatarImage(
                    companion: companion,
                    mbtiCode: companion.mbtiCode,
                    seed: 0, // [教練 Agent 2026-08-04] appearanceSeed 已刪除
                    name: companion.name,
                    mood: AgentCompanionMood.proud,
                    action: AgentCompanionAction.bouncing,
                    size: 250,
                  )
                : CompanionAvatarImage(
                    companion: Companion(
                      id: 'first_summon_waiting',
                      name: '等待命名',
                      mbtiCode: 'ENFJ',
                      role: CompanionRole.general,
                    ),
                    mbtiCode: 'ENFJ',
                    seed: 42,
                    name: '等待命名',
                    mood: AgentCompanionMood.curious,
                    action: AgentCompanionAction.wandering,
                    size: 250,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CompanionReadyCard extends StatelessWidget {
  final Companion companion;

  const _CompanionReadyCard({required this.companion});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          CompanionAvatarImage(
            companion: companion,
            mbtiCode: companion.mbtiCode,
            seed: 0, // [教練 Agent 2026-08-04] appearanceSeed 已刪除
            name: companion.name,
            mood: AgentCompanionMood.proud,
            action: AgentCompanionAction.bouncing,
            size: 82,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  companion.name,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
                const SizedBox(height: 4),
                Text(
                  '${companion.mbtiCode} · ${companion.mbtiType?.name ?? '自訂'}型',
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstSummonPanel extends StatelessWidget {
  final Companion? companion;
  final bool hasCompanion;
  final SummonReadiness? readiness;

  const _FirstSummonPanel({
    required this.companion,
    required this.hasCompanion,
    required this.readiness,
  });

  @override
  Widget build(BuildContext context) {
    final summonReady = readiness?.ready ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepCard(
          index: '01',
          title: '確認生成能力',
          detail: hasCompanion
              ? '已完成。現在可以開始創造第一位夥伴了。'
              : readiness?.summary ?? '需要輸入 AI 服務的金鑰才能讓助理開口說話（就是讓 AI 運作的服務密碼，第一次設定只要 3 分鐘），點下方按鈕一步一步完成設定。',
          active: !hasCompanion && !summonReady,
          done: hasCompanion || summonReady,
          child: hasCompanion || summonReady
              ? _ReadinessReadyCard(readiness: readiness)
              : FilledButton.icon(
                  onPressed: () => context.go(
                    Uri(
                      path: '/system',
                      queryParameters: {'returnTo': '/first-summon'},
                    ).toString(),
                  ),
                  icon: const Icon(Icons.key_outlined),
                  label: Text(
                    (readiness?.brainReady == true && readiness?.imageReady == false)
                      ? '繼續設定圖片金鑰 ↓'
                      : (readiness?.actionLabel ?? '開始設定（約 3 分鐘）'),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          index: '02',
          title: '創造第一位夥伴',
          detail: hasCompanion
              ? '已完成。你可以直接進入第一次橋接，也可以回到夥伴館調整。'
              : summonReady
              ? '現在可以設定名字、個性、專長、說話風格、關係與造型方向，系統會自動生成夥伴形象。'
              : '先完成 API Key 與圖片生成能力設定，再創造第一位夥伴。',
          active: !hasCompanion && summonReady,
          done: hasCompanion,
          child: hasCompanion
              ? _CompanionReadyCard(companion: companion!)
              : FilledButton.icon(
                  onPressed: summonReady
                      ? () => context.go(
                            Uri(
                              path: '/companion/create',
                              queryParameters: {'returnTo': '/first-summon'}, // [以利沙 P1 修復十五輪 2026-06-27]
                            ).toString(),
                          )
                      : null,
                  icon: const Icon(Icons.auto_fix_high),
                  label: Text(summonReady ? '創造第一位夥伴' : '請先完成上方設定'), // [P1-3 修復 2026-06-30] disabled 文字簡化
                ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          index: '03',
          title: '確認造型與角色設定',
          detail: '定稿後會產生角色設定與狀態圖組，讓桌面夥伴能有表情與動作。',
          active: hasCompanion && (companion!.appearancePrompt.isEmpty),
          done: hasCompanion,
          child: OutlinedButton.icon(
            onPressed: hasCompanion ? () => context.go('/companions') : null,
            icon: const Icon(Icons.badge_outlined),
            label: const Text('查看夥伴館'),
          ),
        ),
        const SizedBox(height: 12),
        _StepCard(
          index: '04',
          title: '打開第一座橋',
          detail: hasCompanion
              ? '現在可以讓手機與桌面建立第一次跨裝置連接。'
              : '完成第一位夥伴後，才會進入手機與桌面的第一次連接。',
          active: hasCompanion,
          done: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: hasCompanion ? () => context.go('/bridge-pairing') : null,
                icon: const Icon(Icons.cable_outlined),
                label: const Text('開始跨裝置連接'),
              ),
              if (hasCompanion) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/chat'),
                  child: Text(
                    '我先試對話，明天再接桌面', // [P2-37 修復 2026-06-30] 語意更明確
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ReadinessReadyCard extends StatelessWidget {
  final SummonReadiness? readiness;

  const _ReadinessReadyCard({required this.readiness});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: AppTheme.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              readiness?.summary ?? '生成能力已準備好。',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1.35,),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String index;
  final String title;
  final String detail;
  final bool active;
  final bool done;
  final Widget child;

  const _StepCard({
    required this.index,
    required this.title,
    required this.detail,
    required this.active,
    required this.done,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? AppTheme.success
        : active
        ? AppTheme.primary
        : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: done
                    ? Icon(Icons.check_rounded, color: color, size: 20)
                    : Text(
                        index,
                        style: TierStyle.of(context, Tier.numericEmphasis).toTextStyle().copyWith(color: color,
                          fontWeight: FontWeight.w900,),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      detail,
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.textSecondary,
                        height: 1.42,
                        fontWeight: FontWeight.w700,),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
