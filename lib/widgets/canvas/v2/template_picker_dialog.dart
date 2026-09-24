// template_picker_dialog.dart
// 範本選擇對話框
// [教練 Agent 2026-07-22] Phase 5
//
// 在空畫布狀態下顯示，讓使用者選擇範本快速建立工作流。

import 'package:bridge_app/services/vault/vault_templates.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 範本選擇對話框
///
/// 顯示所有內建範本，點擊後回傳所選範本。
/// [刀 5 D5.5 2026-09-08] 自訂範本（示範錄製）置頂顯示——「我的示範」分類。
class TemplatePickerDialog extends StatefulWidget {
  const TemplatePickerDialog({super.key});

  @override
  State<TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<TemplatePickerDialog> {
  List<WorkflowTemplate> _custom = [];

  @override
  void initState() {
    super.initState();
    _loadCustom();
  }

  Future<void> _loadCustom() async {
    final custom = await VaultTemplateService.instance.getCustomTemplates();
    if (mounted) setState(() => _custom = custom);
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    final templates = VaultTemplateService.instance.getBuiltinTemplates();
    final categories = VaultTemplateService.instance.getCategories();

    return Dialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題
            Row(
              children: [
                Icon(Icons.dashboard_outlined,
                    size: 24, color: colors.accentPurple),
                const SizedBox(width: 12),
                Text(
                  '選擇工作流範本',
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                    color: colors.textPrimary,),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '從範本快速建立工作流，或雙擊畫布空白處從零開始',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: 24),

            // 依分類顯示
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // [刀 5 D5.5] 自訂範本置頂（示範錄製的範本）
                  if (_custom.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '我的示範',
                        style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                          color: colors.accentBlue,),
                      ),
                    ),
                    ..._custom.map((template) => _TemplateCard(
                          template: template,
                          colors: colors,
                          onTap: () =>
                              Navigator.of(context).pop(template),
                        )),
                    const SizedBox(height: 16),
                  ],
                  ...categories.map((category) {
                  final categoryTemplates = templates
                      .where((t) => t.category == category)
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 分類標題
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          category,
                          style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                            color: colors.accentPurple,),
                        ),
                      ),
                      // 範本卡片
                      ...categoryTemplates.map((template) =>
                          _TemplateCard(
                            template: template,
                            colors: colors,
                            onTap: () =>
                                Navigator.of(context).pop(template),
                          )),
                      const SizedBox(height: 16),
                    ],
                  );
                }).toList(),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final WorkflowTemplate template;
  final BridgeDSColors colors;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surfaceHover.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Row(
          children: [
            // 圖示
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.accentPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  template.icon,
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 標題 + 描述
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                      color: colors.textPrimary,),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    template.description,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // 節點數
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.borderSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${template.nodes.length} 節點',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
