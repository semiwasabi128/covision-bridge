// vault_file_tree.dart
// [教練 Agent 2026-07-28] 從 vault_screen.dart 抽出 — 分層檔案樹
//
// _FileTreeNode 資料結構 + 檔案樹渲染方法
// 需要 VaultScreenState 的 context（BridgeDSColors），所以用 mixin 或 helper class

import 'dart:io';
import 'package:bridge_app/services/material_pool_service.dart';
import 'package:flutter/material.dart';
import '../../theme/bridge_design_system.dart';
import '../../services/vector_db/asset_index_service.dart';
import '../../services/vector_db/file_classifier.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 分層檔案樹的節點資料結構
class FileTreeNode {
  final String name;
  final String path;
  final bool isFolder;
  final ManifestFile? file;

  final List<FileTreeNode> children = [];

  // [教練 Agent 2026-07-28] 快取 — 避免每次 build 都遞迴計算
  int _cachedFileCount = -1;
  bool _childrenSorted = false;

  FileTreeNode({
    required this.name,
    required this.path,
    required this.isFolder,
    this.file,
  });

  /// 遞迴計算此節點下所有檔案數量（快取版）
  int get totalFileCount {
    if (_cachedFileCount >= 0) return _cachedFileCount;
    if (!isFolder) {
      _cachedFileCount = 1;
      return 1;
    }
    var count = 0;
    for (final child in children) {
      count += child.totalFileCount;
    }
    _cachedFileCount = count;
    return count;
  }

  /// 確保子節點已排序（只排一次）
  void ensureSorted() {
    if (_childrenSorted) return;
    children.sort((a, b) {
      if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    _childrenSorted = true;
  }
}

/// 檔案樹工廠 — 從 ManifestFile 列表建構樹
///
/// [小葵 2026-09-09] Blue 回報兩 bug 的架構根因修復：
/// 1. 樹扁平化——多授權根（DATA/橋樑計劃＋農場資料庫＋bridge_media）合併時
///    舊版只吃 mf.path（相對路徑）、丟掉 mf.folder（根），導致三個根的
///    第一層資料夾全部混在一起（實測 40 個頂層資料夾）。Blue 記得的
///    「最外面五個資料夾」是單一根自己的結構，被合併後就認不出來了。
/// 2. 選資料夾右側空白——_selectedFolderPath 是相對路徑，但篩選端拿
///    絕對路徑 startsWith 比對 → 永遠 false → 素材牆恆空。
///
/// 修法：groupByRoot=true 時第一層為「根節點」（path=絕對根路徑），
/// 子節點 path 一律絕對（folder + 相對段）——樹的 key 空間與篩選、
/// 檔案系統三方一致，兩個 bug 同源同治。
FileTreeNode buildFileTree(List<ManifestFile> files, {bool groupByRoot = false}) {
  final root = FileTreeNode(name: '', path: '', isFolder: true);
  for (final mf in files) {
    if (groupByRoot) {
      // [小葵 2026-09-09] 根層：每個授權根一個節點（絕對路徑）
      final rootName = mf.folder.split('/').last;
      var rootNode = root.children
          .where((c) => c.isFolder && c.path == mf.folder)
          .firstOrNull;
      if (rootNode == null) {
        rootNode = FileTreeNode(name: rootName, path: mf.folder, isFolder: true);
        root.children.add(rootNode);
      }
      final segments =
          mf.path.split('/').where((s) => s.isNotEmpty).toList();
      _insertIntoTree(rootNode, segments, mf, rootPrefix: mf.folder);
    } else {
      // [教練 Agent 2026-08-03] mf.path 是相對路徑，不加 rootName prefix
      // （canvas 素材庫面板 per-root 使用，維持舊行為）
      final segments = mf.path.split('/').where((s) => s.isNotEmpty).toList();
      _insertIntoTree(root, segments, mf);
    }
  }
  return root;
}

void _insertIntoTree(FileTreeNode parent, List<String> segments, ManifestFile mf,
    {String? rootPrefix}) {
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final isFile = i == segments.length - 1;
    // [小葵 2026-09-09] 有 rootPrefix 時節點 path 一律絕對（與篩選端同空間）
    final childPath = rootPrefix != null
        ? '$rootPrefix/${segments.sublist(0, i + 1).join('/')}'
        : '${parent.path}/$seg'.replaceFirst(RegExp(r'^/'), '');

    if (isFile) {
      parent.children.add(FileTreeNode(
        name: seg,
        path: childPath,
        isFolder: false,
        file: mf,
      ));
    } else {
      var folder = parent.children
          .where((c) => c.isFolder && c.name == seg)
          .firstOrNull;
      if (folder == null) {
        folder = FileTreeNode(name: seg, path: childPath, isFolder: true);
        parent.children.add(folder);
      }
      parent = folder;
    }
  }
}

/// 渲染檔案樹（只渲染展開的資料夾）
/// 
/// [expandedFolders] — 已展開的資料夾 path 集合
/// [onToggleFolder] — 切換資料夾展開/收合的回調
/// [batchMode] — 批量選擇模式
/// [selectedIds] — 已選取的檔案 id 集合
/// [onToggleSelect] — 切換選取的回調
/// [assetRecords] — file_path → AssetRecord 映射（含 room/confidence）
Widget buildFileTreeNodes(
  BuildContext context,
  FileTreeNode node,
  int depth,
  Set<String> expandedFolders,
  void Function(String path)? onToggleFolder, {
  bool batchMode = false,
  Set<String>? selectedIds,
  void Function(String id)? onToggleSelect,
  Map<String, AssetRecord>? assetRecords,
}) {
  // [教練 Agent 2026-07-28] 用快取排序 — 避免每次 build 都 sort
  node.ensureSorted();
  final sorted = node.children;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // [教練 Agent 2026-07-28] 限制每層最多渲染 50 個子節點 — 避免萬級檔案卡死
      ...sorted.take(50).map((child) {
      if (child.isFolder) {
        final isExpanded = expandedFolders.contains(child.path);
        return _buildFolderTile(context, child, depth, isExpanded, expandedFolders, onToggleFolder,
          batchMode: batchMode,
          selectedIds: selectedIds,
          onToggleSelect: onToggleSelect,
          assetRecords: assetRecords,
        );
      } else {
        return Padding(
          padding: EdgeInsets.only(left: depth * 16.0),
          child: buildLibraryTile(
            context,
            child.file!,
            batchMode: batchMode,
            isSelected: selectedIds?.contains(child.file!.path) ?? false,
            onToggleSelect: onToggleSelect != null
                ? () => onToggleSelect(child.file!.path)
                : null,
            assetRecord: assetRecords?[child.file!.path],
          ),
        );
      }
    }).toList(),
    if (sorted.length > 50)
      Padding(
        padding: EdgeInsets.only(left: depth * 16.0 + 8, top: 4, bottom: 4),
        child: Text(
        '... 還有 ${sorted.length - 50} 個項目',
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
          fontStyle: FontStyle.italic,),
        ),
      ),
    ],
  );
}

