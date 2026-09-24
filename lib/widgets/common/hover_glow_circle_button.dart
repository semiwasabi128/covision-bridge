// _HoverGlowCircleButton — 共用 hover 顯著發光圓形按鈕
//
// [教練 Agent 2026-08-03] 跟 chat_screen.dart 的 FloatingActionButton.small 一樣
// 「滑鼠移過去會亮、視覺對比強」互動感。
//
// 為什麼不用 IconButton：IconButton 在 Material 透明背景上 hover 圈不顯眼，
// 而且視覺上「灰灰暗暗」— 跟 FAB 的實心背景對比差太多。
//
// 設計：
// - 預設：背景 color alpha 0.18（視覺對比明確）
// - hover：背景 alpha 0.3 + 微小 scale 1.05 + shadow 顯著
// - pressed：背景 alpha 0.4
// - 動畫：180ms curveOut
//
// 用法：
//   HoverGlowCircleButton(
//     icon: Icons.send,
//     color: BridgeDSColors.of(context).accentBlue,
//     tooltip: '送出',
//     onPressed: () {},
//   )

import 'package:flutter/material.dart';
import '../../theme/bridge_design_system.dart';

class HoverGlowCircleButton extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool disabled;
  final double size;
  final double iconSize;

  const HoverGlowCircleButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
    this.disabled = false,
    // [教練 Agent 2026-08-16 使用者回饋] 預設縮小 44→32 / icon 22→16——
    // 發送/語音/停止按鈕太佔空間。兩個聊天面板（對話頁＋畫布頁）
    // 都走此預設，一處改動全系統生效；需要大按鈕的呼叫處可自行覆寫。
    this.size = 32,
    this.iconSize = 16,
  });

  @override
  State<HoverGlowCircleButton> createState() => HoverGlowCircleButtonState();
}

class HoverGlowCircleButtonState extends State<HoverGlowCircleButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final isInteractive = !widget.disabled && widget.onPressed != null;

    // [教練 Agent 2026-08-03] 跟 chat_screen.dart 的 FloatingActionButton.small 完全一致
    // - 預設：實心背景（不再 alpha 0.18 — 那樣看起來霧霧的有膜）
    // - hover：背景顏色用 HSLColor.lighten 提亮（不靠 alpha）
    // - pressed：背景顏色用 HSLColor.darken 變深
    // - disabled：背景 gray，icon 灰
    final hsl = HSLColor.fromColor(color);
    final baseBg = widget.disabled
        ? BridgeDS.grey600  // 灰
        : (_pressed
            ? hsl.withLightness((hsl.lightness * 0.85).clamp(0.0, 1.0)).toColor()
            : (_hovered
                ? hsl.withLightness((hsl.lightness * 1.10).clamp(0.0, 1.0)).toColor()
                : color));
    final scale = _pressed ? 0.96 : (_hovered ? 1.05 : 1.0);
    final iconColor = widget.disabled
        ? Colors.white.withValues(alpha: 0.7)
        : Colors.white;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: isInteractive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: GestureDetector(
          onTapDown: isInteractive ? (_) => setState(() => _pressed = true) : null,
          onTapUp: isInteractive ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: isInteractive ? () => setState(() => _pressed = false) : null,
          onTap: isInteractive ? widget.onPressed : null,
          child: AnimatedScale(
            scale: scale,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                color: baseBg,
                shape: BoxShape.circle,
                // hover 顯著陰影
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.35),
                          blurRadius: 12,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  widget.icon,
                  size: widget.iconSize,
                  color: iconColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
