// 橋樑 App — MBTI 靈魂選擇
// 設計風格：截圖3 - What is your companion's soul type?

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../models/companion.dart';
import '../services/companion_store.dart';
import '../services/appearance_generator.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

class CompanionSoulScreen extends StatefulWidget {
  final String companionId;
  final String? returnTo;
  final bool hideAppBar; // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏
  final VoidCallback? onBack; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式返回 callback
  final void Function(String page)? onNavigateTo; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式導航 callback

  const CompanionSoulScreen({
    super.key,
    required this.companionId,
    this.returnTo,
    this.hideAppBar = false,
    this.onBack,
    this.onNavigateTo,
  });

  @override
  State<CompanionSoulScreen> createState() => _CompanionSoulScreenState();
}

class _CompanionSoulScreenState extends State<CompanionSoulScreen> {
  Companion? _companion;
  MBTIType? _selectedMBTI;

  @override
  void initState() {
    super.initState();
    _loadCompanion();
  }

  void _loadCompanion() {
    final c = CompanionStore().getById(widget.companionId);
    if (c != null) {
      setState(() {
        _companion = c;
        _selectedMBTI = c.mbtiType ?? MBTIType.allTypes.first;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    if (_companion == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AdaptiveScaffold(
      backgroundColor: ds.canvas,
      // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏 AppBar（外層已加）
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  size: 28,
                ), // [P1-12 修復 2026-06-30] 統一 arrow_back+size:28
                onPressed: () {
                  // [教練 Agent 2026-08-04 Phase E+] 優先 callback → returnTo → pop → 預設
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (widget.returnTo != null) {
                    context.go(widget.returnTo!);
                  } else if (context.canPop()) {
                    // [小葵 2026-09-08] push 進來的返回就 pop 回原頁
                    context.pop();
                  } else {
                    context.go('/companion/control?id=${widget.companionId}');
                  }
                },
              ),
              title: const Text('選擇夥伴的靈魂類型'), // [P1-13 修復 2026-06-30] 英文改中文
              backgroundColor: ds.canvas,
            ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                child: Column(
                  children: [
                    // MBTI 網格
                    _buildMBTIGrid(),
                    const SizedBox(height: AppTheme.spacingL),

                    // 選中預覽
                    if (_selectedMBTI != null) _buildPreviewCard(),
                  ],
                ),
              ),
            ),

            // 底部按鈕
            if (_selectedMBTI != null)
              Padding(
                padding: const EdgeInsets.all(AppTheme.spacingM),
                child: _buildConfirmButton(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMBTIGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2, // [P1-11 修復 2026-06-30] 4列改2列，符合手機鐵則
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.4,
      children: MBTIType.allTypes.map((mbti) => _buildMBTICard(mbti)).toList(),
    );
  }

  Widget _buildMBTICard(MBTIType mbti) {
    final ds = BridgeDSColors.of(context);
    final isSelected = _selectedMBTI?.code == mbti.code;
    final color = Color(int.parse(mbti.colorHex.replaceFirst('#', '0xFF')));

    return GestureDetector(
      onTap: () => setState(() => _selectedMBTI = mbti),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: isSelected ? 0.9 : 0.7),
              color.withValues(alpha: isSelected ? 0.7 : 0.5),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: isSelected
              ? Border.all(color: ds.textPrimary, width: 3)
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              mbti.code,
              style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                color: ds.textPrimary,),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                mbti.nameEn,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard() {
    final ds = BridgeDSColors.of(context);
    final mbti = _selectedMBTI!;
    final color = Color(int.parse(mbti.colorHex.replaceFirst('#', '0xFF')));
    final generator = GeometricAppearanceGenerator();
    final svgString = generator.generatePreview(
      mbti,
      '',
      _companion!.appearanceSeed,
    );

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 形象預覽
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withValues(alpha: 0.6),
                      color.withValues(alpha: 0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: Image.network(
                    GeometricAppearanceGenerator.svgToBase64(svgString),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Center(
                      child: Text(
                        mbti.code.substring(0, 1),
                        style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                          color: ds.textPrimary,),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${mbti.code} — ${mbti.nameEn}',
                      style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                        color: ds.textPrimary,),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      mbti.description,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary,
                        height: 1.5,),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingM),
          const Divider(),
          const SizedBox(height: AppTheme.spacingS),
          Text(
            'Suggested Capabilities:',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
              color: ds.textPrimary,),
          ),
          const SizedBox(height: AppTheme.spacingS),
          ...mbti.traits.map(
            (trait) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    trait,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    final ds = BridgeDSColors.of(context);
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ds.accentBlue.withValues(alpha: 0.5),
            ds.accentBlue,
          ],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: [
          BoxShadow(
            color: ds.accentBlue.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          onTap: _onConfirm,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 20,
                  color: ds.textPrimary,
                ), // [P3-12 修復 2026-06-30] 加 icon 統一風格
                SizedBox(width: 8),
                Text(
                  '確認靈魂類型',
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                    color: ds.textPrimary,),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onConfirm() async {
    if (_selectedMBTI == null || _companion == null) return;

    final updated = _companion!.copyWith(mbtiCode: _selectedMBTI!.code);

    await CompanionStore().update(updated);
    if (!mounted) return;
    // [教練 Agent 2026-08-04 Phase E+] 內嵌模式用 callback 進 appearance
    if (widget.onNavigateTo != null) {
      widget.onNavigateTo!('appearance');
    } else {
      context.go('/companion/appearance?id=${updated.id}');
    }
  }
}
