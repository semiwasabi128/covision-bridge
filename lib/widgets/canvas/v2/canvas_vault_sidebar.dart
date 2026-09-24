// canvas_vault_sidebar.dart
// 畫布側欄 — Vault 條目搜尋 + 送至畫布
// [教練 Agent 2026-07-22] Phase 3
//
// 設計文件決策 #9：右鍵送至畫布，不做拖曳。
// 側欄可摺疊，點擊條目 → 送入畫布中心。
//
// 這是畫布的左側浮動面板，不佔用佈局空間。

import 'dart:async';

import 'package:bridge_app/services/vault/vault_service.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 畫布 Vault 側欄
///
/// 浮動在畫布左側，可摺疊。
/// 搜尋 Vault 條目 → 點擊 → 送至畫布。
class CanvasVaultSidebar extends StatefulWidget {
  /// 當使用者點擊條目時，將條目送至畫布
  final void Function(VaultEntry entry)? onSendToCanvas;

  const CanvasVaultSidebar({super.key, this.onSendToCanvas});

  @override
  State<CanvasVaultSidebar> createState() => _CanvasVaultSidebarState();
}

class _CanvasVaultSidebarState extends State<CanvasVaultSidebar> {
  bool _isExpanded = false;
  final _searchController = TextEditingController();
  List<VaultEntry> _results = [];
  bool _isSearching = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch();
    });
  }

  Future<void> _performSearch() async {
    setState(() => _isSearching = true);

    final results = await VaultService.instance.search(
      mode: VaultSearchMode.fullText,
      query: _searchController.text,
      limit: 20,
    );

    if (mounted) {
      setState(() {
        _results = results;
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = BridgeDSColors.of(context);

    if (!_isExpanded) {
      // 摺疊狀態 — 只顯示一個圖示按鈕
      return Positioned(
        left: 16,
        top: 72,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.borderDefault),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.auto_awesome_motion_outlined, size: 20),
              color: colors.textSecondary,
              tooltip: 'Vault 側欄',
              onPressed: () => setState(() => _isExpanded = true),
            ),
          ),
        ),
      );
    }

    // 展開狀態 — 搜尋面板
    return Positioned(
      left: 16,
      top: 72,
      bottom: 48,
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.borderDefault),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 標題列
              _buildHeader(colors),

              // 搜尋列
              _buildSearchBar(colors),

              // 結果列表
              Expanded(
                child: _isSearching
                    ? Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accentPurple,
                        ),
                      )
                    : _results.isEmpty
                        ? _buildEmptyResults(colors)
                        : _buildResultsList(colors),
              ),

              // 底部提示
              _buildFooter(colors),
            ],
          ),
        ),
      ),
    );
  }

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
          Icon(Icons.auto_awesome_motion,
              size: 16, color: colors.accentPurple),
          const SizedBox(width: 8),
          Text(
            'Vault 側欄',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.bold,
              color: colors.textPrimary,),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() => _isExpanded = false),
            child: Icon(Icons.chevron_left,
                size: 18, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BridgeDSColors colors) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: colors.surfaceHover,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(Icons.search, size: 16, color: colors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: '搜尋條目...',
                  hintStyle: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _performSearch();
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.clear,
                      size: 14, color: colors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyResults(BridgeDSColors colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 32, color: colors.textMuted),
            const SizedBox(height: 8),
            Text(
              '沒有結果',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(BridgeDSColors colors) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final entry = _results[index];
        return _SidebarEntryTile(
          entry: entry,
          colors: colors,
          onTap: () => widget.onSendToCanvas?.call(entry),
        );
      },
    );
  }

  Widget _buildFooter(BridgeDSColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 12, color: colors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '點擊條目送至畫布',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
            ),
          ),
          Text(
            '${_results.length} 筆',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

// ── 條目卡片 ──────────────────────────────────────────────────────

class _SidebarEntryTile extends StatelessWidget {
  final VaultEntry entry;
  final BridgeDSColors colors;
  final VoidCallback onTap;

  const _SidebarEntryTile({
    required this.entry,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceHover.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 類型 + 日期
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: _typeColor().withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    entry.typeLabel,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: _typeColor(),),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${entry.createdAt.month}/${entry.createdAt.day}',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.textMuted),
                ),
                const Spacer(),
                Icon(Icons.add_circle_outline,
                    size: 12, color: colors.textMuted),
              ],
            ),
            const SizedBox(height: 4),
            // 摘要
            Text(
              entry.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.3,
                color: colors.textPrimary,),
            ),
            // 標籤
            if (entry.tags.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 2,
                children: entry.tags.take(3).map((tag) {
                  return Text(
                    '#$tag',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: colors.accentPurple.withValues(alpha: 0.7),),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _typeColor() {
    switch (entry.source) {
      case 'chat':
        return BridgeDS.deepPurple;
      case 'agent_perception':
        return BridgeDS.teal;
      case 'system_sop':
        return BridgeDS.sopOrange;
      case 'knowledge_base':
        return BridgeDS.toolPurpleLight;
      case 'sub_analysis':
        return BridgeDS.pinkAccent;
      default:
        return BridgeDS.slate;
    }
  }
}
