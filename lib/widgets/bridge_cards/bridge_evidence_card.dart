// [以利沙 Sprint 5 2026-06-24] 從 chat_screen.dart 抽出：橋樑證據卡（純顯示 widget）
// [以利沙 Sprint 6 2026-06-24] document export UI 已拆出至 DocumentExportCard
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/managed_folder_rule_store.dart';
import 'search_evidence_card.dart';
import 'document_export_card.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// [以利沙 Sprint 5 2026-06-24] 橋樑證據卡 — 純 StatelessWidget，不持有 service。
///
/// 接受 metadata 和所有必要的 callback，所有業務邏輯留在 chat_screen。
/// 當 kind == 'web_search' 時委派給 [SearchEvidenceCard]。
class BridgeEvidenceCard extends StatelessWidget {
  final Map<String, dynamic> metadata;
  final void Function(String) onCopy;
  final void Function(String) onOpenPath;

  // --- document 相關 ---
  /// 已完成的 workflow action keys（in-memory 狀態由 chat_screen 持有）。
  final Set<String> completedWorkflowActions;
  final void Function(Map<String, dynamic> action) onExecuteWorkflowAction;

  // --- desktop_file_plan 相關 ---
  final void Function(Map<String, dynamic> metadata, String applyPrompt)
      onRequestDesktopOrganizeConfirmation;
  final void Function(Map<String, dynamic> metadata) onExecuteDesktopPlanReport;
  final void Function(Map<String, dynamic> metadata) onExecuteDesktopPlanRules;
  final void Function(Map<String, dynamic> metadata)
      onImportDesktopOrganizeRules;
  /// 桌面整理計畫匹配到的受管資料夾規則（可為 null）。
  final ManagedFolderRule? managedFolderRule;

  // --- managed_folder_guard 相關 ---
  final void Function(BridgeGuardScanAction) onExecuteGuardScan;

  const BridgeEvidenceCard({
    super.key,
    required this.metadata,
    required this.onCopy,
    required this.onOpenPath,
    required this.completedWorkflowActions,
    required this.onExecuteWorkflowAction,
    required this.onRequestDesktopOrganizeConfirmation,
    required this.onExecuteDesktopPlanReport,
    required this.onExecuteDesktopPlanRules,
    required this.onImportDesktopOrganizeRules,
    this.managedFolderRule,
    required this.onExecuteGuardScan,
  });

  // [以利沙 Sprint 5 2026-06-24] 純函數：文件可交付格式摘要
  static String _documentExportSummary(Map<String, dynamic> metadata) {
    final paths = metadata['exportPaths'];
    if (paths is Map && paths.isNotEmpty) {
      return paths.keys.map((key) => key.toString()).join('、');
    }
    return metadata['format']?.toString() ?? 'Markdown';
  }

  // [以利沙 Sprint 5 2026-06-24] 純函數：桌面整理主要分類摘要
  static String _desktopCategorySummary(Map<String, dynamic> metadata) {
    final summary = metadata['categorySummary']?.toString().trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final counts = metadata['categoryCounts'];
    if (counts is! Map || counts.isEmpty) return '尚無分類';
    final entries = counts.entries
        .map((entry) => MapEntry(entry.key.toString(), entry.value))
        .where((entry) => entry.value is num)
        .toList()
          ..sort(
            (a, b) =>
                (b.value as num).toInt().compareTo((a.value as num).toInt()),
          );
    return entries
        .take(4)
        .map((entry) => '${entry.key} ${(entry.value as num).toInt()}')
        .join('、');
  }

