// trust_loop_ticker.dart
// [刀 6 K6.4 2026-09-08] 對話頁底部跑馬燈——loop 可見化的最前線。
//
// 吃 TrustLoop 事件流：回報/檢討/升級事件以一條小條滑入（4s 自動淡出），
// 不阻擋輸入、不搶焦點——「看得到但不打擾」。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bridge_app/services/trust/trust_loop.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

class TrustLoopTicker extends StatefulWidget {
  const TrustLoopTicker({super.key});

  @override
  State<TrustLoopTicker> createState() => _TrustLoopTickerState();
}

class _TrustLoopTickerState extends State<TrustLoopTicker> {
  StreamSubscription<TrustLoopEvent>? _sub;
  TrustLoopEvent? _current;
  Timer? _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _sub = TrustLoop.instance.stream.listen(_onEvent);
  }

  void _onEvent(TrustLoopEvent e) {
    if (!mounted) return;
    _hideTimer?.cancel();
    setState(() {
      _current = e;
      _visible = true;
    });
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_current == null) return const SizedBox.shrink();
    final ds = BridgeDSColors.of(context);
    final color = switch (_current!.kind) {
      'upgrade' => ds.accentGreen,
      'downgrade' => ds.accentRed,
      'review' => ds.accentBlue,
      _ => ds.textMuted,
    };
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: _visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: ds.surfaceElevated,
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(_current!.kind), size: 13, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _current!.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String kind) => switch (kind) {
        'upgrade' => Icons.military_tech_outlined,
        'downgrade' => Icons.trending_down,
        'review' => Icons.rate_review_outlined,
        _ => Icons.campaign_outlined,
      };
}
