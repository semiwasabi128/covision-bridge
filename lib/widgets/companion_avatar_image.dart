import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/agent_activity.dart';
import '../models/companion.dart';
import '../services/background_remover.dart';
import '../theme/app_theme.dart';
import 'companion_art.dart';
import 'companion_loop_video.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../theme/bridge_design_system.dart';

class CompanionAvatarImage extends StatelessWidget {
  final Companion companion;
  final String mbtiCode;
  final int seed;
  final String name;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final double size;
  final bool framed;

  const CompanionAvatarImage({
    super.key,
    required this.companion,
    required this.mbtiCode,
    required this.seed,
    required this.name,
    required this.mood,
    required this.action,
    required this.size,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    // [小葵 2026-09-24] 動畫優先：avatarAnimationPath 指到本地 .mp4 時播循環影片
    final animPath = companion.avatarAnimationPath?.trim();
    if (animPath != null && animPath.isNotEmpty && animPath.endsWith('.mp4')) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            _buildImage(companion.avatarImagePath?.trim() ?? '') ?? const SizedBox.shrink(),
            CompanionLoopVideo(path: animPath, size: size),
          ],
        ),
      );
    }
    final imagePath = companion.avatarImagePath?.trim();
    if (imagePath == null || imagePath.isEmpty) {
      return _fallback();
    }

    final image = _buildImage(imagePath);
    if (image == null) {
      return _fallback();
    }

    // [教練 Agent 2026-07-01] 移除多餘的 FittedBox 雙重縮放，
    // _buildImage 已設 width/height/BoxFit.contain，再包一層 FittedBox 會造成變形。
    return SizedBox(
      width: size,
      height: size,
      child: image,
    );
  }

  Widget? _buildImage(String imagePath) {
    if (imagePath.startsWith('data:image/')) {
      try {
        final commaIndex = imagePath.indexOf(',');
        final payload = commaIndex == -1
            ? imagePath
            : imagePath.substring(commaIndex + 1);
        final rawBytes = base64Decode(payload);
        // [教練 Agent 2026-06-29] 去白背景，讓角色圖透明
        final cleanedBytes = BackgroundRemover.removeWhiteBackground(
              Uint8List.fromList(rawBytes),
            ) ??
            Uint8List.fromList(rawBytes);
        return Image.memory(
          cleanedBytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      } catch (_) {
        return null;
      }
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    }

    if (kIsWeb) return null;
    // [教練 Agent 2026-06-29] 檔案路徑也去白背景
    try {
      final rawBytes = File(imagePath).readAsBytesSync();
      final cleanedBytes = BackgroundRemover.removeWhiteBackground(
            Uint8List.fromList(rawBytes),
          ) ??
          Uint8List.fromList(rawBytes);
      return Image.memory(
        cleanedBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } catch (_) {
      return null;
    }
  }

  Widget _fallback() {
    return CompanionArt(
      mbtiCode: mbtiCode,
      seed: seed,
      name: name,
      mood: mood,
      action: action,
      size: size,
      framed: framed,
    );
  }
}

// [教練 Agent 2026-06-29] 呼吸動畫引擎已封存（CompanionBreathingTuning/Sprite/BreathProfile）
// 未來重建角色動作系統時可從 git 歷史恢復。

class CompanionStateImageSheet extends StatelessWidget {
  final Companion companion;
  final bool compact;

  const CompanionStateImageSheet({
    super.key,
    required this.companion,
    this.compact = false,
  });

  static const _defaultStates = [
    ('idle', '待機', AgentCompanionMood.idle, AgentCompanionAction.standing),
    ('reading', '閱讀', AgentCompanionMood.focused, AgentCompanionAction.reading),
    (
      'writing',
      '編寫中',
      AgentCompanionMood.focused,
      AgentCompanionAction.reading,
    ),
    ('stuck', '卡住了', AgentCompanionMood.waiting, AgentCompanionAction.standing),
    ('idea', '有好點子了', AgentCompanionMood.proud, AgentCompanionAction.pointing),
    (
      'pointing',
      '指路',
      AgentCompanionMood.routing,
      AgentCompanionAction.pointing,
    ),
    (
      'bridging',
      '橋接',
      AgentCompanionMood.bridging,
      AgentCompanionAction.spinning,
    ),
    (
      'celebrating',
      '慶祝',
      AgentCompanionMood.proud,
      AgentCompanionAction.bouncing,
    ),
    (
      'wandering',
      '漫遊',
      AgentCompanionMood.curious,
      AgentCompanionAction.wandering,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final knownKeys = _defaultStates.map((state) => state.$1).toSet();
    final states = [
      for (final state in _defaultStates)
        if (!compact || state.$1 != 'celebrating' && state.$1 != 'wandering')
          state,
      for (final entry in companion.stateImagePaths.entries)
        if (!knownKeys.contains(entry.key))
          (
            entry.key,
            entry.key,
            AgentCompanionMood.curious,
            AgentCompanionAction.wandering,
          ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: states.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: compact ? 4 : 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final state = states[index];
        var imagePath = companion.stateImagePaths[state.$1]?.trim();
        // [教練 Agent 2026-06-29] 待機狀態沒有專屬圖時，用主形象圖當 fallback
        if ((imagePath == null || imagePath.isEmpty) && state.$1 == 'idle') {
          imagePath = companion.avatarImagePath?.trim();
          if (imagePath != null && imagePath.isEmpty) imagePath = null;
        }
        return _CompanionStateImageTile(
          imagePath: imagePath == null || imagePath.isEmpty ? null : imagePath,
          label: state.$2,
          fallback: CompanionArt(
            mbtiCode: companion.mbtiCode,
            seed: index * 97, // [教練 Agent 2026-08-04] appearanceSeed 已刪除，用 index 作變化
            name: companion.name,
            mood: state.$3,
            action: state.$4,
            label: state.$2,
            size: 180,
          ),
        );
      },
    );
  }
}

class _CompanionStateImageTile extends StatelessWidget {
  final String? imagePath;
  final String label;
  final Widget fallback;

  const _CompanionStateImageTile({
    required this.imagePath,
    required this.label,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final imagePath = this.imagePath;
    if (imagePath == null || imagePath.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: AppTheme.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: _StoredCompanionImage(imagePath: imagePath),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                  border: Border.all(color: BridgeDSColors.of(context).textPrimary),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: AppTheme.accent,
                    fontWeight: FontWeight.w800,),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoredCompanionImage extends StatelessWidget {
  final String imagePath;

  const _StoredCompanionImage({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final image = _buildImage();
    if (image == null) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, color: AppTheme.textMuted),
      );
    }
    // [教練 Agent 2026-07-01] 移除 FittedBox 雙重縮放，Image 已有 BoxFit.contain
    return image;
  }

  Widget? _buildImage() {
    if (imagePath.startsWith('data:image/')) {
      try {
        final commaIndex = imagePath.indexOf(',');
        final payload = commaIndex == -1
            ? imagePath
            : imagePath.substring(commaIndex + 1);
        return Image.memory(
          base64Decode(payload),
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      } catch (_) {
        return null;
      }
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            const Icon(Icons.broken_image_outlined, color: AppTheme.textMuted),
      );
    }

    if (kIsWeb) return null;
    return Image.file(
      File(imagePath),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.broken_image_outlined, color: AppTheme.textMuted),
    );
  }
}
