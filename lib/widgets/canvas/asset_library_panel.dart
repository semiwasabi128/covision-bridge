// asset_library_panel.dart
// 畫布側欄 — 資產庫（Obsidian 風格）
// [教練 Agent 2026-07-25] 移除記憶區（六大房間留在大腦 tab），只保留資產區
//
// 設計文件: open-canvas-unified-design.md §3.2

import 'package:bridge_app/models/digital_asset.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/vector_db/asset_sandbox.dart';
import 'package:bridge_app/services/vector_db/asset_index_service.dart'; // [教練 Agent 2026-07-25] 向量資料庫
import 'package:bridge_app/screens/vault/vault_file_tree.dart'; // [教練 Agent 2026-08-03] 樹狀渲染
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:file_picker/file_picker.dart'; // [教練 Agent 2026-08-03] 加入新資料夾
import 'package:flutter/material.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../theme/bridge_design_system.dart';

/// 資產庫面板（畫布側欄）。
///
/// 只顯示數位資產（照片、影片、文件、工作流等），
/// 可拖到畫布上。記憶（六大房間）已移至「大腦」tab。
class AssetLibraryPanel extends StatefulWidget {
  /// 點擊工作流資產時的 callback — 傳回 workflow JSON 字串
  final void Function(String workflowJson)? onLoadWorkflow;

  const AssetLibraryPanel({super.key, this.onLoadWorkflow});

  @override
  State<AssetLibraryPanel> createState() => _AssetLibraryPanelState();
}

/// [教練 Agent 2026-08-03] root group 結構
class _RootGroup {
  final String name;
  final String fullPath;
  final List<DigitalAsset> assets;
  _RootGroup({required this.name, required this.fullPath, required this.assets});
}

