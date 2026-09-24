// asset_preview.dart
// [教練 Agent 2026-08-21] Agent 自律——畫布成果大預覽層
//
// 使用者：「無論是音樂影片文章圖片…所有工作流的成果都要在畫布中
// 有一個大大的預覽機制」。
//
// 現況：圖片有縮圖（_lastImageB64）；影片/音樂只有文字 output 裡
// 一條 URL；長文章擠在文字框。全部升級為統一大預覽：
//   - 圖片 → 全幅 Image
//   - 影片 → media_kit 播放器（可播）
//   - 音樂 → media_kit 播放器＋聲波裝飾
//   - 文章 → 大字級可捲動全文
//
// 進入方式：點節點上的「查看成果」按鈕（NodeWidget preview 區塊）
// 或點節點本體（node_detail_panel 既有行為保留）。

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';

/// 成果大預覽對話框——任何工作流產出都值得被好好看見
Future<void> showAssetPreview(
  BuildContext context, {
  required String title,
  Uint8List? imageBytes,
  String? imageUrl,
  String? videoUrl,
  String? audioUrl,
  String? articleText,
}) {
  return showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(48),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(ctx).surfaceElevated,
          borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
          border: Border.all(color: BridgeDSColors.of(ctx).borderDefault),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題列
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: BridgeDSColors.of(ctx).borderDefault)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TierStyle.of(ctx, Tier.bodyPrimary).toTextStyle(),
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),
            // 內容區
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _PreviewBody(
                  imageBytes: imageBytes,
                  imageUrl: imageUrl,
                  videoUrl: videoUrl,
                  audioUrl: audioUrl,
                  articleText: articleText,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PreviewBody extends StatefulWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;
  final String? videoUrl;
  final String? audioUrl;
  final String? articleText;
  const _PreviewBody({
    this.imageBytes,
    this.imageUrl,
    this.videoUrl,
    this.audioUrl,
    this.articleText,
  });

  @override
  State<_PreviewBody> createState() => _PreviewBodyState();
}

class _PreviewBodyState extends State<_PreviewBody> {
  Player? _player;
  VideoController? _controller;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  void _initPlayer(String url) {
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player!);
    // 本地檔案路徑轉 file:// URI，http(s) 原樣通過
    final uri = url.contains('://') ? url : Uri.file(url).toString();
    _player!.open(Media(uri));
  }

  @override
  Widget build(BuildContext context) {
    // 1) 影片——可播放大預覽
    if (widget.videoUrl != null && widget.videoUrl!.startsWith('http')) {
      _initPlayer(widget.videoUrl!);
      return Video(
        controller: _controller!,
        controls: AdaptiveVideoControls,
        width: double.infinity,
        height: double.infinity,
      );
    }
    // 2) 圖片——全幅
    if (widget.imageBytes != null) {
      return InteractiveViewer(
        child: Center(
          child: Image.memory(widget.imageBytes!, fit: BoxFit.contain),
        ),
      );
    }
    if (widget.imageUrl != null && widget.imageUrl!.startsWith('http')) {
      return InteractiveViewer(
        child: Center(
          child: Image.network(widget.imageUrl!, fit: BoxFit.contain),
        ),
      );
    }
    // 3) 音樂——播放器＋聲波裝飾（支援 http 與本地檔案路徑）
    if (widget.audioUrl != null && widget.audioUrl!.isNotEmpty) {
      _initPlayer(widget.audioUrl!);
      return Column(
        children: [
          // 聲波裝飾
          SizedBox(
            height: 120,
            child: CustomPaint(
              painter: _WavePainter(color: BridgeDSColors.of(context).accentBlue),
              size: Size.infinite,
            ),
          ),
          SizedBox(
            height: 180,
            child: Video(
              controller: _controller!,
              controls: AdaptiveVideoControls,
              width: double.infinity,
            ),
          ),
        ],
      );
    }
    // 4) 文章——大字級可捲動
    if (widget.articleText != null && widget.articleText!.isNotEmpty) {
      return SingleChildScrollView(
        child: SelectableText(
          widget.articleText!,
          style: TierStyle.of(context, Tier.bodyPrimary)
              .toTextStyle()
              .copyWith(fontSize: 15, height: 1.7),
        ),
      );
    }
    return const Center(child: Text('（無可預覽內容）'));
  }
}

/// 音樂聲波裝飾（純美觀——播放進度視覺化）
class _WavePainter extends CustomPainter {
  final Color color;
  _WavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final midY = size.height / 2;
    final path = Path();
    for (double x = 0; x <= size.width; x += 4) {
      final t = x / size.width;
      final amp = (size.height * 0.3) * (0.5 + 0.5 * _sin01(t * 6.28 * 3));
      final y = midY + amp * _sin01(t * 6.28 * 8);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  static double _sin01(double x) => 0.5 + 0.5 * math.sin(x);

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
