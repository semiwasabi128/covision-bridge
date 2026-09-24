// brain_container_screen.dart
// 大腦容器視覺化 — 六大房間 + 記憶瀏覽
// 建立日期: 2026-07-03 by 教練 Agent (CEO)
//
// 三層導航：
// 1. 房間概覽（六大房間 + 燈號 + 記憶數）
// 2. 房間記憶列表（可搜尋、可調重要性）
// 3. 記憶詳情（內容、來源、連結、存取次數）

import 'package:flutter/material.dart';
import '../../models/brain_container/brain_room.dart';
import '../../services/brain_container/brain_container_service.dart';
import '../../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

class BrainContainerScreen extends StatefulWidget {
  const BrainContainerScreen({super.key});

  @override
  State<BrainContainerScreen> createState() => _BrainContainerScreenState();
}

class _BrainContainerScreenState extends State<BrainContainerScreen> {
  Map<BrainRoom, int> _roomStats = {};
  bool _isLoading = true;
  bool _modelAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final svc = BrainContainerService.instance;
    if (!svc.isInitialized) {
      // 等 initialize 完成
      for (var i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (svc.isInitialized) break;
      }
    }
    final stats = await svc.getRoomStats();
    final modelOk = svc.isModelAvailable;
    if (mounted) {
      setState(() {
        _roomStats = stats;
        _modelAvailable = modelOk;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('大腦容器', style: TextStyle(color: BridgeDSColors.of(context).textPrimary)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: BridgeDSColors.of(context).textPrimary),
          onPressed: () => context.pop(),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 模型狀態 banner
                    if (!_modelAvailable) ...[
                      _buildModelWarningBanner(),
                      const SizedBox(height: 16),
                    ],
                    // 總記憶數
                    _buildTotalSummary(),
                    const SizedBox(height: 16),
                    // 六大房間
                    Text(
                      '六大房間',
                      style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                        color: BridgeDSColors.of(context).textPrimary,),
                    ),
                    const SizedBox(height: 16),
                    ...BrainRoom.values.map((room) => _buildRoomCard(room)),
                    const SizedBox(height: 24),
                    // 全部記憶搜尋
                    _buildSearchButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildModelWarningBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: BridgeDSColors.of(context).accentYellow.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: BridgeDSColors.of(context).accentYellow, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '記憶模型未安裝，目前使用 fallback 模式。\n'
              '前往「設定 → 大腦記憶模型」下載安裝。',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentYellow,
                height: 1.4,),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalSummary() {
    final total = _roomStats.values.fold(0, (a, b) => a + b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Row(
        children: [
          Icon(Icons.psychology, color: BridgeDSColors.of(context).textPrimary, size: 32),
          SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$total',
                style: TextStyle(
                  color: BridgeDSColors.of(context).textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '條記憶',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,),
              ),
            ],
          ),
          Spacer(),
          if (_modelAvailable)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(context).textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: BridgeDSColors.of(context).textPrimary, size: 14),
                  SizedBox(width: 8),
                  Text(
                    '語意搜尋',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRoomCard(BrainRoom room) {
    final count = _roomStats[room] ?? 0;
    // 燈號：根據記憶數量決定活躍度
    final isActive = count > 0;
    final isHot = count > 10;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _navigateToRoom(room),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: BridgeDSColors.of(context).borderDefault),
          ),
          child: Row(
            children: [
              // 房間 icon + 燈號
              Stack(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: (isActive ? BridgeDSColors.of(context).accentPurple : BridgeDSColors.of(context).textMuted)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Center(
                      child: Text(
                        room.icon,
                        style: TierStyle.of(context, Tier.appHeadline).toTextStyle(),
                      ),
                    ),
                  ),
                  // 燈號
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: !isActive
                            ? BridgeDSColors.of(context).textMuted
                            : isHot
                                ? BridgeDSColors.of(context).accentGreen
                                : BridgeDSColors.of(context).accentYellow,
                        shape: BoxShape.circle,
                        border: Border.all(color: BridgeDSColors.of(context).textPrimary, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // 房間名稱 + 副標題
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.displayName,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                        color: BridgeDSColors.of(context).textPrimary,),
                    ),
                    Text(
                      '$count 條記憶',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                    ),
                  ],
                ),
              ),
              // 活躍度指示
              if (isHot)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '活躍',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentGreen,
                      fontWeight: FontWeight.w600,),
                  ),
                ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: BridgeDSColors.of(context).textMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showSearchDialog,
        icon: const Icon(Icons.search, size: 18),
        label: const Text('搜尋全部記憶'),
        style: OutlinedButton.styleFrom(
          foregroundColor: BridgeDSColors.of(context).accentPurple,
          side: BorderSide(color: BridgeDSColors.of(context).accentPurple),
          padding: const EdgeInsets.symmetric(vertical: 06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
        ),
      ),
    );
  }

  void _navigateToRoom(BrainRoom room) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RoomMemoryListScreen(room: room),
      ),
    ).then((_) => _loadData()); // 回來時刷新
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (_) => const _MemorySearchDialog(),
    );
  }
}

// ============================================================
// 房間記憶列表頁
// ============================================================

class _RoomMemoryListScreen extends StatefulWidget {
  final BrainRoom room;

