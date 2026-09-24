// api_usage_dashboard.dart
// [教練 Agent 2026-07-29] API 額度儀表板 — top bar BridgeChip 按鈕 + 浮動下拉面板
// 支援多 provider 分項顯示

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_usage_tracker.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class ApiUsageDashboard extends StatefulWidget {
  const ApiUsageDashboard({super.key});

  @override
  State<ApiUsageDashboard> createState() => _ApiUsageDashboardState();
}

class _ApiUsageDashboardState extends State<ApiUsageDashboard> {
  StreamSubscription<List<ProviderUsage>>? _sub;
  List<ProviderUsage>? _summary;
  bool _expanded = false;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  bool _hovering = false;

  // [教練 Agent 2026-07-29] 警告閾值輸入框控制器 — 必須持久化，
  // 避免每次 overlay rebuild 時重建 controller 導致使用者輸入被重設為預設值
  late TextEditingController _thresholdController;
  // 追蹤 tracker 端最後一次同步進 controller 的值，避免覆蓋使用者正在輸入的內容
  int? _lastSyncedThresholdMille;
  // 「套用」按鈕短暫顯示已套用狀態
  bool _thresholdJustApplied = false;

  @override
  void initState() {
    super.initState();
    _summary = ApiUsageTracker.instance.getTodaySummary();
    _initThresholdController();
    _sub = ApiUsageTracker.instance.usageStream.listen((s) {
      if (mounted) {
        setState(() => _summary = s);
        _overlayEntry?.markNeedsBuild();
      }
    });
    // [教練 Agent 2026-07-29] 從 SharedPreferences 載入自訂警告閾值並同步到 controller
    // init() 為 async，必須在 initState 內 fire-and-forget（不能在這裡 await）
    _loadPersistedThreshold();
  }

  /// [教練 Agent 2026-07-29] 初始化警告閾值輸入框，顯示目前值（單位：K tokens）
  void _initThresholdController() {
    final currentK = (ApiUsageTracker.instance.dailyWarningThreshold / 1000).round();
    _thresholdController = TextEditingController(text: '$currentK');
    _lastSyncedThresholdMille = currentK;
  }

