// MessageContextMenu — 訊息長按彈出選單
// [教練 Agent 2026-08-02]
//
// 共用元件，三個對話面板共用：
// 1. 回覆 — 設為回覆目標
// 2. 複製 — 複製到剪貼簿
// 3. 刪除 — 刪除這則訊息
// 4. 延伸話題（僅對話頁面）— 以這句話+上下文 5 則建立新對話

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/conversation.dart';
import '../../theme/bridge_design_system.dart';

/// 長按訊息選單
///
/// [showExtendTopic] = true 時顯示「延伸話題」選項（對話頁面用）
/// [onReply] 設為回覆目標
/// [onCopy] 複製文字（如不提供則用 Clipboard.setData）
/// [onDelete] 刪除訊息
/// [onExtendTopic] 延伸話題（帶上下文建立新對話）
class MessageContextMenu {
  static void show({
    required BuildContext context,
    required Message message,
    bool showExtendTopic = false,
    VoidCallback? onReply,
    VoidCallback? onDelete,
    VoidCallback? onExtendTopic,
  }) {
    final ds = BridgeDSColors.of(context);

    final actions = <_MenuAction>[
      _MenuAction(
        icon: Icons.reply_rounded,
        label: '回覆',
        onTap: onReply,
      ),
      _MenuAction(
        icon: Icons.copy_rounded,
        label: '複製',
        onTap: () {
          Clipboard.setData(ClipboardData(text: message.content));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('已複製'),
                duration: const Duration(milliseconds: 800),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
      _MenuAction(
        icon: Icons.delete_outline_rounded,
        label: '刪除',
        isDestructive: true,
        onTap: onDelete,
      ),
    ];

    if (showExtendTopic && onExtendTopic != null) {
      actions.insert(2, _MenuAction(
        icon: Icons.fork_right_rounded,
        label: '延伸話題',
        onTap: onExtendTopic,
      ));
    }

    // 過濾掉沒有 callback 的
    final activeActions = actions.where((a) => a.onTap != null).toList();
    if (activeActions.isEmpty) return;

    showMenu<_MenuAction>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 500, 0, 0),
      items: activeActions.map((action) {
        return PopupMenuItem<_MenuAction>(
          value: action,
          child: Row(
            children: [
              Icon(
                action.icon,
                size: 18,
                color: action.isDestructive ? ds.accentRed : ds.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(
                action.label,
                style: BridgeDS.body.copyWith(
                  color: action.isDestructive ? ds.accentRed : ds.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: ds.surface,
      elevation: 8,
    ).then((selected) {
      if (selected != null) {
        selected.onTap!();
      }
    });
  }

  /// 建立延伸話題：以 [centerMsg] 為中心，取前後各 2 則（共 5 則）
  /// 取以 [centerMsg] 為中心的上下文訊息（共 maxContext 則）
  /// 如果沒有後文，往前多取補足
  static List<Message> extractContextMessages({
    required List<Message> allMessages,
    required Message centerMsg,
    int maxContext = 5,
  }) {
    final centerIndex = allMessages.indexWhere((m) => m.id == centerMsg.id);
    if (centerIndex == -1) return [centerMsg];

    final total = allMessages.length;
    final halfRange = (maxContext - 1) ~/ 2; // = 2

    int start = (centerIndex - halfRange).clamp(0, total - 1);
    int end = (centerIndex + halfRange + 1).clamp(0, total);

    // 如果後面不夠（沒有後文），往前多取補足
    final actualEnd = end;
    final count = actualEnd - start;
    if (count < maxContext) {
      final shortage = maxContext - count;
      start = (start - shortage).clamp(0, start);
    }

    return allMessages.sublist(start, end < total ? end : total);
  }

  /// 從訊息內容擷取重點作為新對話標題（不超過 7 個字）
  static String extractTopicTitle(String content) {
    var title = content.trim();

    // 移除系統標記
    title = title
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (title.isEmpty) return '延伸話題';

    // 如果已經 <= 7 字，直接回傳
    if (title.length <= 7) return title;

    // 從前 7 字找最後一個斷句點
    final snippet = title.substring(0, title.length < 14 ? title.length : 14);
    final cutPoints = ['。', '，', '、', '；', '：', '？', '！', ' ', '\n', '．', '，', '的', '是', '在'];
    
    // 找 <= 7 字範圍內最後的截斷點
    for (int i = 6; i >= 3; i--) {
      if (i < snippet.length) {
        for (final c in cutPoints) {
          if (snippet[i] == c[0]) {
            return snippet.substring(0, i);
          }
        }
      }
    }

    // 找不到斷句點，取前 7 字
    return title.length > 7 ? '${title.substring(0, 7)}' : title;
  }
}

class _MenuAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isDestructive;

  _MenuAction({
    required this.icon,
    required this.label,
    this.onTap,
    this.isDestructive = false,
  });
}
