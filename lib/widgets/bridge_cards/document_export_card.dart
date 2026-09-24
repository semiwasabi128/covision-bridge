// [以利沙 Sprint 6 2026-06-24] 從 bridge_evidence_card.dart 抽出：文件產出動作卡（純 StatelessWidget）
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// [以利沙 Sprint 6 2026-06-24] 文件產出動作卡 — 純 StatelessWidget，不持有 service。
///
/// 從 BridgeEvidenceCard 拆出，負責 document kind 的可開啟檔案、接續文件工作、
/// 社群插件接口三段 UI。所有業務邏輯留在 chat_screen，透過 callback 傳入。
///
/// 接受：
/// - [metadata]：訊息的 metadata map
/// - [completedWorkflowActions]：已完成的 workflow action keys（由 chat_screen 持有）
/// - [onExecuteWorkflowAction]：執行接續文件工作
/// - [onOpenPath]：開啟檔案路徑
/// - [onCopyText]：複製文字
class DocumentExportCard extends StatelessWidget {
  final Map<String, dynamic> metadata;
  final Set<String> completedWorkflowActions;
  final void Function(Map<String, dynamic> action) onExecuteWorkflowAction;
  final void Function(String) onOpenPath;
  final void Function(String) onCopyText;

  const DocumentExportCard({
    super.key,
    required this.metadata,
    required this.completedWorkflowActions,
    required this.onExecuteWorkflowAction,
    required this.onOpenPath,
    required this.onCopyText,
  });

  // [以利沙 Sprint 6 2026-06-24] 純函數：workflow action 去重 key
  static String documentWorkflowActionKey(Map<String, dynamic> action) {
    final label = action['label']?.toString().trim();
    final prompt = action['prompt']?.toString().trim();
    return [
      if (label != null && label.isNotEmpty) label,
      if (prompt != null && prompt.isNotEmpty) prompt,
    ].join('|');
  }

  // [以利沙 Sprint 6 2026-06-24] 純函數：從 metadata 取出 workflowActions
  static List<Map<String, dynamic>> documentWorkflowActions(
    Map<String, dynamic> metadata,
  ) {
    final raw = metadata['workflowActions'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['prompt']?.toString().trim().isNotEmpty == true)
        .toList();
  }