class _AssetLibraryPanelState extends State<AssetLibraryPanel> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  // [教練 Agent 2026-08-03] AssetIndexService — 用來掃描、查檔案
  final AssetIndexService _indexService = AssetIndexService();

  // 資產資料
  List<DigitalAsset> _assets = [];
  bool _assetsLoading = true;
  final Set<String> _activeTags = {};

  // [教練 Agent 2026-08-03] 樹狀 root 預設收合 — 只有使用者按開才展開
  final Set<String> _expandedRoots = {};

  // [教練 Agent 2026-08-03] 子資料夾展開狀態（每個 rootPath 一組）
  final Map<String, Set<String>> _expandedFolders = {};

  // [教練 Agent 2026-08-03] 正在掃描的 rootPath
  final Set<String> _scanningPaths = {};

  @override
  void initState() {
    super.initState();
    _loadAssets();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    try {
      // [教練 Agent 2026-07-25] 從兩個來源載入：
      // 1. DigitalAssetRegistryStore（已有的數位資產，含工作流）
      // 2. AssetIndexService（向量資料庫裡的檔案）
      final store = DigitalAssetRegistryStore();
      final assets = await store.getAll();

      // 從向量資料庫載入檔案
      final indexService = AssetIndexService();
      final manifestFiles = indexService.allFiles;
      final vectorDbAssets = <DigitalAsset>[];
      for (final mf in manifestFiles) {
        // 把 manifest 檔案轉成 DigitalAsset 顯示
        final ext = mf.path.contains('.')
            ? '.${mf.path.split('.').last}'
            : '';
        final kind = _inferKindFromExt(ext);
        final fileName = mf.path.split('/').last;
        final folderName = mf.folder.split('/').last;
        final created = DateTime.fromMillisecondsSinceEpoch(mf.modified);
        vectorDbAssets.add(DigitalAsset(
          id: 'vdb_${mf.path.hashCode}',
          title: fileName,
          kind: kind,
          summary: folderName,
          tags: const [],
          purposeTags: const [],
          creativeTags: const [],
          sourceLabel: mf.folder, // [教練 Agent 2026-08-03] 用 mf.folder (rootPath) 當 group key
          createdAt: created,
          updatedAt: created,
          secondBrainEntryId: '',
        ));
      }

      // 合併：向量資料庫的檔案 + 既有數位資產（去重）
      final existingIds = assets.map((a) => a.title).toSet();
      final merged = [
        ...assets,
        ...vectorDbAssets.where((a) => !existingIds.contains(a.title)),
      ];

      if (mounted) {
        setState(() {
          _assets = merged;
          _assetsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _assetsLoading = false);
    }
  }

  /// [教練 Agent 2026-07-25] 從副檔名推斷 DigitalAssetKind
  DigitalAssetKind _inferKindFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
      case '.heic':
      case '.gif':
      case '.mp4':
      case '.mov':
      case '.mp3':
      case '.wav':
      case '.m4a':
        return DigitalAssetKind.mediaAsset;
      case '.json':
        return DigitalAssetKind.workflowEngine;
      case '.md':
      case '.txt':
      case '.pdf':
      case '.docx':
        return DigitalAssetKind.documentAsset;
      default:
        return DigitalAssetKind.documentAsset;
    }
  }

  /// [教練 Agent 2026-08-03] 把 _assets 按 rootPath 分組 — sourceLabel = mf.folder = rootPath
  List<_RootGroup> get _rootGroups {
    final groups = <String, List<DigitalAsset>>{};
    for (final a in _assets) {
      // [教練 Agent 2026-08-03] sourceLabel 現在就是 mf.folder (rootPath) 直接當 key
      final rootPath = a.sourceLabel ?? '';
      if (rootPath.isEmpty) continue;
      groups.putIfAbsent(rootPath, () => []).add(a);
    }
    // 顯示 rootPath 最後一段（「農場資料庫」「橋樑計劃」）
    return groups.entries
        .map((e) => _RootGroup(
              name: e.key.split('/').last,
              fullPath: e.key,
              assets: e.value,
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// [教練 Agent 2026-08-03] 取 rootPath 下的 manifest 檔案
  /// [教練 Agent 2026-08-03] 搜尋時過濾：比對檔案名 + 路徑中繼節點（子資料夾名，如「鹿角蕨」）+ rootPath
  List<ManifestFile> _filesForRoot(String rootPath) {
    var files = _indexService.allFiles
        .where((f) => f.folder == rootPath)
        .toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      files = files.where((f) {
        final fileName = f.path.split('/').last;
        final folderSegments = f.path.split('/')
            .where((s) => s.isNotEmpty && s != fileName)
            .join(' / ');
        final fullPath = '${f.folder}/${f.path}';
        return fileName.toLowerCase().contains(q) ||
               folderSegments.toLowerCase().contains(q) ||
               fullPath.toLowerCase().contains(q);
      }).toList();
    }
    return files;
  }

  /// [教練 Agent 2026-08-03] 重新載入 manifest 並刷新 state
  Future<void> _refreshManifests() async {
    try {
      await _indexService.loadManifests();
      await _loadAssets();
    } catch (e) {
      debugPrint('[AssetLibrary] 刷新失敗: $e');
    }
  }

  /// [教練 Agent 2026-08-03] 加入新資料夾 → 同步到 vector DB
  Future<void> _addNewFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要加入向量資料庫的資料夾',
    );
    if (path == null) return;

    final sandbox = AssetSandbox();
    sandbox.addFolder(path);

    setState(() => _scanningPaths.add(path));

    try {
      await _indexService.fullScan(path);
      await _refreshManifests();
    } catch (e) {
      debugPrint('[AssetLibrary] 掃描失敗: $e');
    } finally {
      if (mounted) {
        setState(() => _scanningPaths.remove(path));
      }
    }
  }

  /// 重掃資料夾
  Future<void> _rescanFolder(String rootPath) async {
    setState(() => _scanningPaths.add(rootPath));
    try {
      await _indexService.fullScan(rootPath);
      await _refreshManifests();
    } catch (e) {
      debugPrint('[AssetLibrary] 重掃失敗: $e');
    } finally {
      if (mounted) {
        setState(() => _scanningPaths.remove(rootPath));
      }
    }
  }

  /// 移除資料夾
  Future<void> _removeFolder(String rootPath) async {
    final sandbox = AssetSandbox();
    sandbox.removeFolder(rootPath);
    setState(() {
      _expandedRoots.remove(rootPath);
      _expandedFolders.remove(rootPath);
    });
    await _refreshManifests();
  }

  /// 切換子資料夾展開
  void _toggleFolder(String rootPath, String folderPath) {
    setState(() {
      final set = _expandedFolders.putIfAbsent(rootPath, () => {});
      if (set.contains(folderPath)) {
        set.remove(folderPath);
      } else {
        set.add(folderPath);
      }
    });
  }

  List<DigitalAsset> get _filteredAssets {
    var list = List<DigitalAsset>.from(_assets);
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      // [教練 Agent 2026-08-03] 搜尋改為：
      // 1. DigitalAsset 標題/摘要/標籤（保留原本功能）
      // 2. 樹狀結構內的檔案名（mf.path 最後一段）
      // 3. 樹狀結構內的子資料夾名稱（mf.path 中間段，如「鹿角蕨」）
      // 4. rootPath（mf.folder）— 完整比對
      final manifestFiles = _indexService.allFiles;
      final manifestFileIds = <String>{};
      for (final mf in manifestFiles) {
        final fileName = mf.path.split('/').last;
        final folderSegments = mf.path.split('/')
            .where((s) => s.isNotEmpty && s != fileName)
            .join(' / ');
        final fullPath = '${mf.folder}/${mf.path}';
        if (fileName.toLowerCase().contains(q) ||
            folderSegments.toLowerCase().contains(q) ||
            fullPath.toLowerCase().contains(q)) {
          // mf.path.hashCode 是 DigitalAsset id 的命名規則（見 _loadRootGroups）
          manifestFileIds.add('vdb_${mf.path.hashCode}');
        }
      }
      list = list
          .where((a) =>
              a.title.toLowerCase().contains(q) ||
              a.summary.toLowerCase().contains(q) ||
              a.tags.any((t) => t.toLowerCase().contains(q)) ||
              manifestFileIds.contains(a.id))
          .toList();
    }
    if (_activeTags.isNotEmpty) {
      list = list.where((a) {
        final allTags = {...a.tags, ...a.purposeTags, ...a.creativeTags};
        return _activeTags.every((t) => allTags.contains(t));
      }).toList();
    }
    return list..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<String> get _allAssetTags {
    final tags = <String>{};
    for (final a in _assets) {
      tags.addAll(a.tags);
      tags.addAll(a.purposeTags);
      tags.addAll(a.creativeTags);
    }
    return tags.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    // [教練 Agent 2026-08-03] 改為佔滿父容器（跟 desktop_chat_panel 一樣會隨欄位拉寬）
    // 加 min/max 約束避免太窄或太寬
    return Container(
      constraints: const BoxConstraints(
        // [教練 Agent 2026-08-16 使用者回饋] minWidth 220→180，且 maxWidth 拿掉
        // 「太寬浪費空間」限制——寬度完全跟隨外層 sidebar 拖曳（clamp 200-500），
        // 不再壓縮內容產生黃黑警示條。
        minWidth: 180,
      ),
      color: colors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          _buildHeader(colors),
          // 搜尋框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _buildSearchField(),
          ),
          // 樹狀 rootPath 列表
          Expanded(
            child: _assetsLoading
                ? _buildLoadingHint()
                : ListView(
                    padding: const EdgeInsets.only(bottom: 8),
                    children: [
                      if (_rootGroups.isEmpty)
                        _buildEmptyHint()
                      else
                        ..._rootGroups.map((g) => _buildRootGroup(colors, g)),
                    ],
                  ),
          ),
          // 底部 — +加入新資料夾
          _buildFooter(colors),
        ],
      ),
    );
  }

  /// [教練 Agent 2026-08-03] 標題列 + 收合/展開（與浮動 overlay 對齊）
  Widget _buildHeader(BridgeDSColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.storage, size: 16, color: colors.accentBlue),
          const SizedBox(width: 8),
          Text(
            '向量資料庫',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] headingS token — 再升一級
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,),
          ),
          const Spacer(),
          Text(
            '${_assets.length}',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted,
              fontWeight: FontWeight.w500,),
          ),
        ],
      ),
    );
  }

  /// [教練 Agent 2026-08-03] 底部 — 「+加入新資料夾」按鈕（同步 vector DB 資料夾）
  Widget _buildFooter(BridgeDSColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: GestureDetector(
          onTap: _addNewFolder,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.accentBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colors.accentBlue.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add, size: 14, color: colors.accentBlue),
                const SizedBox(width: 6),
                Text(
                  '加入新資料夾',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                    color: colors.accentBlue,),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [教練 Agent 2026-08-03] 樹狀 root group — 跟浮動 overlay 對齊
  Widget _buildRootGroup(BridgeDSColors colors, _RootGroup group) {
    // [教練 Agent 2026-08-03] 搜尋時強制展開所有 root 跟子資料夾
    final isExpanded = _searchQuery.isNotEmpty || _expandedRoots.contains(group.fullPath);
    final files = _filesForRoot(group.fullPath);
    final tree = buildFileTree(files);
    // [教練 Agent 2026-08-03] 搜尋時展開所有子資料夾
    final expandedSet = _searchQuery.isNotEmpty
        ? tree.children.where((c) => c.isFolder).map((c) => c.path).toSet()
        : (_expandedFolders[group.fullPath] ?? {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (_expandedRoots.contains(group.fullPath)) {
              _expandedRoots.remove(group.fullPath);
            } else {
              _expandedRoots.add(group.fullPath);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,  // [教練 Agent 2026-08-03] iconMd — 跟 14pt 文字對齊
                  color: colors.textMuted,
                ),
                const SizedBox(width: 2),
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  size: 18,  // [教練 Agent 2026-08-03] iconLg — 主要資料夾 icon
                  color: colors.accentBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] 升級 — 跟「示範工作流」按鈕同級
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,),
                  ),
                ),
                Text(
                  '${group.assets.length}',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] 升級
                    color: colors.textMuted,
                    fontWeight: FontWeight.w500,),
                ),
                const SizedBox(width: 6),
                // 重掃
                InkWell(
                  onTap: () => _rescanFolder(group.fullPath),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.refresh, size: 12, color: colors.textMuted),
                  ),
                ),
                const SizedBox(width: 2),
                // 移除
                InkWell(
                  onTap: () => _removeFolder(group.fullPath),
                  borderRadius: BorderRadius.circular(3),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 12, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 子資料夾樹狀（跟浮動 overlay 對齊）
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 8, bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: buildFileTreeNodes(
                context,
                tree,
                0,
                expandedSet,
                (path) => _toggleFolder(group.fullPath, path),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchField() {
    // [教練 Agent 2026-08-03] Row + crossAxisAlignment.center 強制對齊放大鏡跟文字
    return Container(
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 10),
          Icon(Icons.search, color: BridgeDSColors.of(context).textMuted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '搜尋檔案/資料夾/標籤...',
                hintStyle: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isCollapsed: true,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String label,
    required int count,
    required bool expanded,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD, vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            SizedBox(width: 8),
            Text(
              label,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                // [教練 Agent 2026-08-03] headingS token
                fontWeight: FontWeight.w500,),
            ),
            SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
            Spacer(),
            Icon(
              expanded ? Icons.expand_less : Icons.chevron_right,
              color: BridgeDSColors.of(context).textMuted,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssetTile(DigitalAsset asset) {
    // 工作流引擎資產：可點擊載入
    final isWorkflow = asset.kind == DigitalAssetKind.workflowEngine;
    final canLoad = isWorkflow && widget.onLoadWorkflow != null;

    return LongPressDraggable<String>(
      data: asset.id,
      delay: const Duration(milliseconds: 50),
      feedback: _buildDragFeedback(asset.title, BridgeDSColors.of(context).accentBlue, '📄'),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _assetTileContent(asset),
      ),
      child: canLoad
          ? InkWell(
              onTap: () => _loadWorkflowAsset(asset),
              child: _assetTileContent(asset),
            )
          : _assetTileContent(asset),
    );
  }

  Future<void> _loadWorkflowAsset(DigitalAsset asset) async {
    if (widget.onLoadWorkflow == null) return;
    final store = DigitalAssetRegistryStore();
    final jsonStr = await store.getWorkflowJson(asset.id);
    if (jsonStr == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('找不到工作流 JSON：${asset.title}'),
            backgroundColor: BridgeDSColors.of(context).accentYellow,
          ),
        );
      }
      return;
    }
    widget.onLoadWorkflow!(jsonStr);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('載入工作流：${asset.title}'),
          backgroundColor: BridgeDSColors.of(context).accentGreen,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _assetTileContent(DigitalAsset asset) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(5),
        border: Border(
          left: BorderSide(color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.6), width: 2),
        ),
      ),
      child: Row(
        children: [
          Icon(_iconForAsset(asset), color: BridgeDSColors.of(context).accentBlue, size: 16),  // [教練 Agent 2026-08-03] iconMd — 跟 14pt 文字對齊
          SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),  // [教練 Agent 2026-08-03] 升級 — 跟 _sidebarItem「示範工作流」同級
                ),
                if (asset.summary.isNotEmpty)
                  Text(
                    asset.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragFeedback(String text, Color color, String emoji) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
            SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary, decoration: TextDecoration.none),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTagFilter() {
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: _allAssetTags.take(10).map((tag) {
        final active = _activeTags.contains(tag);
        return GestureDetector(
          onTap: () => setState(() {
            if (active) {
              _activeTags.remove(tag);
            } else {
              _activeTags.add(tag);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: active ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).surfaceHover,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: active ? BridgeDSColors.of(context).accentBlue : BridgeDSColors.of(context).borderSubtle,
                width: 1,
              ),
            ),
            child: Text(
              '#$tag',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: active ? BridgeDSColors.of(context).canvas : BridgeDSColors.of(context).textMuted,),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLoadingHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: BridgeDSColors.of(context).textMuted,
            ),
          ),
          SizedBox(width: 8),
          Text('載入中...', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,)),
        ],
      ),
    );
  }

  Widget _buildEmptyHint() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD, vertical: 16),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 32, color: BridgeDSColors.of(context).textMuted),
          SizedBox(height: 8),
          Text(
            '尚無資產',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
          SizedBox(height: 4),
          Text(
            '在設定中加入資料夾到向量資料庫後，\n檔案會自動顯示在這裡',
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
          ),
        ],
      ),
    );
  }

  IconData _iconForAsset(DigitalAsset asset) {
    // 工作流引擎資產 → 專屬圖示
    if (asset.kind == DigitalAssetKind.workflowEngine) {
      return Icons.account_tree;
    }
    final allTags = {...asset.tags, ...asset.purposeTags, ...asset.creativeTags};
    if (allTags.any((t) => t.toLowerCase().contains('pdf'))) {
      return Icons.picture_as_pdf;
    }
    if (allTags.any((t) =>
        ['png', 'jpg', 'jpeg', 'webp', 'gif', '圖片', 'image']
            .any((kw) => t.toLowerCase().contains(kw)))) {
      return Icons.image_outlined;
    }
    if (allTags.any((t) =>
        ['mp4', 'mov', 'video', '影片'].any((kw) => t.toLowerCase().contains(kw)))) {
      return Icons.movie_outlined;
    }
    if (allTags.any((t) =>
        ['code', '程式', 'dart', 'python'].any((kw) => t.toLowerCase().contains(kw)))) {
      return Icons.code;
    }
    return Icons.insert_drive_file_outlined;
  }
}