  @override
  Widget build(BuildContext context) {
    final kind = metadata['kind']?.toString();
    // [以利沙 Sprint 5 2026-06-24] web_search 委派給 SearchEvidenceCard
    if (kind == 'web_search') {
      return SearchEvidenceCard(
        metadata: metadata,
        onCopy: onCopy,
        onOpenPath: onOpenPath,
      );
    }

    final rows = _buildRows(kind);
    if (rows.isEmpty) return const SizedBox.shrink();

    final title = _titleForKind(kind);
    final icon = _iconForKind(kind);

    return Container(
      width: kind == 'document' ? 560 : 430,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle().copyWith(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            _EvidenceLine(label: row.$1, value: row.$2),
          // [以利沙 Sprint 6 2026-06-24] 改用抽出的 DocumentExportCard widget
          if (kind == 'document')
            DocumentExportCard(
              metadata: metadata,
              completedWorkflowActions: completedWorkflowActions,
              onExecuteWorkflowAction: onExecuteWorkflowAction,
              onOpenPath: onOpenPath,
              onCopyText: onCopy,
            ),
          if (kind == 'desktop_file_plan') _buildDesktopPlanDetails(context, metadata),
          if (kind == 'managed_folder_guard')
            _buildManagedFolderGuardDetails(context, metadata),
        ],
      ),
    );
  }

  // [以利沙 Sprint 5 2026-06-24] 組 rows（純資料映射，不改邏輯）
  List<(String, String)> _buildRows(String? kind) {
    return switch (kind) {
      'vision' => [
        ('辨識目的', metadata['prompt']?.toString() ?? '描述圖片內容'),
        ('圖片來源', metadata['imageSource']?.toString() ?? '已附加圖片'),
        ('圖片數量', '${metadata['imageCount'] ?? 1} 張'),
        ('使用模型', metadata['model']?.toString() ?? '未標示'),
        ('執行橋', metadata['adapter']?.toString() ?? '圖片辨識橋'),
      ],
      'image' => [
        ('模型', metadata['model']?.toString() ?? '未標示'),
        ('品質', metadata['quality']?.toString() ?? '未標示'),
        ('模式', metadata['mode']?.toString() ?? '生成'),
        ('保存', metadata['storage']?.toString() ?? '已保存'),
      ],
      'document' => [
        ('文件標題', metadata['title']?.toString() ?? '橋樑文件'),
        ('文件類型', metadata['documentType']?.toString() ?? '文件'),
        ('格式', metadata['format']?.toString() ?? 'Markdown'),
        ('產出方式', metadata['generationMode']?.toString() ?? '文件產出'),
        ('使用服務', metadata['provider']?.toString() ?? '本機'),
        ('位置', metadata['path']?.toString() ?? '已附加'),
        ('可交付格式', _documentExportSummary(metadata)),
      ],
      'desktop_file_plan' => [
        ('任務', metadata['prompt']?.toString() ?? '桌面檔案整理'),
        ('掃描位置', metadata['rootPath']?.toString() ?? '等待授權'),
        (
          '檔案 / 資料夾',
          '${metadata['fileCount'] ?? 0} / ${metadata['folderCount'] ?? 0}',
        ),
        ('主要分類', _desktopCategorySummary(metadata)),
        if (metadata['executed'] == true) ...[
          ('已建立資料夾', '${metadata['createdFolderCount'] ?? 0} 個'),
          ('已移動檔案', '${metadata['movedCount'] ?? 0} 個'),
          if (metadata['recordPath'] != null)
            ('整理紀錄', metadata['recordPath'].toString()),
        ] else ...[
          ('預計建立資料夾', '${metadata['plannedFolderCount'] ?? 0} 個'),
          ('預計移動檔案', '${metadata['plannedMoveCount'] ?? 0} 個'),
          ('保留原處', '${metadata['skippedCount'] ?? 0} 個'),
        ],
        ('執行方式', metadata['readOnly'] == true ? '只讀掃描，等待你確認' : '已依確認執行'),
      ],
      'managed_folder_guard' => [
        ('受管資料夾', metadata['folderLabel']?.toString() ?? '資料夾'),
        ('位置', metadata['folderPath']?.toString() ?? '未標示'),
        ('套用規則', metadata['ruleTitle']?.toString() ?? '整理規則'),
        ('新檔案', '${metadata['newFileCount'] ?? 0} 個'),
        ('可能分類', metadata['categorySummary']?.toString() ?? '尚未分類'),
        ('觸發方式', metadata['trigger']?.toString() ?? '事件觸發'),
      ],
      'capability_gap' => [
        ('缺少能力', metadata['type']?.toString() ?? '橋樑能力'),
        ('建議入口', metadata['setupRoute']?.toString() ?? '/golden-keys'),
        if (metadata['provider'] != null)
          ('建議服務', metadata['provider'].toString()),
      ],
      _ => const <(String, String)>[],
    };
  }

  static String _titleForKind(String? kind) {
    return switch (kind) {
      'vision' => '圖片辨識證據',
      'image' => '圖片生成證據',
      'document' => '文件產出證據',
      'desktop_file_plan' => '桌面整理證據',
      'managed_folder_guard' => '受管資料夾守門',
      'capability_gap' => '能力缺口證據',
      _ => '橋樑證據',
    };
  }

  static IconData _iconForKind(String? kind) {
    return switch (kind) {
      'vision' => Icons.image_search_outlined,
      'image' => Icons.auto_awesome_outlined,
      'document' => Icons.description_outlined,
      'desktop_file_plan' => Icons.desktop_windows_outlined,
      'managed_folder_guard' => Icons.folder_special_outlined,
      'capability_gap' => Icons.vpn_key_outlined,
      _ => Icons.hub_outlined,
    };
  }

  // [以利沙 Sprint 6 2026-06-24] document export actions 已搬至 DocumentExportCard

  // === desktop_file_plan details ===

  Widget _buildDesktopPlanDetails(
    BuildContext context,
    Map<String, dynamic> metadata,
  ) {
    final executed = metadata['executed'] == true;
    final applyPrompt = metadata['applyPrompt']?.toString().trim();
    final recordPath = metadata['recordPath']?.toString().trim();
    final suggestions =
        (metadata['suggestions'] as List<dynamic>?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toList() ??
        const <String>[];
    final samples =
        (metadata['samples'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    final hasActions =
        (!executed && applyPrompt != null && applyPrompt.isNotEmpty) ||
        (recordPath != null && recordPath.isNotEmpty);
    if (suggestions.isEmpty && samples.isEmpty && !hasActions) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (suggestions.isNotEmpty) ...[
            Text(
              '整理建議',
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 4),
            for (final suggestion in suggestions.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: SelectableText(
                  '• $suggestion',
                  style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w700,),
                ),
              ),
          ],
          if (samples.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '樣本檔案',
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: samples.take(6).map((sample) {
                final name = sample['name']?.toString() ?? '檔案';
                final kind = sample['kind']?.toString() ?? '其他';
                final path = sample['path']?.toString() ?? '';
                return ActionChip(
                  avatar: const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 15,
                  ),
                  label: Text('$kind · $name'),
                  tooltip: path.isEmpty ? name : path,
                  onPressed: path.isEmpty ? null : () => onCopy(path),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 10),
          _buildDesktopPlanActionHint(context),
          _buildManagedFolderRuleStatus(context),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!executed && applyPrompt != null && applyPrompt.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => onRequestDesktopOrganizeConfirmation(
                    metadata,
                    applyPrompt,
                  ),
                  icon: const Icon(Icons.drive_file_move_outline, size: 17),
                  label: const Text('執行整理計畫'),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onExecuteDesktopPlanReport(metadata),
                      icon: const Icon(Icons.summarize_outlined, size: 17),
                      label: const Text('保存完整報告'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onExecuteDesktopPlanRules(metadata),
                      icon: const Icon(Icons.rule_folder_outlined, size: 17),
                      label: const Text('保存整理規則'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => onImportDesktopOrganizeRules(metadata),
                icon: const Icon(Icons.drive_folder_upload_outlined, size: 17),
                label: const Text('匯入已存整理規則'),
              ),
              if (recordPath != null && recordPath.isNotEmpty) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => onOpenPath(recordPath),
                  icon: const Icon(Icons.article_outlined, size: 17),
                  label: const Text('開啟整理紀錄'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopPlanActionHint(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHighlight.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.16)),
      ),
      child: SelectableText(
        '想換整理方式可以直接跟我說，例如「改成依日期整理」或「先把截圖跟安裝檔分開」。'
        '完整報告適合存檔閱讀；整理規則會登記成受管資料夾規則，方便下次重複使用。',
        style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,
          height: 1.35,
          fontWeight: FontWeight.w700,),
      ),
    );
  }

  Widget _buildManagedFolderRuleStatus(BuildContext context) {
    final rule = managedFolderRule;
    if (rule == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.verified_outlined,
            size: 18,
            color: AppTheme.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '受管資料夾規則已啟用',
                  style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.success,
                    fontWeight: FontWeight.w900,),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  '${rule.modeLabel}。規則：${rule.ruleTitle}',
                  style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,
                    height: 1.35,
                    fontWeight: FontWeight.w700,),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => onOpenPath(rule.rulePath),
            icon: const Icon(Icons.article_outlined, size: 15),
            label: const Text('開啟規則'),
          ),
        ],
      ),
    );
  }

  // === managed_folder_guard details ===

  Widget _buildManagedFolderGuardDetails(
    BuildContext context,
    Map<String, dynamic> metadata,
  ) {
    final samples =
        (metadata['samples'] as List<dynamic>?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    final scanPrompt = metadata['scanPrompt']?.toString().trim();
    final rulePath = metadata['rulePath']?.toString().trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (samples.isNotEmpty) ...[
            Text(
              '新增檔案樣本',
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: samples.take(8).map((sample) {
                final name = sample['name']?.toString() ?? '檔案';
                final kind = sample['kind']?.toString() ?? '其他';
                final path = sample['path']?.toString() ?? '';
                return ActionChip(
                  avatar: const Icon(Icons.note_add_outlined, size: 15),
                  label: Text('$kind · $name'),
                  tooltip: path.isEmpty ? name : path,
                  onPressed: path.isEmpty ? null : () => onCopy(path),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              border: Border.all(
                color: AppTheme.warning.withValues(alpha: 0.22),
              ),
            ),
            child: SelectableText(
              '守門器只偵測與提醒，不會自動搬移。按下產生整理計畫後，Bridge 仍會先只讀掃描，等你確認才會執行。',
              style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w700,),
            ),
          ),
          const SizedBox(height: 8),
          if (scanPrompt != null && scanPrompt.isNotEmpty)
            FilledButton.icon(
              onPressed: () => onExecuteGuardScan(
                BridgeGuardScanAction(prompt: scanPrompt),
              ),
              icon: const Icon(Icons.fact_check_outlined, size: 17),
              label: const Text('產生整理計畫'),
            ),
          if (rulePath != null && rulePath.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onOpenPath(rulePath),
              icon: const Icon(Icons.rule_folder_outlined, size: 17),
              label: const Text('開啟套用規則'),
            ),
          ],
        ],
      ),
    );
  }
}

/// [以利沙 Sprint 5 2026-06-24] 共用列元件（與 search_evidence_card 中的 _SearchEvidenceLine 相同結構，
/// 但因為 search_evidence_card 的 _SearchEvidenceLine 是私有，這裡獨立定義一份）。
class _EvidenceLine extends StatelessWidget {
  final String label;
  final String value;

  const _EvidenceLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textMuted,
                fontWeight: FontWeight.w800,),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w700,),
            ),
          ),
        ],
      ),
    );
  }
}

/// [以利沙 Sprint 5 2026-06-24] 受管資料夾守門掃描回調參數。
class BridgeGuardScanAction {
  final String prompt;
  const BridgeGuardScanAction({required this.prompt});
}
