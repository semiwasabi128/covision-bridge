// Bridge App 全域鍵盤快捷鍵系統
// 使用 Flutter 的 Shortcuts + Actions 機制
//
// 快捷鍵清單：
// Cmd+1 → 對話 (tab 0)
// Cmd+2 → 畫布 (tab 1)
// Cmd+3 → 專案 (tab 2)
// Cmd+4 → 大腦 (tab 3)
// Cmd+5 → 向量資料庫 (tab 4)
// Cmd+6 → 系統 (tab 5)
// Cmd+K → Quick Assistant 隨身小幫手
// Cmd+, → 系統設定頁
// Cmd+D → 切換深色/淺色主題
// Cmd + / = → 放大字體（無障礙，老花眼友善）
// Cmd - → 縮小字體
// Cmd 0 → 重置字體為 100%

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/chat_controller.dart';
import '../screens/bridge_desktop_screen.dart';
import '../state/typography_scale_provider.dart';
import '../state/theme_provider.dart';
import '../widgets/quick_assistant_panel.dart';

/// 指定 tab 的 Intent
class NavigateToTabIntent extends Intent {
  final String tabName;
  const NavigateToTabIntent(this.tabName);
}

/// [羅盤 2026-09-06] 切到羅盤系統（測試用快捷鍵 Cmd+Shift+C）
class NavigateToCompassIntent extends Intent {
  const NavigateToCompassIntent();
}

/// [收據搜尋 2026-09-08] 全局搜尋（Cmd+Shift+F）
class OpenReceiptsSearchIntent extends Intent {
  const OpenReceiptsSearchIntent();
}

/// 切換主題的 Intent
class ToggleThemeIntent extends Intent {
  const ToggleThemeIntent();
}

/// [教練 Agent 2026-08-04] Phase E+ v1.1：字體縮放 Intent（無障礙）
class IncreaseFontScaleIntent extends Intent {
  const IncreaseFontScaleIntent();
}

class DecreaseFontScaleIntent extends Intent {
  const DecreaseFontScaleIntent();
}

class ResetFontScaleIntent extends Intent {
  const ResetFontScaleIntent();
}

/// 跳轉到系統設定頁的 Intent
class NavigateToSettingsIntent extends Intent {
  const NavigateToSettingsIntent();
}

/// 開啟 Quick Assistant 的 Intent
class OpenQuickAssistantIntent extends Intent {
  const OpenQuickAssistantIntent();
}

/// Bridge App 全域 Shortcuts Widget
/// 需要傳入 ChatController（桌面主聊天的 controller）
class BridgeShortcuts extends StatelessWidget {
  final Widget child;
  final ChatController? chatController;

  const BridgeShortcuts({
    super.key,
    required this.child,
    this.chatController,
  });

