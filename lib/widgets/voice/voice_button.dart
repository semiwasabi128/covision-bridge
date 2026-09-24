// voice_button.dart — Toggle 語音按鈕
//
// 兩種互動模式：
// - 短按一下 → 雙向持續對話（GPT-Live 風格）
// - 長按不放 → 語音輸入文字（iMessage 風格，放開自動送出）
//
// [教練 Agent 2026-08-03] 改為 ValueListenable<double> 接真實音量
// - 上層提供 ValueNotifier（從 voice_speech_handler stream 寫入）
// - 內部用 ValueListenableBuilder 只重建波形 5 條 bar
// - 整個 panel 不重建（避免「地震」閃爍）
//
// [教練 Agent 2026-08-03] 加長按手勢：
// - onLongPressStart → 進入語音輸入文字模式
// - onLongPressEnd → 停止 + 自動送出文字

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/bridge_design_system.dart';

/// 當前語音模式
enum VoiceMode {
  idle, // 閒置
  listening, // 正在聽
  thinking, // 正在想
  speaking, // 正在說
}

class VoiceButton extends StatefulWidget {
  const VoiceButton({
    super.key,
    required this.mode,
    required this.onToggle,
    this.volume,
    this.onLongPressStart,  // [教練 Agent 2026-08-03] 長按開始（語音輸入模式）
    this.onLongPressEnd,    // [教練 Agent 2026-08-03] 長按結束（停止錄音+送出）
  });

  /// 當前語音模式
  final VoiceMode mode;

  /// 按鈕點擊回調（短按 → 雙向對話）
  /// idle → 開始對談
  /// 非 idle → 結束對談
  final VoidCallback onToggle;

  /// [教練 Agent 2026-08-03] 音頻振幅串流（0.0 ~ 1.0）
  /// 上層從 voice_speech_handler.amplitudeStream 包成 ValueNotifier 傳入
  /// VoiceButton 內部 ValueListenableBuilder 只重建波形 bar
  final ValueListenable<double>? volume;

  /// [教練 Agent 2026-08-03] 長按開始回調
  /// 觸發時：進入語音輸入文字模式（partial 寫入 controller）
  final VoidCallback? onLongPressStart;

  /// [教練 Agent 2026-08-03] 長按結束回調
  /// 觸發時：停止錄音 + 自動送出文字
  final VoidCallback? onLongPressEnd;

  @override
  State<VoiceButton> createState() => _VoiceButtonState();
}