/// 資料夾節點 tile（可展開/收合）
Widget _buildFolderTile(
  BuildContext context,
  FileTreeNode node,
  int depth,
  bool isExpanded,
  Set<String> expandedFolders,
  void Function(String path)? onToggleFolder, {
  bool batchMode = false,
  Set<String>? selectedIds,
  void Function(String id)? onToggleSelect,
  Map<String, AssetRecord>? assetRecords,
}) {
  final fileCount = node.totalFileCount;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        onTap: () => onToggleFolder?.call(node.path),
        borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
        child: Container(
          margin: const EdgeInsets.only(bottom: BridgeDS.spaceSM),
          padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceSM, vertical: BridgeDS.spaceSM),  // [教練 Agent 2026-08-03] 字級升級 padding 對應
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surfaceHover.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
            border: Border(
              left: BorderSide(
                color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(left: depth * 16.0),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,  // [教練 Agent 2026-08-03] iconMd
                  color: BridgeDSColors.of(context).textMuted,
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  size: 16,  // [教練 Agent 2026-08-03] iconMd
                  color: BridgeDSColors.of(context).accentBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                      // [教練 Agent 2026-08-03] 升級 — 跟「示範工作流」按鈕同級
                      fontWeight: FontWeight.w500,),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceSM, vertical: BridgeDS.spaceSM),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(BridgeDS.roundSubtle),
                  ),
                  child: Text(
                    '$fileCount',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] 升級 10→12（最低限度 token）
                      fontWeight: FontWeight.w600,
                      color: BridgeDSColors.of(context).accentBlue,),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      if (isExpanded)
        buildFileTreeNodes(context, node, depth + 1, expandedFolders, onToggleFolder,
          batchMode: batchMode,
          selectedIds: selectedIds,
          onToggleSelect: onToggleSelect,
          assetRecords: assetRecords,
        ),
    ],
  );
}
/// [教練 Agent 2026-07-28] 決策 2：檔案 tile（支援批量選擇 + 信心度低黃點 + 房間標籤）
///
/// [batchMode] — 批量選擇模式：顯示 checkbox
/// [isSelected] — 是否已選取
/// [onToggleSelect] — 切換選取回調
/// [assetRecord] — 含 room / classificationConfidence 的 DB 記錄
Widget buildLibraryTile(
  BuildContext context,
  ManifestFile mf, {
  bool batchMode = false,
  bool isSelected = false,
  VoidCallback? onToggleSelect,
  AssetRecord? assetRecord,
  VoidCallback? onAddToPool, // [小葵 2026-08-29] 素材池 Phase 1
  VoidCallback? onPreview,  // [小葵 2026-08-29] 預覽
}) {
  final fileName = mf.path.split('/').last;
  final folderName = mf.folder.split('/').last;
  final ext = mf.path.contains('.') ? mf.path.split('.').last.toLowerCase() : '';

  // 信心度低標記
  final isLowConfidence = assetRecord != null &&
      assetRecord.classificationConfidence < 0.5 &&
      assetRecord.classificationConfidence > 0;

  // 當前房間
  FileRoom? currentRoom;
  if (assetRecord != null) {
    currentRoom = FileRoom.values
        .where((r) => r.name == assetRecord.room)
        .firstOrNull;
  }

  IconData icon = Icons.insert_drive_file_outlined;
  if (['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif'].contains(ext)) {
    icon = Icons.image_outlined;
  } else if (['mp4', 'mov'].contains(ext)) {
    icon = Icons.movie_outlined;
  } else if (['mp3', 'wav', 'm4a'].contains(ext)) {
    icon = Icons.audio_file_outlined;
  } else if (['md', 'txt', 'pdf', 'docx'].contains(ext)) {
    icon = Icons.description_outlined;
  } else if (ext == 'json') {
    icon = Icons.account_tree;
  }

  return Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),  // [教練 Agent 2026-08-03] 字級升級 padding 對應
    decoration: BoxDecoration(
      color: isSelected
          ? BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.12)
          : BridgeDSColors.of(context).surface.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(5),
      border: Border(
        left: BorderSide(
          color: isSelected
              ? BridgeDSColors.of(context).accentPurple
              : currentRoom != null
                  ? Color(currentRoom.colorValue).withValues(alpha: 0.6)
                  : BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.6),
          width: 2,
        ),
      ),
    ),
    child: Row(
      children: [
        // 批量模式：checkbox
        if (batchMode) ...[
          GestureDetector(
            onTap: onToggleSelect,
            child: Icon(
              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
              size: 16,
              color: isSelected
                  ? BridgeDSColors.of(context).accentPurple
                  : BridgeDSColors.of(context).textMuted,
            ),
          ),
          const SizedBox(width: 6),
        ],
        // [小葵 2026-08-29] 預覽——圖片直接縮圖，其他保留 icon
        Builder(builder: (_) {
          final absPath = '${mf.folder}/${mf.path}';
          if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
            final f = File(absPath);
            if (f.existsSync()) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.file(
                  f,
                  width: 22,
                  height: 22,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(icon, size: 16, color: BridgeDSColors.of(context).accentBlue),
                ),
              );
            }
          }
          return Icon(icon, size: 16, color: BridgeDSColors.of(context).accentBlue);
        }),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
                        // [教練 Agent 2026-08-03] 升級 — 跟「示範工作流」按鈕同級
                      ),
                    ),
                  ),
                  // 信心度低標記黃點
                  if (isLowConfidence) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '分類信心度低（${(assetRecord.classificationConfidence * 100).toInt()}%），建議手動確認',
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(context).accentYellow,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  Text(
                    '$folderName/${mf.path.contains('/') ? mf.path.substring(0, mf.path.lastIndexOf('/')) : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                      // [教練 Agent 2026-08-03] 升級 11→12
                    ),
                  ),
                  if (currentRoom != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      currentRoom.icon,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle(),  // [教練 Agent 2026-08-03] 升級
                    ),
                    const SizedBox(width: 2),
                    Text(
                      currentRoom.label,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(
                        // [教練 Agent 2026-08-03] 升級 10→12
                        color: Color(currentRoom.colorValue),),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Text(
          formatFileSize(mf.size),
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(// [教練 Agent 2026-08-03] 升級 10→12
            color: BridgeDSColors.of(context).textMuted,),
        ),
        // [小葵 2026-08-29] 預覽鈕
        if (onPreview != null) ...[
          GestureDetector(
            onTap: onPreview,
            child: Icon(
              Icons.visibility_outlined,
              size: 14,
              color: BridgeDSColors.of(context).textMuted,
            ),
          ),
          const SizedBox(width: 6),
        ],
        // [小葵 2026-08-29] 素材池——加入購物車
        if (onAddToPool != null) ...[
          const SizedBox(width: 6),
          _PoolAddButton(
            onPressed: onAddToPool,
            alreadyInPool: assetRecord != null &&
                MaterialPoolService.instance.draft?.items
                        .any((i) => i.assetId == assetRecord.id) ==
                    true,
          ),
        ],
      ],
    ),
  );
}

/// 格式化檔案大小
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
}


/// [小葵 2026-08-29] 加入素材池小按鈕——黑底紫框風（教學按鈕定案語言）
class _PoolAddButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool alreadyInPool;

  const _PoolAddButton({required this.onPressed, required this.alreadyInPool});

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: alreadyInPool ? colors.borderSubtle : colors.accentPurple,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              alreadyInPool ? Icons.check : Icons.add_shopping_cart_outlined,
              size: 12,
              color: alreadyInPool ? colors.textMuted : colors.accentPurple,
            ),
            const SizedBox(width: 3),
            Text(
              alreadyInPool ? '已加入' : '加入',
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(
                    color:
                        alreadyInPool ? colors.textMuted : colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