  @override
  Widget build(BuildContext context) {
    // [教練 Agent 2026-08-03] 註冊全域 controller accessor — 讓 QuickAssistantManager 能取
    QuickAssistantManager.activeControllerAccessor = () =>
        BridgeDesktopScreen.activeChatController.value;

    return Shortcuts(
      shortcuts: {
        // Cmd+1 → 對話
        const SingleActivator(LogicalKeyboardKey.digit1, meta: true):
            const NavigateToTabIntent('chat'),
        // Cmd+2 → 畫布
        const SingleActivator(LogicalKeyboardKey.digit2, meta: true):
            const NavigateToTabIntent('canvas'),
        // Cmd+3 → 專案
        const SingleActivator(LogicalKeyboardKey.digit3, meta: true):
            const NavigateToTabIntent('project'),
        // Cmd+4 → 大腦
        const SingleActivator(LogicalKeyboardKey.digit4, meta: true):
            const NavigateToTabIntent('brain'),
        // Cmd+5 → 向量資料庫
        const SingleActivator(LogicalKeyboardKey.digit5, meta: true):
            const NavigateToTabIntent('vault'),
        // Cmd+6 → 系統
        const SingleActivator(LogicalKeyboardKey.digit6, meta: true):
            const NavigateToTabIntent('system'),
        // [羅盤 2026-09-06] Cmd+Shift+C → 開啟羅盤系統（測試 / 開發用快捷鍵）
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true):
            const NavigateToCompassIntent(),
        // [收據搜尋 2026-09-08] Cmd+Shift+F → 全局搜尋
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
            const OpenReceiptsSearchIntent(),
        // Cmd+, → 系統設定頁
        const SingleActivator(LogicalKeyboardKey.comma, meta: true):
            const NavigateToSettingsIntent(),
        // Cmd+K → Quick Assistant
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            const OpenQuickAssistantIntent(),
        // Cmd+D → 切換主題
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true):
            const ToggleThemeIntent(),
        // [教練 Agent 2026-08-04] Phase E+ v1.1：字體縮放快速鍵（無障礙）
        // Cmd + / = → 放大字體
        const SingleActivator(LogicalKeyboardKey.equal, meta: true):
            const IncreaseFontScaleIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadAdd, meta: true):
            const IncreaseFontScaleIntent(),
        // Cmd - → 縮小字體
        const SingleActivator(LogicalKeyboardKey.minus, meta: true):
            const DecreaseFontScaleIntent(),
        // Cmd 0 → 重置字體
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true):
            const ResetFontScaleIntent(),
      },
      child: Actions(
        actions: {
          NavigateToTabIntent: CallbackAction<NavigateToTabIntent>(
            onInvoke: (intent) {
              BridgeDesktopScreen.navigateTo(intent.tabName);
              return null;
            },
          ),
          NavigateToSettingsIntent: CallbackAction<NavigateToSettingsIntent>(
            onInvoke: (intent) {
              BridgeDesktopScreen.navigateTo('system');
              return null;
            },
          ),
          OpenQuickAssistantIntent: CallbackAction<OpenQuickAssistantIntent>(
            onInvoke: (intent) {
              // [教練 Agent 2026-08-03] 簡化：傳 null 讓 QuickAssistantManager 自己取
              if (QuickAssistantManager.isOpen) {
                QuickAssistantManager.close();
              } else {
                QuickAssistantManager.open(context, chatController, 'any-page');  // [教練 Agent 2026-08-03] 簡化：先傳 any-page
              }
              return null;
            },
          ),
          ToggleThemeIntent: CallbackAction<ToggleThemeIntent>(
            onInvoke: (intent) {
              // [教練 Agent 2026-08-18 使用者 抓包] Cmd+D 無反應根因：
              // 舊代碼呼叫 ThemeController（死的舊系統，沒人監聽）。
              // App 實際主題 = ThemeProvider（主題包系統）——改呼叫 cycleToNext。
              ThemeProvider.instance.cycleToNext();
              return null;
            },
          ),
          // [教練 Agent 2026-08-04] Phase E+ v1.1：字體縮放 callback
          IncreaseFontScaleIntent: CallbackAction<IncreaseFontScaleIntent>(
            onInvoke: (intent) {
              TypographyScaleProvider.instance.increase();
              return null;
            },
          ),
          DecreaseFontScaleIntent: CallbackAction<DecreaseFontScaleIntent>(
            onInvoke: (intent) {
              TypographyScaleProvider.instance.decrease();
              return null;
            },
          ),
          // [羅盤 2026-09-06] Cmd+Shift+C callback
          NavigateToCompassIntent: CallbackAction<NavigateToCompassIntent>(
            onInvoke: (intent) {
              BridgeDesktopScreen.navigateToCompass?.call();
              return null;
            },
          ),
          // [收據搜尋 2026-09-08] Cmd+Shift+F callback
          OpenReceiptsSearchIntent: CallbackAction<OpenReceiptsSearchIntent>(
            onInvoke: (intent) {
              BridgeDesktopScreen.navigateToReceiptsSearch?.call();
              return null;
            },
          ),
          ResetFontScaleIntent: CallbackAction<ResetFontScaleIntent>(
            onInvoke: (intent) {
              TypographyScaleProvider.instance.reset();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
