// embedding_progress_bar.dart
// [教練 Agent 2026-07-28] 全域浮動嵌入進度條
//
// 監聽 EmbeddingProgressTracker.progressStream，
// 在畫面底部顯示分階段進度條：
//   scanning  → 「掃描檔案中」
//   embedding → 「生成向量嵌入中」
//   completing→ 「收尾中」
//   done      → 顯示完成 1.5s 後自動消失
//   error     → 顯示錯誤 3s 後自動消失
//   idle      → 不顯示

import 'dart:async';

import 'package:bridge_app/services/vector_db/embedding_progress_tracker.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../theme/bridge_design_system.dart';

/// 全域浮動嵌入進度條。
///
/// 用 [Stack] + [Positioned] 放在畫面底部。
/// 無任務時回傳 [SizedBox.shrink]（不佔空間）。
class EmbeddingProgressBar extends StatefulWidget {
  const EmbeddingProgressBar({super.key});

  @override
  State<EmbeddingProgressBar> createState() => _EmbeddingProgressBarState();
}

class _EmbeddingProgressBarState extends State<EmbeddingProgressBar>
    with SingleTickerProviderStateMixin {
  StreamSubscription<EmbeddingProgress>? _sub;
  EmbeddingProgress _progress = EmbeddingProgress.idle;

  // 進度條出現/消失動畫
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));

    // 用當前快照初始化
    _progress = EmbeddingProgressTracker.instance.currentProgress;
    _updateVisibility();

    _sub = EmbeddingProgressTracker.instance.progressStream.listen((p) {
      if (!mounted) return;
      setState(() => _progress = p);
      _updateVisibility();
    });
  }

  void _updateVisibility() {
    if (_progress.isActive || _progress.stage == EmbeddingStage.done) {
      _animController.forward();
    } else if (_progress.stage == EmbeddingStage.error) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // idle 時完全不渲染
    if (_progress.stage == EmbeddingStage.idle &&
        !_animController.isAnimating) {
      return const SizedBox.shrink();
    }

    final ds = BridgeDSColors.of(context);
    final isVisible =
        _progress.isActive ||
        _progress.stage == EmbeddingStage.done ||
        _progress.stage == EmbeddingStage.error;

    if (!isVisible && _animController.value == 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: _buildBar(context, ds),
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context, BridgeDSColors ds) {
    final stageLabel = _stageLabel(_progress.stage, ds);
    final isError = _progress.stage == EmbeddingStage.error;
    final isDone = _progress.stage == EmbeddingStage.done;

    // 進度百分比
    final percent = isDone
        ? 100
        : isError
            ? _progress.percent
            : _progress.percent;

    // 進度條顏色
    final barColor = isError
        ? ds.accentRed
        : isDone
            ? ds.accentGreen
            : ds.accentPurple;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: ds.surfaceElevated.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: barColor.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: barColor.withValues(alpha: 0.08),
              blurRadius: 24,
              spreadRadius: 0,
            ),
          ],
        ),
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 第一行：階段圖示 + 標籤 + 百分比 ──
            Row(
              children: [
                // 階段圖示
                _stageIcon(_progress.stage, barColor),
                const SizedBox(width: 10),
                // 階段文字
                Expanded(
                  child: Text(
                    isError
                        ? '嵌入失敗'
                        : isDone
                            ? '嵌入完成'
                            : stageLabel,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary,
                      fontWeight: FontWeight.w600,),
                  ),
                ),
                // 百分比
                if (!isError)
                  Text(
                    '$percent%',
                    style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: barColor,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // ── 第二行：進度條本體 ──
            if (!isError) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: percent / 100.0,
                  minHeight: 6,
                  backgroundColor: ds.surfaceHover,
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
              // ── 第三行：目前檔名 + done/total ──
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_progress.currentFile != null &&
                      _progress.currentFile!.isNotEmpty &&
                      !isDone) ...[
                    Icon(
                      Icons.description_outlined,
                      size: 12,
                      color: ds.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _progress.currentFile!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted,),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  Text(
                    isDone
                        ? '${_progress.total} 個檔案已嵌入'
                        : '${_progress.done}/${_progress.total}',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],),
                  ),
                ],
              ),
            ] else ...[
              // 錯誤訊息
              Text(
                _progress.error ?? '未知錯誤',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentRed,),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 階段中文標籤
  String _stageLabel(EmbeddingStage stage, BridgeDSColors ds) {
    switch (stage) {
      case EmbeddingStage.scanning:
        return '掃描檔案中';
      case EmbeddingStage.embedding:
        return '生成向量嵌入中';
      case EmbeddingStage.completing:
        return '收尾中';
      case EmbeddingStage.done:
        return '嵌入完成';
      case EmbeddingStage.error:
        return '嵌入失敗';
      case EmbeddingStage.idle:
        return '';
    }
  }

  /// 階段圖示
  Widget _stageIcon(EmbeddingStage stage, Color color) {
    if (stage == EmbeddingStage.done) {
      return Icon(Icons.check_circle, size: 18, color: color);
    }
    if (stage == EmbeddingStage.error) {
      return Icon(Icons.error_outline, size: 18, color: color);
    }
    // 活動中 — 小旋轉動畫
    return SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}
