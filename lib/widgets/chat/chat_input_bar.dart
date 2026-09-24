// [以利沙 Sprint 3 2026-06-24]
// ChatInputBar — 獨立的輸入列 widget，從 chat_screen.dart 抽出。
// [教練 Agent 2026-07-28] 改為 StatefulWidget — 用 AnimatedBuilder 監聽 controller
// 來切換 suffixIcon，避免 parent rebuild 時重建 TextField 導致外部語音
// 輸入法（Open Whisper）的 paste 操作被重複觸發。
// [教練 Agent 2026-07-29] 修復 Enter 鍵行為：Enter = 新增行、Cmd+Enter / Shift+Enter = 送出

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import 'package:bridge_app/widgets/trust/trust_loop_ticker.dart'; // [刀 6 K6.4]

/// 聊天輸入列（圖片按鈕 + TextField + 送出）。
///
/// 接受來自 [ChatScreenState] 的 callback，不直接持有任何 service。
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isLoading,
    required this.onSend,
    required this.onPickImage,
    required this.onClearDraft,
    this.onNewConversation,
    this.onDispatchTask, // [隊友訊息流 C3] 派工鈕——null 時不顯示
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLoading;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onClearDraft;
  final VoidCallback? onNewConversation;

  /// [隊友訊息流 C3 2026-09-08] 派工——把輸入框文字直接派給背景夥伴。
  /// Phase 1 明示派工（設計稿 §4.1）：按下去 = 明確 TaskSession，零誤判。
  final VoidCallback? onDispatchTask;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  /// [教練 Agent 2026-07-29] 攔截 Enter 鍵：
  /// - Cmd+Enter 或 Shift+Enter → 送出
  /// - 純 Enter → 換行（不攔截）
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // 只處理 Enter 鍵
    if (key != LogicalKeyboardKey.enter && key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }

    final isCmd = HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCmd || isShift) {
      widget.onSend();
      return KeyEventResult.handled;
    }

    // 純 Enter → 讓 TextField 處理換行（不攔截）
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // [刀 6 K6.4 2026-09-08] 信任 loop 跑馬燈——做事→回報→檢討→升級
            // （看得到但不打擾：事件滑入 4s 淡出，不搶焦點）
            const TrustLoopTicker(),
            Row(
              children: [
                // 新增對話
                if (widget.onNewConversation != null)
                  Semantics(
                    label: '新增對話',
                    button: true,
                    child: IconButton(
                      icon: Icon(
                        Icons.add_comment_outlined,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      onPressed: widget.onNewConversation,
                      tooltip: '新增對話',
                    ),
                  ),
                // [隊友訊息流 C3 2026-09-08] 派工鈕——火箭圖標，
                // 與附件鈕同組（輸入列左側動作區），Phase 1 明示派工入口
                if (widget.onDispatchTask != null)
                  Semantics(
                    label: '派工給夥伴',
                    button: true,
                    child: IconButton(
                      icon: Icon(
                        Icons.rocket_launch_outlined,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      onPressed: widget.onDispatchTask,
                      tooltip: '派工給夥伴（背景執行，不佔用對話）',
                    ),
                  ),
                // 上傳圖片/檔案
                Semantics(
                  label: '上傳圖片或檔案',
                  button: true,
                  child: IconButton(
                    icon: Icon(
                      Icons.attach_file_outlined,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    onPressed: widget.onPickImage,
                    tooltip: '上傳圖片或檔案',
                  ),
                ),
                Expanded(
                  // [教練 Agent 2026-08-03] Stack 包 TextField + partial 浮層
                  child: Stack(
                    children: [
                      TextField(
                        key: const ValueKey('chat-message-input'),
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        // [教練 Agent 2026-07-29] 不再使用 onSubmitted 送出
                        // Enter 由 _handleKeyEvent 攔截，純 Enter 換行
                        maxLines: null,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: '輸入訊息...',
                          hintStyle: TextStyle(color: ds.textMuted),
                          filled: true,
                          fillColor: ds.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          // [教練 Agent 2026-07-28] 用 AnimatedBuilder 監聽 controller
                          // 只重建 suffixIcon，不重建整個 TextField
                          suffixIcon: AnimatedBuilder(
                            animation: widget.controller,
                            builder: (context, _) {
                              return widget.controller.text.isEmpty
                                  ? const SizedBox.shrink()
                                  : Semantics(
                                      label: '清除輸入',
                                      button: true,
                                      child: IconButton(
                                        icon: const Icon(Icons.clear, size: 18, color: AppTheme.textSecondary),
                                        onPressed: widget.onClearDraft,
                                        tooltip: '清除輸入',
                                      ),
                                    );
                            },
                          ),
                        ),
                      ),
                      ],
                  ),
                ),
                const SizedBox(width: 8),
                // 送出按鈕
                Semantics(
                  label: '發送訊息',
                  button: true,
                  child: FloatingActionButton.small(
                    key: const ValueKey('chat-send-button'),
                    heroTag: 'sendBtn',
                    backgroundColor: AppTheme.primary,
                    onPressed: widget.onSend,
                    tooltip: '發送訊息',
                    child: Icon(Icons.send, color: ds.textPrimary),
                  ),
                ),
              ],
            ),
            // [教練 Agent 2026-07-29] 輸入框下方小字提示
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 48),
              child: Text(
                'Enter 新增行 · Cmd+Enter 送出',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