class _VoiceButtonState extends State<VoiceButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _glowController;

  // [教練 Agent 2026-08-03] hover / pressed 狀態
  bool _hovered = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _updateAnimations();
  }

  @override
  void didUpdateWidget(VoiceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    switch (widget.mode) {
      case VoiceMode.idle:
        _pulseController.stop();
        _waveController.stop();
        _glowController.stop();
        break;
      case VoiceMode.listening:
        _pulseController.repeat();
        _waveController.repeat();
        _glowController.repeat(reverse: true);
        break;
      case VoiceMode.thinking:
        _pulseController.repeat();
        _waveController.stop();
        _glowController.stop();
        break;
      case VoiceMode.speaking:
        _pulseController.stop();
        _waveController.repeat();
        _glowController.repeat(reverse: true);
        break;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isActive = widget.mode != VoiceMode.idle;
    final color = _colorForMode(widget.mode, context);
    final isListening = widget.mode == VoiceMode.listening;

    final volumeScale = isListening ? 1.0 : 1.0;
    // [教練 Agent 2026-08-16 使用者回饋] 語音鈕縮小與發送/停止一致——
    // 原 idle 48 / active 52，改 idle 32 / active 36（跟 HoverGlowCircleButton
    // 的新預設 32 對齊，說話時稍大維持狀態感）。
    final baseSize = isActive ? 36.0 : 32.0;
    final scaledSize = baseSize * volumeScale;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTap: widget.onToggle,
        onLongPressStart: widget.onLongPressStart != null
            ? (_) {
                setState(() => _pressed = true);
                widget.onLongPressStart!();
              }
            : null,
        onLongPressEnd: widget.onLongPressEnd != null
            ? (_) {
                setState(() => _pressed = false);
                widget.onLongPressEnd!();
              }
            : null,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedBuilder(
          animation: Listenable.merge([_glowController, _pulseController]),
          builder: (context, _) {
            final glowIntensity = _glowController.isAnimating
                ? _glowController.value
                : (isActive ? 0.5 : 0.0);

            final glowAlpha = isListening
                ? 0.3 + 0.4 * glowIntensity
                : (isActive ? 0.2 + 0.2 * glowIntensity : 0.0);

            final glowBlur = isListening
                ? 12.0 + 12.0 * glowIntensity
                : (widget.mode == VoiceMode.speaking
                    ? 10.0 + 8.0 * glowIntensity
                    : (isActive ? 8.0 : 0.0));

            final ringScale = isListening
                ? 1.0 + 0.3 * _pulseController.value
                : 1.0;
            final ringAlpha = isListening
                ? (1.0 - _pulseController.value) * 0.4
                : 0.0;

            return SizedBox(
              width: scaledSize + 4, // [教練 Agent 2026-08-03] 縮小 padding (跟送出按鈕等距)
              height: scaledSize + 4,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── 脈動外環（listening 時波紋擴散）──
                  if (isListening)
                    Transform.scale(
                      scale: ringScale,
                      child: Container(
                        width: scaledSize,
                        height: scaledSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color.withValues(alpha: ringAlpha),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  // ── 主按鈕 ──
                  // [教練 Agent 2026-08-03] 麥克風按鈕語意：
                  // - idle → 灰
                  // - hover（idle）→ 仍灰 + 紅色光暈（hover 提示）
                  // - pressed → 深紅
                  // - listening → 紅
                  // - speaking → 藍
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: scaledSize,
                    height: scaledSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _pressed
                          ? BridgeDS.berlinRed
                          : (widget.mode == VoiceMode.listening
                              ? BridgeDS.alertRed
                              : color),
                      boxShadow: [
                        if (_hovered)
                          BoxShadow(
                            color: BridgeDS.alertRed.withValues(alpha: 0.55),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        if (isActive)
                          BoxShadow(
                            color: color.withValues(alpha: glowAlpha.clamp(0.0, 1.0)),
                            blurRadius: glowBlur,
                            spreadRadius: 2,
                          ),
                      ],
                    ),
                    child: _buildContent(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.mode) {
      case VoiceMode.idle:
        return const Icon(
          CupertinoIcons.mic,
          color: Colors.white,
          size: 16,
        );

      case VoiceMode.listening:
        // [教練 Agent 2026-08-03] 波形動畫：依據真實音量（ValueListenable）變化
        // - ValueListenableBuilder 只重建這 5 條 bar，不重建整個 panel
        // - 沒聲音時 bar 高度一致（靜止）
        final volume = widget.volume;
        return AnimatedBuilder(
          animation: _waveController,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (i) {
                // [教練 Agent 2026-08-03] 真實波形：中央高、兩側低（拋物線）
                // 5 條 bar 各自的「拋物線權重」:
                // i=0 → 0.3 / i=1 → 0.7 / i=2 → 1.0 / i=3 → 0.7 / i=4 → 0.3
                final posWeight = [0.3, 0.7, 1.0, 0.7, 0.3][i];
                // 每條 bar 自己的相位（讓 5 條各自動）
                final phase = (_waveController.value * 6.28 + i * 0.9) % 6.28;
                // 各自的微小擺動（5 條不同步）
                final wave = 0.4 + 0.6 * (0.5 + 0.5 * (math.sin(phase)));
                return ValueListenableBuilder<double>(
                  valueListenable: volume ?? ValueNotifier<double>(0.0),
                  builder: (context, v, _) {
                    // [教練 Agent 2026-08-03] 敏銳度 2x：用 sqrt 放大小音量
                    // v=0.1 → 0.316 (3.16x), v=0.2 → 0.447 (2.24x), v=0.5 → 0.707 (1.41x)
                    // 配合 44 倍幅度：v=0.1 中央 → 5 + 14*0.316*0.7 ≈ 8px（小聲也有感）
                    //              v=0.5 中央 → 5 + 44*0.707*1.0 ≈ 36px（中等音量大幅跳）
                    //              v=1.0 中央 → 5 + 44*1.0*1.0 = 49px
                    final vBoosted = math.sqrt(v);
                    // [教練 Agent 2026-08-16] 波形高度等比縮小（鈕徑 48→32）
                    final height = 3.5 + vBoosted * 28.0 * posWeight * wave;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 3,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                );
              }),
            );
          },
        );

      case VoiceMode.thinking:
        // 載入動畫 — 旋轉圓圈
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            return Transform.rotate(
              angle: _pulseController.value * 6.28,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
          },
        );

      case VoiceMode.speaking:
        // 說話動畫 — 圓形波紋從中心擴散
        return AnimatedBuilder(
          animation: _waveController,
          builder: (context, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) {
                final phase = (_waveController.value * 6.28 + i * 2.1) % 6.28;
                final scale = 0.5 + 0.5 * (0.5 + 0.5 * math.sin(phase));
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.5 + 0.5 * scale),
                  ),
                );
              }),
            );
          },
        );
    }
  }

  Color _colorForMode(VoiceMode mode, BuildContext context) {
    final ds = BridgeDSColors.of(context);
    switch (mode) {
      case VoiceMode.idle:
        return ds.textMuted; // 灰色 — 閒置
      case VoiceMode.listening:
        return ds.accentRed; // 紅色 — 正在聽
      case VoiceMode.thinking:
        return ds.accentYellow; // 橙黃色 — 正在想
      case VoiceMode.speaking:
        return ds.accentBlue; // 藍色 — 正在說
    }
  }
}
