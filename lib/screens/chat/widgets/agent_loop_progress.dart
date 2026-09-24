import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// [教練 Agent S21d] Agent Loop 進度條 widget。
///
/// 顯示當前 Agent Loop 的輪數、工具名稱、工具狀態及進度條。
class AgentLoopProgress extends StatelessWidget {
  final int turn;
  final int maxTurns;
  final String? toolName;
  final String? toolStatus;

  /// [小葵 2026-09-18 Hermes 式透明化] 思路+動作日誌——
  /// Blue 拍板：過程不能是黑箱，要看得到 agent 的思路與動作，才能插嘴修正方向。
  final List<String> activityLog;

  const AgentLoopProgress({
    super.key,
    required this.turn,
    required this.maxTurns,
    this.toolName,
    this.toolStatus,
    this.activityLog = const [],
  });

  static const _toolLabels = {
    'web_search': '搜尋網路',
    'image_recognition': '辨識圖片',
    'generate_image': '生成圖片',
    'create_document': '產出文件',
    'desktop_files': '整理檔案',
    'memory_search': '搜尋記憶',
    'browser_navigate': '瀏覽網頁',
    'browser_screenshot': '截取畫面',
    'browser_click': '點擊元素',
    // [教練 Agent 2026-07-29] 補充完整工具翻譯
    'read_source_file': '讀取檔案',
    'patch_source_file': '修改檔案',
    'run_terminal': '執行指令',
    'restart_app': '重啟 App',
    'canvas_get_state': '查看畫布',
    'canvas_place': '放置節點',
    'canvas_connect': '連接節點',
    'canvas_remove_node': '移除節點',
    'canvas_remove': '移除節點',
    'canvas_send_chat': '畫布對話',
    'canvas_get_annotations': '查看標注',
    'canvas_execute': '執行工作流',
    'screen_capture': '截取畫面',
    'browse': '瀏覽網頁',
    'vision': '視覺分析',
    'document': '文件處理',
    'local_vision_analyze': '本地視覺分析',
    'local_code_generate': '本地程式碼生成',
    'video_download': '下載影片',
    'frame_extract': '影片截幀',
    'audio_transcribe': '語音轉文字',
    'delegate_subagent': '分派子代理',
    'delegate_batch': '批次分派',
  };

  static const _statusLabels = {
    'success': '完成',
    'failed': '失敗',
  };

  @override
  Widget build(BuildContext context) {
    final toolLabel =
        toolName != null ? (_toolLabels[toolName!] ?? toolName) : null;
    final statusLabel =
        toolStatus != null ? (_statusLabels[toolStatus!] ?? toolStatus) : null;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDS.darkPanel.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: BridgeDS.toolPurple.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
          // 輪數指示器
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: BridgeDS.toolPurple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$turn/$maxTurns',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.toolPurpleLight,
                fontWeight: FontWeight.w600,),
            ),
          ),
          const SizedBox(width: 10),
          // 工具名稱
          if (toolLabel != null) ...[
            Icon(
              toolStatus == 'failed'
                  ? Icons.error_outline
                  : Icons.build_outlined,
              size: 14,
              color: toolStatus == 'failed'
                  ? BridgeDSColors.of(context).accentRed
                  : BridgeDS.softGreen,
            ),
            const SizedBox(width: 6),
            Text(
              toolLabel,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: toolStatus == 'failed'
                    ? BridgeDSColors.of(context).accentRed
                    : BridgeDS.lightGray,),
            ),
            if (statusLabel != null) ...[
              const SizedBox(width: 6),
              Text(
                '· $statusLabel',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted.withValues(alpha: 0.7),),
              ),
            ],
          ] else
            Text(
              '思考中…',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: AppTheme.textMuted.withValues(alpha: 0.8),),
            ),
          const Spacer(),
          // 進度條
          SizedBox(
            width: 60,
            height: 3,
            child: LinearProgressIndicator(
              value: maxTurns >= 1000 ? (turn / 50).clamp(0.0, 1.0) : turn / maxTurns,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(BridgeDS.toolPurple),
            ),
          ),
            ],
          ),
          // [小葵 2026-09-18] 思路+動作日誌——最近 3 行，Hermes 式透明化
          if (activityLog.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...activityLog.takeLast(3).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final line = entry.value;
              final isLatest = i == 2 || i == activityLog.length - 1;
              return Opacity(
                opacity: isLatest ? 0.95 : (i == 1 ? 0.6 : 0.35),
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardBody)
                        .toTextStyle()
                        .copyWith(
                          fontSize: 11,
                          color: isLatest
                              ? BridgeDS.toolPurpleLight
                              : AppTheme.textMuted,
                        ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int n) =>
      length <= n ? this : sublist(length - n);
}
