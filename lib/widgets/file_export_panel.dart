// file_export_panel.dart
// AD-05 檔案管理面板 — 匯出 + 標籤管理
// Sprint 13-6
//
// 嵌入 master_folder_manager_screen 底部。
// 功能：
// 1. 一鍵匯出（大腦記憶 / 舊記憶 / 洞察 / 全部）
// 2. 標籤列表 + 建立/刪除

import 'package:bridge_app/models/master_folder.dart';
import 'package:bridge_app/services/file_export_service.dart';
import 'package:bridge_app/services/file_tag_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../theme/bridge_design_system.dart';

class FileExportPanel extends StatefulWidget {
  const FileExportPanel({super.key});

  @override
  State<FileExportPanel> createState() => _FileExportPanelState();
}

class _FileExportPanelState extends State<FileExportPanel> {
  final _exportService = FileExportService();
  final _tagStore = const FileTagStore();

  List<FileTag> _tags = [];
  bool _exporting = false;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await _tagStore.loadAll();
    if (mounted) setState(() => _tags = tags);
  }

  Future<void> _export(Future<ExportResult> Function() action, String label) async {
    setState(() {
      _exporting = true;
      _lastResult = null;
    });

    final result = await action();

    if (mounted) {
      setState(() {
        _exporting = false;
        _lastResult = result.success
            ? '✅ $label成功（${result.itemCount} 項）\n${result.filePath ?? ""}'
            : '❌ $label失敗：${result.error ?? "未知錯誤"}';
      });
      if (result.success) _loadTags();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 匯出區 ──
        _buildSectionHeader(Icons.file_download_outlined, '資料匯出'),
        const SizedBox(height: 8),
 Text(
   '把 App 內的對話、記憶、洞察匯出到檔案層（/專案/、/記憶庫/、/圖書館/）',
   style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
 ),
        const SizedBox(height: 12),

        if (_exporting)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _exportButton('大腦記憶', Icons.psychology_outlined, () {
                return _exportService.exportBrainMemories();
              }, '大腦記憶'),
              _exportButton('舊記憶', Icons.memory, () {
                return _exportService.exportLegacyMemories();
              }, '舊記憶'),
              _exportButton('洞察', Icons.lightbulb_outline, () {
                return _exportService.exportInsights();
              }, '洞察'),
              _exportButton('全部匯出', Icons.download_for_offline_outlined,
                  () async {
                final results = await _exportService.exportAll();
                final success = results.every((r) => r.success);
                final total = results.fold(0, (s, r) => s + r.itemCount);
                return ExportResult(
                  success: success,
                  itemCount: total,
                  filePath: results.where((r) => r.filePath != null).map((r) => r.filePath).join('\n'),
                );
              }, '全部匯出'),
            ],
          ),
        ],

        if (_lastResult != null) ...[
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _lastResult!.startsWith('✅')
                  ? BridgeDSColors.of(context).tagSuccessBg
                  : BridgeDSColors.of(context).tagErrorBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _lastResult!.startsWith('✅')
                    ? BridgeDSColors.of(context).tagSuccessBg.withValues(alpha: 0.6)
                    : BridgeDSColors.of(context).tagErrorBg.withValues(alpha: 0.6),
              ),
            ),
            child: Text(
              _lastResult!,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: _lastResult!.startsWith('✅')
                    ? BridgeDSColors.of(context).tagSuccessFg
                    : BridgeDSColors.of(context).tagErrorFg,),
            ),
          ),
        ],

        const SizedBox(height: 24),

        // ── 標籤管理 ──
        _buildSectionHeader(Icons.label_outline, '標籤管理'),
        const SizedBox(height: 8),

        if (_tags.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '尚未有標籤。匯出資料後會自動建立標籤。',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _tags.map((tag) => _buildTagChip(tag)).toList(),
          ),

        const SizedBox(height: 12),
        _buildCreateTagRow(),
      ],
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,),
        ),
      ],
    );
  }

  Widget _exportButton(
    String label,
    IconData icon,
    Future<ExportResult> Function() action,
    String resultLabel,
  ) {
    return ElevatedButton.icon(
      onPressed: _exporting ? null : () => _export(action, resultLabel),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 36),
      ),
    );
  }

  Widget _buildTagChip(FileTag tag) {
    return Chip(
      label: Text(
        '${tag.label} (${tag.filePaths.length})',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
      ),
      deleteIcon: const Icon(Icons.close, size: 16),
      onDeleted: () async {
        await _tagStore.deleteTag(tag.name);
        _loadTags();
      },
      backgroundColor: BridgeDSColors.of(context).tagInfoBg,
      side: BorderSide(color: BridgeDSColors.of(context).borderDefault),
      deleteIconColor: BridgeDSColors.of(context).tagErrorFg,
    );
  }

  Widget _buildCreateTagRow() {
    final controller = TextEditingController();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: '新標籤名稱',
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () async {
            final text = controller.text.trim();
            if (text.isEmpty) return;
            await _tagStore.createTag(text);
            controller.clear();
            _loadTags();
          },
          icon: const Icon(Icons.add_circle_outline),
          tooltip: '建立標籤',
        ),
      ],
    );
  }
}
