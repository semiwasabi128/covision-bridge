import 'package:flutter/material.dart';

/// BreathingImage — 帶呼吸感的靜態立繪容器
///
/// [小葵 2026-09-13] Blue 拍板：動態 rig 封存後，「一點生命感」由呼吸動畫承擔。
/// 懸浮窗（Swift 端）、夥伴設定頁主形象、狀態圖組預覽共用同一套呼吸語彙：
/// 中心錨定微縮放 1.2%，單程 2.8s（慢呼吸），easeInEaseOut 無限往返。
///
/// 用途：讓使用者/開發者一眼看出「這個預覽是活的」。
class BreathingImage extends StatefulWidget {
  const BreathingImage({
    super.key,
    required this.child,
    this.enabled = true,
    this.scaleAmplitude = 0.012,
    this.period = const Duration(milliseconds: 2800),
    this.anchor = Alignment.center,
  });

  final Widget child;
  final bool enabled;

  /// 縮放幅度（1.0 → 1.0+amplitude）。1.2% = 安靜的呼吸。
  final double scaleAmplitude;

  /// 單程時長（放大或縮小各一次）。2.8s ≈ 成人靜息呼吸頻率。
  final Duration period;

  /// 呼吸擴散原點——縮放錨定在圖的哪個位置。
  /// center=整圖中心擴散；Alignment(0, 0.15)=胸口（全身立繹胸口約在中心略下方）
  /// → 胸口不動、身體從胸口起伏，更像「從胸腔呼吸」。
  /// [小葵 2026-09-13] Blue 提問「由某個點擴散放大」——Transform.scale 的
  /// alignment 原生支援，零額外成本。雙點擴散（兩手同時放大）需 fragment
  /// shader 局部變形，複雜度高暫不做（Blue 原則：不複雜化）。
  final Alignment anchor;

  @override
  State<BreathingImage> createState() => _BreathingImageState();
}

class _BreathingImageState extends State<BreathingImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    _scale = Tween<double>(begin: 1.0, end: 1.0 + widget.scaleAmplitude)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.enabled) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BreathingImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        alignment: widget.anchor,
        child: child,
      ),
      child: widget.child,
    );
  }
}