  /// [教練 Agent 2026-07-29] 從 SharedPreferences 載入使用者自訂警告閾值後重新同步 controller。
  /// 因為 init() 是 async，initState 內的同步讀取會拿到預設值 100K，
  /// 必須在 prefs 載入後把 controller 更新為使用者實際設定的值。
  Future<void> _loadPersistedThreshold() async {
    try {
      await ApiUsageTracker.instance.init();
    } catch (_) {
      // init() 失敗不影響 UI 顯示,使用預設值即可
    }
    if (!mounted) return;
    final k = (ApiUsageTracker.instance.dailyWarningThreshold / 1000).round();
    if (k != _lastSyncedThresholdMille) {
      _thresholdController.text = '$k';
      _thresholdController.selection =
          TextSelection.collapsed(offset: _thresholdController.text.length);
      _lastSyncedThresholdMille = k;
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _sub?.cancel();
    _thresholdController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _togglePanel() {
    if (_expanded) {
      _removeOverlay();
      setState(() => _expanded = false);
    } else {
      _overlayEntry = OverlayEntry(builder: (_) => _buildFloatingPanel());
      Overlay.of(context).insert(_overlayEntry!);
      setState(() => _expanded = true);
    }
  }

  int get _totalTokens => ApiUsageTracker.instance.todayTotalTokens;

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final tracker = ApiUsageTracker.instance;
    final isWarning = tracker.isWarningLevel;
    final isLimit = tracker.isLimitLevel;

    final accentColor = isLimit
        ? ds.accentRed
        : isWarning
            ? ds.accentYellow
            : ds.accentGreen;

    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: _togglePanel,
          child: AnimatedContainer(
            duration: BridgeDS.durationFast,
            curve: BridgeDS.transitionSpring,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _expanded
                  ? accentColor.withValues(alpha: 0.15)
                  : (_hovering
                      ? ds.surfaceGlassHover
                      : ds.surfaceGlass),
              borderRadius: BorderRadius.circular(BridgeDS.roundPill),
              border: Border.all(
                color: _expanded
                    ? accentColor.withValues(alpha: 0.4)
                    : (_hovering ? ds.borderSubtle : Colors.transparent),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, size: 14, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  'API ${_formatTokens(_totalTokens)}',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w500,
                    color: ds.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: ds.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingPanel() {
    final ds = BridgeDSColors.of(context);
    final summary = _summary ?? [];
    final tracker = ApiUsageTracker.instance;
    final isWarning = tracker.isWarningLevel;
    final isLimit = tracker.isLimitLevel;
    final totalTokens = tracker.todayTotalTokens;

    final accentColor = isLimit
        ? ds.accentRed
        : isWarning
            ? ds.accentYellow
            : ds.accentGreen;

    return Stack(
      children: [
        // 點擊外部關閉
        GestureDetector(
          onTap: () {
            _removeOverlay();
            if (mounted) setState(() => _expanded = false);
          },
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        // 浮動面板
        CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 8),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 340, // [教練 Agent 2026-08-05] 從 300 擴到 340，容納「警告量 1000 K tokens」chip 不 overflow
              constraints: const BoxConstraints(maxHeight: 500),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ds.surfaceElevated.withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── 標題列 ──
                    Row(
                      children: [
                        Icon(Icons.bolt, size: 16, color: accentColor),
                        const SizedBox(width: 6),
                        Text('API 額度', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600, color: ds.textPrimary)),
                        const Spacer(),
                        Text(
                          _formatTokens(totalTokens),
                          style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                            color: accentColor,
                            fontFeatures: const [FontFeature.tabularFigures()],),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // ── 進度條 ──
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (totalTokens / tracker.dailyWarningThreshold).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: ds.surfaceHover,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('0', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted)),
                        Text('警告 ${_formatTokens(tracker.dailyWarningThreshold)}', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── 各 Provider 分項 ──
                    if (summary.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text('尚無 API 使用記錄', style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted)),
                        ),
                      )
                    else ...[
                      Text(
                        '今日各服務用量',
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600, color: ds.textMuted),
                      ),
                      const SizedBox(height: 8),
                      ...summary.map((p) => _buildProviderRow(p, ds)),
                    ],

                    // ── 溫馨提醒 ──
                    if (isWarning) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: accentColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isLimit
                                    ? '今日用量較高，建議切換本地模型節省額度'
                                    : '今日用量接近警告值，請留意 API 額度',
                                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: accentColor),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // [教練 Agent 2026-07-29] 自訂警告閾值輸入框
                    const SizedBox(height: 12),
                    _buildWarningThresholdEditor(ds),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// [教練 Agent 2026-07-29] 警告閾值設定區 — 讓使用者自訂警告量（單位：K tokens）
  /// 使用持久化的 _thresholdController，避免 overlay rebuild 時輸入被重設
  Widget _buildWarningThresholdEditor(BridgeDSColors ds) {
    // [教練 Agent 2026-07-29] 嚴格限制：只允許正整數（不限上限），輸入「500」「1000」「5000」皆可。
    // 沒有 100 以下的上限，配合 [_thresholdController] 於 state-level 持久化保存。
    final inputFormatters = <TextInputFormatter>[
      FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
      LengthLimitingTextInputFormatter(7), // 7 位數上限 = 9,999,999 K tokens，足以容納任何合理閾值
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ds.canvas.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 14, color: ds.textMuted),
          const SizedBox(width: 6),
          Text(
            '警告量',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary),
          ),
          const SizedBox(width: 8),
          // [教練 Agent 2026-07-29] 加寬至 80px，容納 3 位數以上輸入（如 500、1000、5000）
          SizedBox(
            width: 80,
            child: TextField(
              controller: _thresholdController,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: inputFormatters,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: ds.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: ds.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: ds.accentBlue),
                ),
              ),
              onSubmitted: (value) => _applyThreshold(value),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'K tokens',
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted),
          ),
          const Spacer(),
          // [教練 Agent 2026-07-29] 套用成功短暫顯示「✓ 已套用」回饋（1.2s 後復原）
          if (_thresholdJustApplied)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '✓ 已套用',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentGreen),
              ),
            ),
          TextButton(
            onPressed: () => _applyThreshold(_thresholdController.text),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 28),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            ),
            child: Text(
              '套用',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentBlue),
            ),
          ),
        ],
      ),
    );
  }

  /// [教練 Agent 2026-07-29] 套用使用者輸入的警告閾值，不做任何 100 等上限限制。
  /// 任意正整數皆可（例如 500、1000、5000、9999 都會被視為 K tokens 寫入）。
  Future<void> _applyThreshold(String rawValue) async {
    final k = int.tryParse(rawValue.trim());
    if (k == null || k <= 0) return;
    await ApiUsageTracker.instance.setWarningThreshold(k * 1000);
    _lastSyncedThresholdMille = k;
    if (!mounted) return;
    setState(() {
      _thresholdJustApplied = true;
    });
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() => _thresholdJustApplied = false);
    });
  }

  /// 每個 provider 一行
  Widget _buildProviderRow(ProviderUsage p, BridgeDSColors ds) {
    final displayName = ApiUsageTracker.providerDisplayName(p.provider);
    final icon = p.isLocal ? '💻' : '☁️';
    final color = p.isLocal ? ds.accentBlue : ds.accentGreen;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: ds.canvas.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Provider 名稱 + 總量
            Row(
              children: [
                Text(icon, style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
                const SizedBox(width: 6),
                Text(
                  displayName,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600, color: ds.textPrimary),
                ),
                const Spacer(),
                Text(
                  _formatTokens(p.totalTokens),
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 明細
            Row(
              children: [
                _miniStat('${p.requestCount} 次', ds),
                const SizedBox(width: 8),
                _miniStat('↓ ${_formatTokens(p.inputTokens)}', ds),
                const SizedBox(width: 8),
                _miniStat('↑ ${_formatTokens(p.outputTokens)}', ds),
              ],
            ),
            // 該 provider 的進度條
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: (p.totalTokens / ApiUsageTracker.instance.dailyWarningThreshold).clamp(0.0, 1.0),
                minHeight: 2,
                backgroundColor: ds.surfaceHover,
                valueColor: AlwaysStoppedAnimation<Color>(color.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String text, BridgeDSColors ds) {
    return Text(
      text,
      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted, fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return '$tokens';
  }
}