  // [以利沙 Sprint 6 2026-06-24] 純函數：從 metadata 取出 pluginInterfaces
  static List<Map<String, dynamic>> documentPluginInterfaces(
    Map<String, dynamic> metadata,
  ) {
    final raw = metadata['pluginInterfaces'];
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['label']?.toString().trim().isNotEmpty == true)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return _buildDocumentExportActions(context, metadata);
  }

  // [以利沙 Sprint 6 2026-06-24] 從 BridgeEvidenceCard 搬入，邏輯不變
  Widget _buildDocumentExportActions(
    BuildContext context,
    Map<String, dynamic> metadata,
  ) {
    final paths = metadata['exportPaths'];
    final workflowActions = documentWorkflowActions(metadata);
    final pluginInterfaces = documentPluginInterfaces(metadata);
    if ((paths is! Map || paths.isEmpty) &&
        workflowActions.isEmpty &&
        pluginInterfaces.isEmpty) {
      return const SizedBox.shrink();
    }
    final entries = paths is Map
        ? paths.entries
              .map(
                (entry) =>
                    MapEntry(entry.key.toString(), entry.value.toString()),
              )
              .where((entry) => entry.value.trim().isNotEmpty)
              .toList()
        : const <MapEntry<String, String>>[];

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entries.isNotEmpty)
            _buildDocumentActionDrawer(
              context: context,
              title: '可開啟檔案',
              subtitle: '${entries.length} 種格式，可開啟或複製路徑',
              icon: Icons.folder_open_outlined,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in entries)
                    ActionChip(
                      avatar: Icon(
                        entry.key.toLowerCase().contains('pdf')
                            ? Icons.picture_as_pdf_outlined
                            : entry.key.toLowerCase().contains('html')
                            ? Icons.web_asset_outlined
                            : Icons.description_outlined,
                        size: 15,
                      ),
                      label: Text('開啟 ${entry.key}'),
                      tooltip: entry.value,
                      onPressed: () => onOpenPath(entry.value),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('複製全部路徑'),
                    onPressed: () => onCopyText(
                      entries
                          .map((entry) => '${entry.key}：${entry.value}')
                          .join('\n'),
                    ),
                  ),
                ],
              ),
            ),
          if (workflowActions.isNotEmpty)
            _buildDocumentActionDrawer(
              context: context,
              title: '接續文件工作',
              subtitle: '補目錄、補摘要、另存版本等後續加工',
              icon: Icons.auto_fix_high_outlined,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in workflowActions)
                    _buildDocumentWorkflowChip(action, metadata),
                ],
              ),
            ),
          if (pluginInterfaces.isNotEmpty)
            _buildDocumentActionDrawer(
              context: context,
              title: '社群插件接口',
              subtitle: '預留給 DOCX、PPTX 等社群轉檔插件',
              icon: Icons.extension_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    '這裡是未來開源社群插件的出口標記；目前只告訴使用者這份文件具備轉成 Word / 簡報等格式的接口，正式插件接上後才會變成可執行按鈕。',
                    style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,
                      height: 1.4,),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in pluginInterfaces)
                        Tooltip(
                          message:
                              '${item['status'] ?? '接口已預留'}\n${item['note'] ?? ''}',
                          child: Chip(
                            avatar: const Icon(
                              Icons.extension_outlined,
                              size: 15,
                            ),
                            label: Text(item['label']?.toString() ?? '插件接口'),
                            backgroundColor: AppTheme.surfaceHighlight
                                .withValues(alpha: 0.55),
                            side: BorderSide(
                              color: AppTheme.primary.withValues(alpha: 0.18),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // [以利沙 Sprint 6 2026-06-24] 從 BridgeEvidenceCard 搬入，邏輯不變
  Widget _buildDocumentWorkflowChip(
    Map<String, dynamic> action,
    Map<String, dynamic> metadata,
  ) {
    final label = action['label']?.toString() ?? '接續處理';
    final actionKey = documentWorkflowActionKey(action);
    // 優先檢查 in-memory Set，其次讀取 metadata['completedWorkflowActions']
    final completedFromMetadata = () {
      final raw = metadata['completedWorkflowActions'];
      if (raw is! List) return false;
      return raw.any((item) => item?.toString() == actionKey);
    }();
    final completed =
        completedWorkflowActions.contains(actionKey) ||
        completedFromMetadata;
    return ActionChip(
      avatar: Icon(
        completed ? Icons.check_circle_outline : Icons.auto_fix_high_outlined,
        size: 15,
      ),
      label: Text(completed ? '已完成：$label' : label),
      tooltip: action['description']?.toString(),
      backgroundColor: completed
          ? AppTheme.success.withValues(alpha: 0.14)
          : null,
      side: BorderSide(
        color: completed
            ? AppTheme.success.withValues(alpha: 0.45)
            : AppTheme.primary.withValues(alpha: 0.22),
      ),
      onPressed: completed
          ? null
          : () => onExecuteWorkflowAction(action),
    );
  }

  // [以利沙 Sprint 6 2026-06-24] 從 BridgeEvidenceCard 搬入，邏輯不變
  Widget _buildDocumentActionDrawer({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHighlight.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.14)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          dense: true,
          initiallyExpanded: false,
          leading: Icon(icon, color: AppTheme.primary, size: 18),
          title: Text(
            title,
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.listItemMeta).toTextStyle().copyWith(color: AppTheme.textSecondary,),
          ),
          children: [Align(alignment: Alignment.centerLeft, child: child)],
        ),
      ),
    );
  }
}
