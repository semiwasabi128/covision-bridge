// [Sprint 13-8 — 桌面檔案管理頁面]
// DesktopFilePage：統一檔案管理入口，整合 4 大功能：
// 1. 檔案總管（既有 DesktopFileExplorer）
// 2. 主資料夾管理（1A+-6：資料夾清單+樹狀結構+啟用停用）
// 3. 標籤系統（1A+-5：標籤 CRUD + 檔案打標籤）
// 4. 匯出中心（1A+-7+1A+-4：對話/記憶/洞察匯出 + 快取搬移）
//
// 由桌面 screen 的「檔案」tab 呼叫。

import 'package:flutter/material.dart';

import '../../models/master_folder.dart';
import '../../services/file_export_service.dart';
import '../../services/file_layer_service.dart';
import '../../services/file_tag_store.dart';
import 'system_pages/restore_history_page.dart';
import '../../services/master_folder_store.dart';
import '../../theme/bridge_design_system.dart';
import '../../widgets/bridge_desktop_widgets.dart';
import '../../widgets/desktop_file_explorer.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class DesktopFilePage extends StatefulWidget {
  const DesktopFilePage({super.key});

  @override
  State<DesktopFilePage> createState() => _DesktopFilePageState();
}

class _DesktopFilePageState extends State<DesktopFilePage> {
  int _subTab = 0; // 0=總管, 1=主資料夾, 2=標籤, 3=匯出

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(BridgeDS.spaceLG),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 子頁切換 ──
          _buildSubNav(),
          const SizedBox(height: BridgeDS.spaceMD),
          // ── 內容 ──
          Expanded(
            child: switch (_subTab) {
              0 => const DesktopFileExplorer(),
              1 => const _MasterFolderTab(),
              2 => const _TagTab(),
              3 => const _ExportTab(),
              4 => const RestoreHistoryPage(),
              _ => const SizedBox(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSubNav() {
    final tabs = [
      ('檔案總管', Icons.folder_open),
      ('主資料夾', Icons.drive_folder_upload_outlined),
      ('標籤管理', Icons.label_outline),
      ('匯出中心', Icons.file_download_outlined),
      ('還原歷史', Icons.restore),
    ];
    return Row(
      children: [
        for (int i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _SubTabButton(
            label: tabs[i].$1,
            icon: tabs[i].$2,
            selected: _subTab == i,
            onTap: () => setState(() => _subTab = i),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// 子頁按鈕
// ═══════════════════════════════════════════════════════

class _SubTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  _SubTabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.12) : BridgeDSColors.of(context).surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(BridgeDS.roundStandard),
            topRight: Radius.circular(BridgeDS.roundStandard),
          ),
          border: Border(
            bottom: BorderSide(
              color: selected ? BridgeDSColors.of(context).accentBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textMuted),
            SizedBox(width: 6),
            Text(label,
                style: BridgeDSColors.of(context).small.copyWith(
                  fontSize: 14,
                  color: selected ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textMuted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 主資料夾管理 (1A+-6)
// ═══════════════════════════════════════════════════════

class _MasterFolderTab extends StatefulWidget {
  const _MasterFolderTab();

  @override
  State<_MasterFolderTab> createState() => _MasterFolderTabState();
}

class _MasterFolderTabState extends State<_MasterFolderTab> {
  final _store = const MasterFolderStore();
  final _fileLayer = const FileLayerService();
  List<MasterFolder> _folders = [];
  Map<String, MasterFolderTree> _trees = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folders = await _store.loadAll();
    final trees = <String, MasterFolderTree>{};
    for (final f in folders.where((f) => f.enabled)) {
      try {
        trees[f.id] = await _fileLayer.scanFolder(f);
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _folders = folders;
        _trees = trees;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 資料夾清單 ──
          Text('主資料夾 (${_folders.length})',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontSize: 16)),
          const SizedBox(height: 12),
          if (_folders.isEmpty)
            _emptyHint(context, '尚未設定主資料夾', '在設定頁面新增主資料夾路徑')
          else
            ..._folders.map((f) => _FolderCard(
                  folder: f,
                  tree: _trees[f.id],
                  onToggle: () async {
                    await _store.toggleEnabled(f.id);
                    _load();
                  },
                  onRescan: _load,
                )),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final MasterFolder folder;
  final MasterFolderTree? tree;
  final VoidCallback onToggle;
  final VoidCallback onRescan;
  _FolderCard({
    required this.folder,
    required this.tree,
    required this.onToggle,
    required this.onRescan,
  });

  @override
  Widget build(BuildContext context) {
    final fileCount = tree?.roots.fold(0, (sum, r) => sum + r.fileCount) ?? 0;

    return BridgeCard(
      child: Padding(
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(folder.enabled
                    ? Icons.folder_open
                    : Icons.folder_off_outlined,
                    size: 18,
                    color: folder.enabled ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).textMuted),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folder.label,
                          style: BridgeDSColors.of(context).small.copyWith(
                              color: BridgeDSColors.of(context).textPrimary, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(folder.path,
                          style: BridgeDSColors.of(context).small.copyWith(
                              fontSize: 14, color: BridgeDSColors.of(context).textMuted),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                if (folder.enabled)
                  Text('$fileCount 檔案',
                      style: BridgeDSColors.of(context).small.copyWith(
                          fontSize: 14, color: BridgeDSColors.of(context).textSecondary)),
                SizedBox(width: 8),
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (folder.enabled ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).textQuaternary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                    ),
                    child: Text(folder.enabled ? '啟用' : '停用',
                        style: BridgeDSColors.of(context).small.copyWith(
                            fontSize: 14,
                            color: folder.enabled ? BridgeDSColors.of(context).accentGreen : BridgeDSColors.of(context).textMuted)),
                  ),
                ),
              ],
            ),
            // ── 樹狀結構預覽 ──
            if (tree != null && tree!.roots.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...tree!.roots.map((r) => _TreePreviewNode(node: r, depth: 0)),
            ],
          ],
        ),
      ),
    );
  }
}

class _TreePreviewNode extends StatelessWidget {
  final TreeNode node;
  final int depth;
  _TreePreviewNode({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 16.0, top: 2, bottom: 2),
          child: Row(
            children: [
              Icon(node.isDirectory ? Icons.folder : Icons.insert_drive_file,
                  size: 12, color: BridgeDSColors.of(context).textMuted),
              SizedBox(width: 4),
              Text(node.name,
                  style: BridgeDSColors.of(context).small.copyWith(
                      fontSize: 14, color: BridgeDSColors.of(context).textSecondary),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (!node.isDirectory && node.sizeBytes > 0)
                Text(' ${_formatSize(node.sizeBytes)}',
                    style: BridgeDSColors.of(context).small.copyWith(
                        fontSize: 14, color: BridgeDSColors.of(context).textQuaternary)),
            ],
          ),
        ),
        ...node.children.map((c) => _TreePreviewNode(node: c, depth: depth + 1)),
      ],
    );
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
}

// ═══════════════════════════════════════════════════════
// 標籤管理 (1A+-5)
// ═══════════════════════════════════════════════════════

class _TagTab extends StatefulWidget {
  const _TagTab();

  @override
  State<_TagTab> createState() => _TagTabState();
}

class _TagTabState extends State<_TagTab> {
  final _tagStore = const FileTagStore();
  List<FileTag> _tags = [];
  bool _loading = true;
  final _newTagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tags = await _tagStore.loadAll();
    if (mounted) {
      setState(() {
        _tags = tags;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 新建標籤 ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newTagController,
                  style: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textPrimary),
                  decoration: InputDecoration(
                    hintText: '輸入標籤名稱…',
                    hintStyle: BridgeDSColors.of(context).small.copyWith(color: BridgeDSColors.of(context).textMuted),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                      borderSide: BorderSide(color: BridgeDSColors.of(context).borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                      borderSide: BorderSide(color: BridgeDSColors.of(context).accentBlue),
                    ),
                  ),
                  onSubmitted: (_) => _createTag(),
                ),
              ),
              const SizedBox(width: 8),
              BridgePillButton(
                label: '新增',
                icon: Icons.add,
                type: BridgeButtonType.accent,
                onPressed: _createTag,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── 標籤列表 ──
          Text('標籤列表 (${_tags.length})',
              style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontSize: 16)),
          const SizedBox(height: 12),
          if (_tags.isEmpty)
            _emptyHint(context, '尚無標籤', '建立標籤後，匯出的檔案會自動打標籤')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _tags.map((t) => _TagChip(
                tag: t,
                onDelete: () async {
                  await _tagStore.deleteTag(t.name);
                  _load();
                },
              )).toList(),
            ),
        ],
      ),
    );
  }

  Future<void> _createTag() async {
    final name = _newTagController.text.trim();
    if (name.isEmpty) return;
    await _tagStore.createTag(name, color: '#4A90D9');
    _newTagController.clear();
    _load();
  }
}

