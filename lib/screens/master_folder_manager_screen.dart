// AD-05 主資料夾 — 管理畫面
//
// 使用者增補 #2：使用者安裝時可選多個資料夾納入 App
// （Google Drive 同步概念，不限定單一位置）
//
// 功能：
// - 列出所有已納入的主資料夾
// - 新增資料夾（file_picker 選擇）
// - 移除資料夾（只從清單移除，不刪實際檔案）
// - 啟用/停用資料夾
// - 顯示每個資料夾的目錄結構概覽

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/master_folder.dart';
import '../services/file_layer_service.dart';
import '../services/master_folder_store.dart';
import '../theme/app_theme.dart';
import '../widgets/file_export_panel.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

class MasterFolderManagerScreen extends StatefulWidget {
  final String? returnTo;

  const MasterFolderManagerScreen({super.key, this.returnTo});

  @override
  State<MasterFolderManagerScreen> createState() =>
      _MasterFolderManagerScreenState();
}

class _MasterFolderManagerScreenState
    extends State<MasterFolderManagerScreen> {
  final _store = const MasterFolderStore();
  final _fileLayer = const FileLayerService();

  List<MasterFolder> _folders = const [];
  bool _loading = true;
  Map<String, MasterFolderTree?> _trees = {};

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() => _loading = true);
    final folders = await _store.loadAll();
    final trees = <String, MasterFolderTree?>{};
    for (final folder in folders) {
      if (!folder.enabled) continue;
      try {
        trees[folder.id] = await _fileLayer.scanFolder(folder);
      } catch (_) {
        trees[folder.id] = null;
      }
    }
    if (mounted) {
      setState(() {
        _folders = folders;
        _trees = trees;
        _loading = false;
      });
    }
  }

  Future<void> _addFolder() async {
    String? selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要納入的主資料夾',
    );

    if (selectedPath == null || selectedPath.trim().isEmpty) return;

    // 檢查是否已存在
    final existing = _folders.where(
      (f) => _normalizePath(f.path) == _normalizePath(selectedPath),
    );
    if (existing.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('此資料夾已在清單中')),
        );
      }
      return;
    }

    // 新增並確保目錄結構
    final folder = await _store.add(selectedPath);
    // 立即掃描
    try {
      final tree = await _fileLayer.scanFolder(folder);
      _trees[folder.id] = tree;
    } catch (_) {
      _trees[folder.id] = null;
    }

    if (mounted) {
      setState(() {
        _folders = [..._folders, folder];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已納入「${folder.label}」')),
      );
    }
  }

  Future<void> _removeFolder(MasterFolder folder) async {
    // 預設資料夾不能移除
    if (folder.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('預設資料夾無法移除')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除資料夾'),
        content: Text(
          '確定要將「${folder.label}」從主資料夾清單移除嗎？\n\n'
          '檔案不會被刪除，但 App 不再掃描此資料夾。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('移除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _store.remove(folder.id);
    _trees.remove(folder.id);
    if (mounted) {
      setState(() {
        _folders = _folders.where((f) => f.id != folder.id).toList();
      });
    }
  }

  Future<void> _toggleEnabled(MasterFolder folder) async {
    await _store.toggleEnabled(folder.id);
    await _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('主資料夾', style: TextStyle(color: AppTheme.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          tooltip: '返回',
          onPressed: () {
            if (widget.returnTo != null) {
              context.go(widget.returnTo!);
            } else {
              context.pop();
            }
          },
        ),
        backgroundColor: AppTheme.background,
        elevation: 0,
      ),
      backgroundColor: AppTheme.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 說明卡片
                  _buildInfoCard(),
                  const SizedBox(height: 16),

                  // 資料夾清單
                  ..._folders.map((folder) => _buildFolderCard(folder)),

                  // 新增按鈕
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _addFolder,
                      icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                      label: const Text('新增資料夾'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusMedium),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 匯出 + 標籤管理面板
                  const Divider(),
                  const SizedBox(height: 16),
                  const FileExportPanel(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHighlight,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: AppTheme.primaryLight.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 20, color: AppTheme.primary),
              SizedBox(width: 8),
              Text(
                '主資料夾是什麼？',
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                  color: AppTheme.primary,),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '主資料夾是 App 的「家」——你的專案、記憶庫、圖書館都存放在這裡。'
            '你可以納入多個資料夾，App 只掃描這些資料夾，不會掃描整台電腦。',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderCard(MasterFolder folder) {
    final tree = _trees[folder.id];
    final totalFiles = tree?.roots.fold(0, (sum, root) => sum + root.fileCount) ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        side: BorderSide(
          color: folder.enabled
              ? AppTheme.border
              : AppTheme.border.withAlpha(50),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Row(
              children: [
                Icon(
                  folder.isDefault ? Icons.home_outlined : Icons.folder_outlined,
                  size: 24,
                  color: folder.enabled ? AppTheme.primary : AppTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            folder.label,
                            style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                              color: folder.enabled
                                  ? AppTheme.textPrimary
                                  : AppTheme.textMuted,),
                          ),
                          if (folder.isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceHighlight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '預設',
                                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        folder.path,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted,),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 啟停開關
                if (!folder.isDefault)
                  Switch(
                    value: folder.enabled,
                    onChanged: (_) => _toggleEnabled(folder),
                    activeThumbColor: AppTheme.primary,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // 統計列
            if (folder.enabled && tree != null) ...[
              Row(
                children: [
                  _buildStatChip(
                    Icons.folder_outlined,
                    '專案 ${tree.roots.where((r) => r.category == FolderCategory.projects).fold(0, (s, r) => s + r.children.length)}',
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.description_outlined,
                    '$totalFiles 個檔案',
                  ),
                  if (folder.lastScannedAt != null) ...[
                    const SizedBox(width: 8),
                    _buildStatChip(
                      Icons.update,
                      _formatDate(folder.lastScannedAt!),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ] else if (!folder.enabled) ...[
              Text(
                '已停用',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted,),
              ),
              const SizedBox(height: 8),
            ],

            // 操作列
            Row(
              children: [
                if (!folder.isDefault)
                  TextButton.icon(
                    onPressed: () => _removeFolder(folder),
                    icon: const Icon(Icons.remove_circle_outline, size: 16),
                    label: const Text('移除'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                const Spacer(),
                if (folder.enabled && tree != null)
                  TextButton.icon(
                    onPressed: () => _showTreeDetails(folder, tree),
                    icon: const Icon(Icons.account_tree_outlined, size: 16),
                    label: const Text('查看結構'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textSecondary,),
          ),
        ],
      ),
    );
  }

  void _showTreeDetails(MasterFolder folder, MasterFolderTree tree) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLarge),
        ),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            // 標題列
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.account_tree, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      folder.label,
                      style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 樹狀結構
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: tree.roots
                    .map((node) => _buildTreeNode(node, 0))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreeNode(TreeNode node, int depth) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: Icon(
          node.isDirectory ? Icons.folder : Icons.insert_drive_file,
          size: 18,
          color: node.isDirectory ? AppTheme.primary : AppTheme.textMuted,
        ),
        title: Text(
          node.name,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: node.isDirectory
                ? AppTheme.textPrimary
                : AppTheme.textSecondary,),
        ),
        subtitle: node.isDirectory
            ? Text(
                '${node.fileCount} 個項目',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted),
              )
            : null,
        children: node.isDirectory
            ? node.children.map((child) => _buildTreeNode(child, depth + 1)).toList()
            : const [],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _normalizePath(String path) {
    var value = path.trim();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}
