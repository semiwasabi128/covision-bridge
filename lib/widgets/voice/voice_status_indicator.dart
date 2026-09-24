// voice_status_indicator.dart — Agent 狀態指示器
//
// 顯示 Agent 當前的語音對談狀態：
// - 聽（listening）— 波形動畫 + 「正在聽...」
// - 想（thinking）— 載入動畫 + 「正在思考...」
// - 說（speaking）— 音波動畫 + 「正在回覆...」
//
// 放在聊天介面上方或輸入框旁邊，讓使用者隨時知道 Agent 在做什麼

import 'package:flutter/cupertino.dart';
import '../../theme/bridge_design_system.dart';
import 'voice_button.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// Agent 語音狀態指示器
///
/// 當 VoiceMode 不是 idle 時顯示一個小條狀指示器
class VoiceStatusIndicator extends StatelessWidget {
  const VoiceStatusIndicator({
    super.key,
    required this.mode,
    this.statusText,
  });

  /// 當前語音模式
  final VoiceMode mode;

  /// 自訂狀態文字（例如第三層現況回報的文字）
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    if (mode == VoiceMode.idle) return const SizedBox.shrink();

    final color = _colorForMode(mode, context);
    final label = statusText ?? _labelForMode(mode);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey('${mode.name}_$label'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIcon(color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color,
                  fontWeight: FontWeight.w500,),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(Color color) {
    switch (mode) {
      case VoiceMode.listening:
        return _PulsingDot(color: color);
      case VoiceMode.thinking:
        return SizedBox(
          width: 12,
          height: 12,
          child: CupertinoActivityIndicator(
            color: color,
            radius: 6,
          ),
        );
      case VoiceMode.speaking:
        return _SoundBars(color: color);
      case VoiceMode.idle:
        return const SizedBox.shrink();
    }
  }

  Color _colorForMode(VoiceMode mode, BuildContext context) {
    final ds = BridgeDSColors.of(context);
    switch (mode) {
      case VoiceMode.idle:
        return ds.textMuted;
      case VoiceMode.listening:
        return ds.accentRed;
      case VoiceMode.thinking:
        return ds.accentYellow;
      case VoiceMode.speaking:
        return ds.accentBlue;
    }
  }

  String _labelForMode(VoiceMode mode) {
    switch (mode) {
      case VoiceMode.idle:
        return '';
      case VoiceMode.listening:
        return '正在聽...';
      case VoiceMode.thinking:
        return '正在思考...';
      case VoiceMode.speaking:
        return '正在回覆...';
    }
  }
}

/// 脈動圓點 — 用於 listening 狀態
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..value = 0.5;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: 8 + _controller.value * 4,
          height: 8 + _controller.value * 4,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}

/// 音波條 — 用於 speaking 狀態
class _SoundBars extends StatefulWidget {
  const _SoundBars({required this.color});
  final Color color;

  @override
  State<_SoundBars> createState() => _SoundBarsState();
}

class _SoundBarsState extends State<_SoundBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..addListener(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return SizedBox(
          width: 14,
          height: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final h = 4.0 +
                  8.0 *
                      (0.5 +
                          0.5 *
                              (_controller.value + i * 0.33) %
                                  1.0).abs();
              return Container(
                width: 2,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