class _TagChip extends StatelessWidget {
  final FileTag tag;
  final VoidCallback onDelete;
  _TagChip({required this.tag, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.label, size: 12, color: BridgeDSColors.of(context).accentBlue),
          SizedBox(width: 4),
          Text(tag.name,
              style: BridgeDSColors.of(context).small.copyWith(
                  fontSize: 14, color: BridgeDSColors.of(context).accentBlue, fontWeight: FontWeight.w500)),
          if (tag.filePaths.isNotEmpty) ...[
            SizedBox(width: 4),
            Text('${tag.filePaths.length}',
                style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
          ],
          SizedBox(width: 6),
          GestureDetector(
            onTap: onDelete,
            child: Icon(Icons.close, size: 12, color: BridgeDSColors.of(context).textMuted),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 匯出中心 (1A+-7 + 1A+-4)
// ═══════════════════════════════════════════════════════

class _ExportTab extends StatefulWidget {
  const _ExportTab();

  @override
  State<_ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<_ExportTab> {
  final _exportService = FileExportService();
  List<String> _log = [];
  bool _busy = false;

  void _addLog(String msg) {
    if (mounted) setState(() => _log.insert(0, '${DateTime.now().toIso8601String().substring(11, 19)} $msg'));
  }

  Future<void> _exportConversations() async {
    setState(() => _busy = true);
    try {
      final result = await _exportService.exportAll();
      final ok = result.where((r) => r.success).length;
      final fail = result.where((r) => !r.success).length;
      _addLog('對話/記憶/洞察匯出：$ok 成功${fail > 0 ? '，$fail 失敗' : ''}');
      for (final r in result.where((r) => !r.success)) {
        _addLog('  ❌ ${r.error}');
      }
    } catch (e) {
      _addLog('匯出失敗：$e');
    }
    setState(() => _busy = false);
  }

  Future<void> _migrateCache() async {
    setState(() => _busy = true);
    try {
      // 快取搬移 = exportLegacyMemories + exportBrainMemories
      final legacy = await _exportService.exportLegacyMemories();
      if (legacy.success) {
        _addLog('舊記憶快取搬移完成 → ${legacy.filePath}');
      } else {
        _addLog('舊記憶搬移：${legacy.error ?? '無資料'}');
      }

      final brain = await _exportService.exportBrainMemories();
      if (brain.success) {
        _addLog('大腦記憶快取搬移完成 → ${brain.filePath}');
      } else {
        _addLog('大腦記憶搬移：${brain.error ?? '無資料'}');
      }
    } catch (e) {
      _addLog('快取搬移失敗：$e');
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('匯出中心', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontSize: 16)),
          SizedBox(height: 4),
          Text('把 App 內的對話、記憶、洞察匯出成檔案，存入主資料夾',
              style: BridgeDSColors.of(context).small.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
          SizedBox(height: 16),

          // ── 操作按鈕 ──
          _ExportButton(
            icon: Icons.cloud_download_outlined,
            title: '全量匯出',
            subtitle: '對話 + 大腦記憶 + 舊記憶 + 洞察 → 檔案層',
            color: BridgeDSColors.of(context).accentBlue,
            busy: _busy,
            onTap: _exportConversations,
          ),
          SizedBox(height: 8),
          _ExportButton(
            icon: Icons.swap_horiz,
            title: '快取搬移',
            subtitle: '把 sandbox 內的記憶搬到檔案層（舊記憶 + 大腦記憶）',
            color: BridgeDSColors.of(context).accentPurple,
            busy: _busy,
            onTap: _migrateCache,
          ),
          SizedBox(height: 20),

          // ── 執行記錄 ──
          if (_log.isNotEmpty) ...[
            Text('執行記錄', style: BridgeDSColors.of(context).labelMono.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
            SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 300),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).canvas,
                borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
                border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _log.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(l,
                        style: BridgeDSColors.of(context).labelMono.copyWith(
                            fontSize: 14, color: BridgeDSColors.of(context).textSecondary)),
                  )).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool busy;
  final VoidCallback onTap;
  _ExportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(BridgeDS.spaceMD),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: busy
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2, color: color),
                    )
                  : Icon(icon, size: 18, color: color),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: BridgeDSColors.of(context).small.copyWith(
                          color: BridgeDSColors.of(context).textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle,
                      style: BridgeDSColors.of(context).small.copyWith(
                          fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: BridgeDSColors.of(context).textMuted),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// 空狀態提示
// ═══════════════════════════════════════════════════════

Widget _emptyHint(BuildContext context, String title, String subtitle) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(BridgeDS.spaceXXL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: BridgeDS.textQuaternary),
          SizedBox(height: 12),
          Text(title, style: BridgeDS.headingS.copyWith(fontSize: 14, color: BridgeDSColors.of(context).textMuted)),
          SizedBox(height: 4),
          Text(subtitle,
              style: BridgeDS.small.copyWith(fontSize: 14, color: BridgeDS.textQuaternary),
              textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
