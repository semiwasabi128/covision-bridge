// receipts_search_overlay.dart
// [收據搜尋 S1 2026-09-08]
// 全局搜尋面板——常駐獨立 panel（QuickAssistantManager 同款 OverlayEntry 模式）。
// 設計稿：docs/specs/2026-09-08-receipts-search.md §4.2（S1 改版）
//
// Blue S1 三鐵則：
// 1. 按出來是獨立視窗——切任何畫面都不消失，除非手動關閉
// 2. 狀態保留——重開時維持上次搜尋的 query 與結果
// 3. 輸入框真的縮短——右側轉圈/結果數與文字之間有明確空隙
//
// S3 四動作：每筆結果（記憶/資產域）hover 出現動作鈕：
// ①向量資料庫開啟 ②大腦圖譜開啟（飛近+自轉+預覽卡）③匯入畫布 ④匯入對話

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bridge_app/services/search/receipts_search_service.dart';
import 'package:bridge_app/services/tasks/task_session.dart' show taskStatusLabel;
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

/// 搜尋面板全域管理器——常駐（不因切 tab/頁面消失）
class ReceiptsSearchManager {
  static OverlayEntry? _entry;
  /// [S1] 狀態保留——關閉後重開維持上次搜尋
  static String lastQuery = '';
  static ReceiptsResults lastResults = const ReceiptsResults();

  static bool get isOpen => _entry != null;

  /// 開啟（或聚焦既有面板）
  static void open(BuildContext context,
      {required void Function(ReceiptHop hop, ReceiptAction action) onAction}) {
    if (_entry != null) return; // 已開——不重複（狀態自然保留）
    _entry = OverlayEntry(
      builder: (ctx) => ReceiptsSearchPanel(
        initialQuery: lastQuery,
        initialResults: lastResults,
        onAction: onAction,
        onClose: close,
        onStateSaved: (q, r) {
          lastQuery = q;
          lastResults = r;
        },
      ),
    );
    OverlayState? overlay;
    try {
      overlay = Overlay.maybeOf(context, rootOverlay: true);
    } catch (_) {}
    overlay ??= _rootOverlayAccessor?.call();
    if (overlay == null) {
      debugPrint('[ReceiptsSearch] 找不到 Overlay（請回報）');
      _entry = null;
      return;
    }
    overlay.insert(_entry!);
  }

  /// 關閉（狀態已由 onStateSaved 保留）
  static void close() {
    _entry?.remove();
    _entry = null;
  }

  /// root Overlay accessor——由 App 層注入（QuickAssistant fallback 同款）
  static OverlayState? Function()? _rootOverlayAccessor;
  static void setRootOverlayAccessor(OverlayState? Function() fn) =>
      _rootOverlayAccessor = fn;
}

/// [S3] 結果動作——四選一
enum ReceiptAction {
  vault, // 在向量資料庫開啟
  galaxy, // 在大腦圖譜開啟（飛近+自轉+預覽卡）
  canvas, // 匯入畫布（跳畫布頁→選畫布或開新）
  chat, // 匯入對話（跳對話頁→選對話或開新）
}

class ReceiptsSearchPanel extends StatefulWidget {
  const ReceiptsSearchPanel({
    super.key,
    this.initialQuery = '',
    this.initialResults = const ReceiptsResults(),
    required this.onAction,
    required this.onClose,
    required this.onStateSaved,
  });

  final String initialQuery;
  final ReceiptsResults initialResults;
  final void Function(ReceiptHop hop, ReceiptAction action) onAction;
  final VoidCallback onClose;
  final void Function(String query, ReceiptsResults results) onStateSaved;

  @override
  State<ReceiptsSearchPanel> createState() => _ReceiptsSearchPanelState();
}

