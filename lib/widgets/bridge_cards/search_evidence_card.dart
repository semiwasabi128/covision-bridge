// [以利沙 Sprint 5 2026-06-24] 從 chat_screen.dart 抽出：搜尋證據卡（純顯示 widget）
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../theme/bridge_design_system.dart';

/// [以利沙 Sprint 5 2026-06-24] 搜尋證據卡 — 純 StatelessWidget，不持有 service。
///
/// 接受 metadata 和兩個 callback（onCopy / onOpenPath），
/// 所有業務邏輯留在 chat_screen。
class SearchEvidenceCard extends StatelessWidget {
  final Map<String, dynamic> metadata;
  final void Function(String) onCopy;
  final void Function(String) onOpenPath;

  const SearchEvidenceCard({
    super.key,
    required this.metadata,
    required this.onCopy,
    required this.onOpenPath,
  });

  // [以利沙 Sprint 5 2026-06-24] 純函數：格式化擷取時間
  static String? _formatBridgeFetchedAt(String? iso) {
    if (iso == null || iso.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    final local = parsed.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final query = metadata['query']?.toString().trim();
    final fetchedAt = _formatBridgeFetchedAt(metadata['fetchedAt']?.toString());
    final timeSensitive = metadata['timeSensitive'] == true;
    final sourceHealth = metadata['sourceHealth']?.toString();
    final sourceWarning = metadata['sourceWarning']?.toString();
    final rawQueries = metadata['searchQueries'];
    final searchQueries = rawQueries is List
        ? rawQueries
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toList()
        : const <String>[];
    final rawSources = metadata['searchSources'];
    final sources = rawSources is List
        ? rawSources
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];

    return Container(
      width: 430,
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
                child: const Icon(
                  Icons.travel_explore_outlined,
                  size: 16,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '搜尋證據',
                  style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle().copyWith(color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,),
                ),
              ),
              Text(
                '${sources.length} 個來源',
                style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w800,),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (query != null && query.isNotEmpty)
            _SearchEvidenceLine(label: '查詢', value: query),
          if (searchQueries.isNotEmpty)
            _SearchEvidenceLine(
              label: '實際搜尋',
              value: searchQueries.take(3).join(' / '),
            ),
          if (fetchedAt != null)
            _SearchEvidenceLine(label: '擷取時間', value: fetchedAt),
          if (sourceHealth == 'sources_missing')
            const _SearchEvidenceLine(
              label: '來源狀態',
              value: '這次沒有取得可點來源。',
            ),
          if (sourceWarning != null && sourceWarning.trim().isNotEmpty)
            _SearchEvidenceLine(label: '提醒', value: sourceWarning.trim()),
          if (timeSensitive)
            const _SearchEvidenceLine(
              label: '時間提醒',
              value: '這類資料會變動，使用前建議再查一次。',
            ),
          if (sources.isNotEmpty) ...[
            const SizedBox(height: 8),
            // [迦勒確認/以利沙補完 2026-06-24] 來源列表：標題粗體 + 可點擊 URL（藍色底線），最多 3 筆
            _buildSearchSourcesList(context, sources),
          ],
        ],
      ),
    );
  }

  // [迦勒確認/以利沙補完 2026-06-24] 搜尋來源列表：標題粗體 + 可點擊 URL（藍色底線），最多 3 筆
  Widget _buildSearchSourcesList(BuildContext context, List<Map<String, dynamic>> sources) {
    const maxVisible = 3;
    final visible = sources.take(maxVisible).toList();
    final hasMore = sources.length > maxVisible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final source in visible) _buildSearchSourceRow(context, source),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: GestureDetector(
              onTap: () => onCopy(
                sources
                    .map(
                      (s) =>
                          '${s['title'] ?? s['url'] ?? '來源'}: ${s['url'] ?? ''}',
                    )
                    .join('\n'),
              ),
              child: Text(
                '查看更多來源',
                style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchSourceRow(BuildContext context, Map<String, dynamic> source) {
    final title = source['title']?.toString().trim().isNotEmpty == true
        ? source['title'].toString().trim()
        : source['url']?.toString().trim().isNotEmpty == true
        ? source['url'].toString().trim()
        : source['source']?.toString().trim().isNotEmpty == true
        ? source['source'].toString().trim()
        : '來源';
    final url = source['url']?.toString().trim() ?? '';
    final hasUrl = url.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: AppTheme.textPrimary,
              fontWeight: FontWeight.bold,),
          ),
          if (hasUrl)
            GestureDetector(
              onTap: () => onOpenPath(url),
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(color: BridgeDS.googleBlue,
                  decoration: TextDecoration.underline,
                  decorationColor: BridgeDS.googleBlue,),
              ),
            ),
        ],
      ),
    );
  }
}

/// [以利沙 Sprint 5 2026-06-24] 從 chat_screen.dart 移出的共用列元件。
class _SearchEvidenceLine extends StatelessWidget {
  final String label;
  final String value;

  const _SearchEvidenceLine({required this.label, required this.value});

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