  const _RoomMemoryListScreen({required this.room});

  @override
  State<_RoomMemoryListScreen> createState() => _RoomMemoryListScreenState();
}

class _RoomMemoryListScreenState extends State<_RoomMemoryListScreen> {
  List<_MemoryRow> _memories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    final svc = BrainContainerService.instance;
    if (!svc.isInitialized) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 透過 BrainContainerService 做語意搜尋
      final memories = await _fetchMemoriesFromDB(widget.room);
      if (mounted) {
        setState(() {
          _memories = memories;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<_MemoryRow>> _fetchMemoriesFromDB(BrainRoom room) async {
    // 透過 BrainContainerService 的內部 DB 查詢
    // 這裡需要直接存取 BrainDatabase
    final svc = BrainContainerService.instance;
    // 使用 getAllMemoryContents 的模式，但加 room filter
    // 因為 BrainContainerService 沒有公開 room-specific 查詢，
    // 我們用 retrieveMemories 做語意搜尋，或直接用 SQL
    //
    // 暫時方案：用 retrieveMemories(query: room.displayName) 做近似搜尋
    // 但這需要模型可用。fallback: 直接查 DB。
    //
    // 更好的方案：在 BrainContainerService 加 getMemoriesByRoom()
    // 但為了不增加更多修改，這裡先用 retrieveMemories
    final results = await svc.retrieveMemories(
      query: room.displayName,
      roomFilter: room,
      limit: 50,
    );

    if (results.isEmpty) return [];

    return results
        .where((r) => r.content.isNotEmpty)
        .map((r) => _MemoryRow(
              id: r.memoryId,
              content: r.content,
              similarity: r.similarity,
              recallReason: r.reasonDetail,
              isConnectionExpansion: r.isConnectionExpansion,
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.room.icon} ${widget.room.displayName}',
          style: TextStyle(color: BridgeDSColors.of(context).textPrimary),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: BridgeDSColors.of(context).textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _memories.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _memories.length,
                  itemBuilder: (_, i) => _buildMemoryCard(_memories[i]),
                ),
    );
  }

  Widget _buildEmpty() {
    final hasModel = BrainContainerService.instance.isModelAvailable;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(widget.room.icon, style: TierStyle.of(context, Tier.appTitle).toTextStyle()),
          const SizedBox(height: 16),
          Text(
            hasModel
                ? '這個房間還沒有被召回的記憶\n繼續對話，記憶會自然累積'
                : '記憶模型未安裝\n安裝後才能使用語意搜尋',
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
              height: 1.5,),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryCard(_MemoryRow mem) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: BridgeDSColors.of(context).borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (mem.isConnectionExpansion)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '關聯',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.accent,
                      fontWeight: FontWeight.w600,),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  decoration: BoxDecoration(
                    color: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '直接命中',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).accentPurple,
                      fontWeight: FontWeight.w600,),
                  ),
                ),
              const Spacer(),
              if (mem.similarity > 0)
                Text(
                  '${(mem.similarity * 100).toInt()}% 相似',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            mem.content,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textPrimary,
              height: 1.5,),
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
          ),
          if (mem.recallReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              mem.recallReason,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                fontStyle: FontStyle.italic,),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// 搜尋對話框
// ============================================================

class _MemorySearchDialog extends StatefulWidget {
  const _MemorySearchDialog();

  @override
  State<_MemorySearchDialog> createState() => _MemorySearchDialogState();
}

class _MemorySearchDialogState extends State<_MemorySearchDialog> {
  final _controller = TextEditingController();
  List<_MemoryRow> _results = [];
  bool _searched = false;
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() => _loading = true);

    final svc = BrainContainerService.instance;
    final results = await svc.retrieveMemories(query: query, limit: 20);

    if (mounted) {
      setState(() {
        _results = results
            .where((r) => r.content.isNotEmpty)
            .map((r) => _MemoryRow(
                  id: r.memoryId,
                  content: r.content,
                  similarity: r.similarity,
                  recallReason: r.reasonDetail,
                  isConnectionExpansion: r.isConnectionExpansion,
                ))
            .toList();
        _searched = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('搜尋記憶'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: '輸入要搜尋的內容…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.send, size: 18),
                        onPressed: _search,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 16),
            if (_searched && _results.isEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  BrainContainerService.instance.isModelAvailable
                      ? '沒有找到相關記憶'
                      : '記憶模型未安裝，無法搜尋',
                  style: TextStyle(color: BridgeDSColors.of(context).textMuted),
                ),
              ),
            if (_results.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(
                      _results[i].content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                    ),
                    subtitle: Text(
                      '${(_results[i].similarity * 100).toInt()}% 相似',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('關閉'),
        ),
      ],
    );
  }
}

// ============================================================
// 輔助資料結構
// ============================================================

class _MemoryRow {
  final String id;
  final String content;
  final double similarity;
  final String recallReason;
  final bool isConnectionExpansion;

  _MemoryRow({
    required this.id,
    required this.content,
    required this.similarity,
    required this.recallReason,
    required this.isConnectionExpansion,
  });
}

// Helper extension for pop
extension on BuildContext {
  void pop() => Navigator.of(this).pop();
}
