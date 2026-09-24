import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/agent_activity.dart';
import '../models/companion.dart';
import '../services/background_remover.dart';
import '../theme/app_theme.dart';
import 'companion_art.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../theme/bridge_design_system.dart';

/// [小葵 2026-09-24] 循環動畫影片 widget——avatarAnimationPath 指到 .mp4 時
/// 用 VideoPlayer 無限循環播放（靜音：影片音軌已在資產側去除，雙保險 muted）。
/// 初始化失敗時回退圖片（不讓角色消失）。
class CompanionLoopVideo extends StatefulWidget {
  final String path;
  final double size;

  const CompanionLoopVideo({super.key, required this.path, required this.size});

  @override
  State<CompanionLoopVideo> createState() => _CompanionLoopVideoState();
}

class _CompanionLoopVideoState extends State<CompanionLoopVideo> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final file = File(widget.path);
    if (!await file.exists()) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    final c = VideoPlayerController.file(file);
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0); // 影片純視覺——語音走 TTS
      await c.play();
      if (mounted) setState(() => _controller = c);
    } catch (_) {
      await c.dispose();
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (_failed || c == null || !c.value.isInitialized) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: c.value.size.width,
          height: c.value.size.height,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}
