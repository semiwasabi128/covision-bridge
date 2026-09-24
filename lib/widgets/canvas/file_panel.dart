// file_panel.dart
// 右側檔案面板 — 資產搜尋 + 標籤 + 拖放源
// B2 Phase 1.5 Open Canvas 統一設計
//
// 設計文件: open-canvas-unified-design.md §3.2

import 'package:bridge_app/models/digital_asset.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import '../../theme/bridge_design_system.dart';

/// 右側檔案/資產面板。
///
/// 顯示已註冊的數位資產，支援搜尋和拖放到畫布。
class FilePanel extends StatefulWidget {
  final void Function(DigitalAsset asset, Offset dropPosition)? onAssetDropped;
  final void Function(DigitalAsset asset)? onAssetTap;

  const FilePanel({
    super.key,
    this.onAssetDropped,
    this.onAssetTap,
  });

  @override
  State<FilePanel> createState() => _FilePanelState();
}

class _FilePanelState extends State<FilePanel> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  List<DigitalAsset> _assets = [];
  final Set<String> _activeTags = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final store = DigitalAssetRegistryStore();
      final assets = await store.getAll();
      if (mounted) {
        setState(() {
          _assets = assets;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> get _allTags {
    final tags = <String>{};
    for (final a in _assets) {
      tags.addAll(a.tags);
      tags.addAll(a.purposeTags);
      tags.addAll(a.creativeTags);
    }
    return tags.toList()..sort();
  }

  List<DigitalAsset> get _filteredAssets {
    var list = _assets;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((a) =>
              a.title.toLowerCase().contains(q) ||
              a.summary.toLowerCase().contains(q) ||
              a.tags.any((t) => t.toLowerCase().contains(q)))
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        width: BridgeDS.sidebarWidth,
        color: BridgeDSColors.of(context).canvas,
        child: Center(
          child: CircularProgressIndicator(color: BridgeDSColors.of(context).accentBlue),
        ),
      );
    }

    return Container(
      width: BridgeDS.sidebarWidth,
      color: BridgeDSColors.of(context).canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題
          Padding(
            padding: const EdgeInsets.all(BridgeDS.spaceMD),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    color: BridgeDSColors.of(context).accentBlue, size: 18),
                const SizedBox(width: 8),
                Text('資產檔案',
                    style: BridgeDSColors.of(context).headingM.copyWith(fontSize: 18)),
              ],
            ),
          ),
          // 搜尋框
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD),
            child: _buildSearchField(),
          ),
          const SizedBox(height: BridgeDS.spaceSM),
          // 標籤篩選
          if (_allTags.isNotEmpty)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: BridgeDS.spaceMD),
              child: _buildTagFilter(),
            ),
          SizedBox(height: BridgeDS.spaceSM),
          // 資產列表
          Expanded(
            child: _filteredAssets.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding:
                        EdgeInsets.only(bottom: BridgeDS.spaceMD),
                    itemCount: _filteredAssets.length,
                    itemBuilder: (context, index) =>
                        _buildAssetTile(_filteredAssets[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle, width: 1),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: BridgeDSColors.of(context).textPrimary, fontSize: 14),
        decoration: InputDecoration(
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: '搜尋檔案...',
          hintStyle: TextStyle(color: BridgeDSColors.of(context).textMuted, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: BridgeDSColors.of(context).textMuted, size: 18),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  Widget _buildTagFilter() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: _allTags.take(12).map((tag) {
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: active
                  ? BridgeDSColors.of(context).accentBlue
                  : BridgeDSColors.of(context).surfaceHover,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: active
                    ? BridgeDSColors.of(context).accentBlue
                    : BridgeDSColors.of(context).borderSubtle,
                width: 1,
              ),
            ),
            child: Text(
              '#$tag',
              style: TextStyle(
                color: active
                    ? BridgeDSColors.of(context).canvas
                    : BridgeDSColors.of(context).textMuted,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAssetTile(DigitalAsset asset) {
    return LongPressDraggable<String>(
      data: asset.id,
      delay: const Duration(milliseconds: 50),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: BridgeDSColors.of(context).accentBlue, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconForAsset(asset),
                  color: BridgeDSColors.of(context).accentBlue, size: 16),
              SizedBox(width: 6),
              Flexible(
                child: Text(
                  asset.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _assetTileContent(asset),
      ),
      child: InkWell(
        onTap: () => widget.onAssetTap?.call(asset),
        child: _assetTileContent(asset),
      ),
    );
  }

  Widget _assetTileContent(DigitalAsset asset) {
    return Container(
      margin: const EdgeInsets.symmetric(
          horizontal: BridgeDS.spaceMD, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border(
          left: BorderSide(
              color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.6), width: 2),
        ),
      ),
      child: Row(
        children: [
          Icon(_iconForAsset(asset),
              color: BridgeDSColors.of(context).accentBlue, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  asset.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: BridgeDSColors.of(context).textPrimary,
                    fontSize: 14,
                  ),
                ),
                if (asset.summary.isNotEmpty)
                  Text(
                    asset.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: BridgeDSColors.of(context).textMuted,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(BridgeDS.spaceLG),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open,
                color: BridgeDSColors.of(context).textMuted, size: 32),
            SizedBox(height: 8),
            Text(
              _assets.isEmpty ? '尚無資產' : '無匹配結果',
              style: TextStyle(
                color: BridgeDSColors.of(context).textMuted,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForAsset(DigitalAsset asset) {
    // 從 capabilities 或 tags 推測類型
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
