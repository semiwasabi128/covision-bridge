// [教練 Agent 2026-08-08] Stream Badge — 水流狀態指示器
//
// 顯示「你在哪條水流」「有幾條水流暫停中」的小徽章。
// 監聽 TransurfingEventBroadcaster，事件觸發時自動刷新。

import 'package:flutter/material.dart';

import '../../../services/brain_container/transurfing_engine.dart';
import '../../../services/brain_container/transurfing_event.dart';
import '../../../theme/app_theme.dart';

/// 水流狀態徽章——顯示當前水流和暫停的水流數量
class StreamBadge extends StatefulWidget {
  const StreamBadge({super.key});

  @override
  State<StreamBadge> createState() => _StreamBadgeState();
}

class _StreamBadgeState extends State<StreamBadge> {
  @override
  void initState() {
    super.initState();
    TransurfingEventBroadcaster.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    TransurfingEventBroadcaster.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final engine = TransurfingEngine.instance;
    final active = engine.activeStream;
    final pausedCount =
        engine.pausedStreams.length + engine.branchedStreams.length;

    // 沒有任何水流——不顯示
    if (active == null && pausedCount == 0) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (active != null) ...[
          Icon(
            Icons.waves,
            size: 14,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              active.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
            ),
          ),
        ],
        if (pausedCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$pausedCount 條水流等待回來',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                  ),
            ),
          ),
        ],
      ],
    );
  }
}