class _ReceiptsSearchPanelState extends State<ReceiptsSearchPanel> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialQuery);
  final _focusNode = FocusNode();
  Timer? _debounce;
  late ReceiptsResults _results = widget.initialResults;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.onStateSaved(_controller.text, _results); // [S1] 關閉前存狀態
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _results = const ReceiptsResults());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), _doSearch);
  }

  Future<void> _doSearch() async {
    final q = _controller.text;
    if (q.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final r = await ReceiptsSearchService.instance.search(q);
      if (_controller.text.trim() != q.trim()) return; // 過期結果丟棄
      if (mounted) setState(() => _results = r);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(ReceiptHop hop, ReceiptAction action) {
    // [S1] 面板常駐——不 pop、不關閉，只執行動作（使用者繼續看其他結果）
    widget.onAction(hop, action);
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Positioned(
      top: 64,
      right: 24,
      width: 460,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 640),
          decoration: BoxDecoration(
            color: ds.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ds.borderDefault),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── 標題列（拖曳把手＋關閉鈕）──
              _buildTitleBar(ds),
              const Divider(height: 1),
              // ── 輸入框（真的縮短——右側明確空隙）──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 20, color: ds.textTertiary),
                    const SizedBox(width: 10),
                    // [S1] 輸入框縮短：不 Expanded 到底——固定 flex 留白給轉圈
                    Expanded(
                      flex: 5,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        onChanged: _onChanged,
                        style: TierStyle.of(context, Tier.cardTitle).toTextStyle(),
                        decoration: InputDecoration(
                          hintText: '搜尋對話、記憶、資產、任務…',
                          hintStyle: TierStyle.of(context, Tier.cardBody)
                              .toTextStyle()
                              .copyWith(color: ds.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    // [S1] 明確空隙：Expanded 空白佔位
                    const Expanded(flex: 2, child: SizedBox()),
                    if (_searching)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: ds.accentBlue),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // ── 結果 ──
              Flexible(
                child: _results.isEmpty && !_searching
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _controller.text.trim().isEmpty
                              ? '輸入關鍵字，搜尋你的整個第二大腦'
                              : '沒有找到相關結果',
                          style: TierStyle.of(context, Tier.cardBody)
                              .toTextStyle()
                              .copyWith(color: ds.textMuted),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          ..._section(context, '對話', Icons.chat_bubble_outline,
                              _results.conversations.length, () => [
                            for (final h in _results.conversations)
                              _row(
                                icon: Icons.chat_bubble_outline,
                                title: h.title,
                                subtitle: h.excerpt,
                                hop: h.hop,
                              ),
                          ]),
                          ..._section(context, '記憶', Icons.psychology_outlined,
                              _results.memories.length, () => [
                            for (final m in _results.memories)
                              _row(
                                icon: Icons.psychology_outlined,
                                title: _oneLine(m.content, 60),
                                subtitle: '${m.room} · 相關度 ${(m.score * 100).round()}%',
                                hop: ReceiptHop(
                                    domain: ReceiptDomain.memory, targetId: m.id),
                              ),
                          ]),
                          ..._section(context, '資產', Icons.folder_outlined,
                              _results.assets.length, () => [
                            for (final a in _results.assets)
                              _row(
                                icon: Icons.folder_outlined,
                                title: a.title ?? a.fileName,
                                subtitle: '${a.assetKind} · ${_oneLine(a.filePath, 50)}',
                                hop: ReceiptHop(
                                    domain: ReceiptDomain.asset, targetId: a.id),
                              ),
                          ]),
                          ..._section(context, '任務', Icons.rocket_launch_outlined,
                              _results.tasks.length, () => [
                            for (final t in _results.tasks)
                              _row(
                                icon: Icons.rocket_launch_outlined,
                                title: t.session.title,
                                subtitle:
                                    '${t.session.steps.length} 步 · ${taskStatusLabel(t.session.status)}',
                                hop: t.hop,
                              ),
                          ]),
                        ],
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('Esc 關閉',
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(color: ds.textMuted)),
                    const Spacer(),
                    Text('${_results.totalHits} 個結果',
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(color: ds.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(BridgeDSColors ds) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.travel_explore, size: 15, color: ds.textTertiary),
          const SizedBox(width: 8),
          Text('全局搜尋',
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle()),
          const Spacer(),
          // [S1] 明確關閉鈕——「除非我把它關掉」
          IconButton(
            icon: Icon(Icons.close, size: 16, color: ds.textMuted),
            tooltip: '關閉搜尋面板',
            onPressed: widget.onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    String label,
    IconData icon,
    int count,
    List<Widget> Function() buildRows,
  ) {
    if (count == 0) return [];
    final ds = BridgeDSColors.of(context);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Row(
          children: [
            Icon(icon, size: 13, color: ds.textMuted),
            const SizedBox(width: 6),
            Text('$label $count',
                style: TierStyle.of(context, Tier.cardCaptionBold)
                    .toTextStyle()
                    .copyWith(color: ds.textMuted)),
          ],
        ),
      ),
      ...buildRows(),
    ];
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required ReceiptHop hop,
  }) {
    final ds = BridgeDSColors.of(context);
    return InkWell(
      onTap: () => _pick(hop, hop.domain == ReceiptDomain.conversation
          ? ReceiptAction.chat
          : hop.domain == ReceiptDomain.task
              ? ReceiptAction.canvas // 任務域預設跳工作畫布
              : ReceiptAction.galaxy), // 記憶/資產預設大腦圖譜
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: ds.textTertiary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: ds.textMuted)),
                ],
              ),
            ),
            // [S3] 四動作鈕（記憶/資產域才有；hover 常駐顯示——桌面不需 hover 判斷）
            if (hop.domain == ReceiptDomain.memory ||
                hop.domain == ReceiptDomain.asset) ...[
              _actionBtn(ds, Icons.storage, '向量資料庫', hop, ReceiptAction.vault),
              _actionBtn(ds, Icons.auto_awesome, '星系', hop, ReceiptAction.galaxy),
              _actionBtn(ds, Icons.dashboard_outlined, '畫布', hop, ReceiptAction.canvas),
              _actionBtn(ds, Icons.chat_outlined, '對話', hop, ReceiptAction.chat),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(BridgeDSColors ds, IconData icon, String tooltip,
      ReceiptHop hop, ReceiptAction action) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: IconButton(
        icon: Icon(icon, size: 14, color: ds.textMuted),
        onPressed: () => _pick(hop, action),
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        padding: EdgeInsets.zero,
      ),
    );
  }

  String _oneLine(String s, int max) {
    final c = s.replaceAll('\n', ' ').trim();
    return c.length > max ? '${c.substring(0, max)}…' : c;
  }
}
