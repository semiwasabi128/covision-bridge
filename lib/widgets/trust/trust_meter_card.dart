// trust_meter_card.dart
// [刀 6 K6.1 2026-09-08] 信任成長儀表板主面板。
//
// 訂閱 BudgetLedger（ChangeNotifier）——任何 record/settle 都會刷新。
// 預設顯示當前夥伴的信任進度（無 companion 概念時顯示全局）。

import 'package:flutter/material.dart';
import 'package:bridge_app/services/budget_ledger.dart';
import 'package:bridge_app/services/paid_action_gate.dart';
import 'package:bridge_app/services/trust/trust_score.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

class TrustMeterCard extends StatefulWidget {
  const TrustMeterCard({super.key});

  @override
  State<TrustMeterCard> createState() => _TrustMeterCardState();
}

class _TrustMeterCardState extends State<TrustMeterCard> {
  TrustScoreInputs? _inputs;
  TrustScore? _score;
  String _error = '';
  late final VoidCallback _listener;

  @override
  void initState() {
    super.initState();
    _listener = () {
      if (mounted) _refresh();
    };
    BudgetLedger.instance.addListener(_listener);
    _refresh();
  }

  @override
  void dispose() {
    BudgetLedger.instance.removeListener(_listener);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final stats = await BudgetLedger.instance.todayStats();
      final dupes = await BudgetLedger.instance.duplicatePromptsToday();
      if (!mounted) return;
      setState(() {
        _inputs = TrustScoreInputs(
          total: stats.total,
          ok: stats.ok,
          failed: stats.failed,
          duplicates: dupes,
        );
        _score = computeTrustScore(_inputs!);
        _error = '';
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    if (_error.isNotEmpty) {
      return _shell(ds, child: Text('⚠ 讀取失敗：$_error',
          style: TierStyle.of(context, Tier.cardBody)
              .toTextStyle()
              .copyWith(color: ds.accentRed)));
    }
    if (_score == null || _inputs == null) {
      return _shell(
        ds,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final pct = (_score!.score * 100).round();
    final i = _inputs!;
    return _shell(
      ds,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('🛡️', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
              const SizedBox(width: 8),
              Text('信任進度',
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle()),
              const Spacer(),
              _badge(ds, _score!.label, _badgeColor(_score!.label, ds)),
            ],
          ),
          const SizedBox(height: 12),
          // 進度條
          Stack(
            children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: ds.borderDefault,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              FractionallySizedBox(
                widthFactor: _score!.score,
                child: Container(
                  height: 12,
                  decoration: BoxDecoration(
                    color: _scoreColor(_score!.score, ds),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('$pct%',
              style: TierStyle.of(context, Tier.cardCaptionBold)
                  .toTextStyle()
                  .copyWith(color: _scoreColor(_score!.score, ds))),
          const SizedBox(height: 12),
          // 今日統計
          _statRow(ds, '📊 今日', '${DateTime.now().toIso8601String().substring(0, 10)}'),
          _statRow(ds, '  總呼叫', '${i.total} 筆'),
          _statRow(ds, '  成功', '${i.ok} 筆  ✅ ${(i.successRate * 100).round()}%'),
          _statRow(ds, '  浪費', '${i.duplicates} 筆  🔁 ${(i.wasteRate * 100).round()}%'),
          _statRow(ds, '  失敗', '${i.failed} 筆'),
          const SizedBox(height: 8),
          // 透明公式（人話解釋）
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ds.canvas,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_score!.whyHuman,
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: ds.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _statRow(BridgeDSColors ds, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: TierStyle.of(context, Tier.cardBody)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted)),
          const Spacer(),
          Text(value, style: TierStyle.of(context, Tier.cardBody).toTextStyle()),
        ],
      ),
    );
  }

  Widget _badge(BridgeDSColors ds, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TierStyle.of(context, Tier.cardCaptionBold)
              .toTextStyle()
              .copyWith(color: color)),
    );
  }

  Color _badgeColor(String label, BridgeDSColors ds) {
    switch (label) {
      case '高信任':
        return ds.accentGreen;
      case '中信任':
        return ds.accentBlue;
      case '成長中':
        return ds.accentYellow;
      default:
        return ds.textMuted;
    }
  }

  Color _scoreColor(double s, BridgeDSColors ds) {
    if (s >= 0.9) return ds.accentGreen;
    if (s >= 0.7) return ds.accentBlue;
    if (s >= 0.5) return ds.accentYellow;
    return ds.accentRed;
  }

  Widget _shell(BridgeDSColors ds, {required Widget child}) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ds.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ds.borderDefault),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 30),
        ],
      ),
      child: child,
    );
  }
}

/// [刀 6 K6.3] TrustMeter 全域 overlay——托盤/能力中心共用（常駐，Esc/點外關閉）
class TrustMeterOverlay {
  static OverlayEntry? _entry;

  static bool get isOpen => _entry != null;

  static void open(BuildContext context) {
    if (_entry != null) return; // 已開
    _entry = OverlayEntry(
      builder: (ctx) => GestureDetector(
        // 點外關閉（面板本體攔截）
        onTap: close,
        child: Material(
          color: Colors.black.withValues(alpha: 0.3),
          child: Stack(
            children: [
              const Positioned(
                top: 72,
                right: 28,
                child: TrustMeterCard(),
              ),
              // Esc 提示（右下）
              Positioned(
                right: 28,
                bottom: 28,
                child: Text(
                  'Esc 或點外面關閉',
                  style: TierStyle.of(ctx, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    Overlay.maybeOf(context, rootOverlay: true)?.insert(_entry!);
  }

  static void close() {
    _entry?.remove();
    _entry = null;
  }
}
