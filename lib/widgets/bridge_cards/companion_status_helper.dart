// [迦勒 Sprint 7 前置 2026-06-24] 從 chat_screen.dart 抽出：companion 狀態預覽共用方法鏈
// 原始定義位置：chat_screen.dart 行 7657-7815（方法）、10188-10293（_CompanionStatusSpec 與 _chatStatusSpecs）
// 此檔案只做搬移，不改邏輯。供 Sprint 7 CompanionPresenceLayer 使用。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/agent_activity.dart';
import '../../models/companion.dart';
import '../../models/companion_runtime.dart';
import '../../services/background_remover.dart';
import '../../theme/app_theme.dart';
import '../companion_art.dart';
import '../companion_loop_video.dart';
import '../companion_avatar_image.dart';

/// [迦勒 Sprint 7 前置 2026-06-24] companion 狀態規格資料模型。
///
/// 原 chat_screen.dart `_CompanionStatusSpec`（行 10188-10208），改為 public。
class CompanionStatusSpec {
  final String id;
  final String label;
  final AgentActivityStage stage;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final IconData icon;
  final bool active;
  final List<String> aliases;

  const CompanionStatusSpec({
    required this.id,
    required this.label,
    required this.stage,
    required this.mood,
    required this.action,
    required this.icon,
    this.active = true,
    this.aliases = const [],
  });
}

/// [迦勒 Sprint 7 前置 2026-06-24] companion 狀態規格常數列表。
///
/// 原 chat_screen.dart `_chatStatusSpecs`（行 10210-10293），改為 public。
const companionStatusSpecs = [
  CompanionStatusSpec(
    id: 'idle',
    label: '待機',
    stage: AgentActivityStage.understanding,
    mood: AgentCompanionMood.idle,
    action: AgentCompanionAction.standing,
    icon: Icons.lightbulb_outline,
    active: false,
    aliases: ['standby', '閒置'],
  ),
  CompanionStatusSpec(
    id: 'reading',
    label: '閱讀',
    stage: AgentActivityStage.context,
    mood: AgentCompanionMood.focused,
    action: AgentCompanionAction.reading,
    icon: Icons.menu_book_outlined,
    aliases: ['read', 'context', '上下文'],
  ),
  CompanionStatusSpec(
    id: 'writing',
    label: '編寫中',
    stage: AgentActivityStage.composing,
    mood: AgentCompanionMood.focused,
    action: AgentCompanionAction.reading,
    icon: Icons.edit_note,
    aliases: ['write', 'coding', 'drafting', '執行', '寫作'],
  ),
  CompanionStatusSpec(
    id: 'stuck',
    label: '卡住了',
    // [教練 Agent 2026-07-03] 修正：stuck 不再對應 waiting stage
    // waiting 是正常思考（等 AI 回應），不是卡住
    // stuck 只在 error/retry/blocked 時由 aliases 觸發
    stage: AgentActivityStage.composing,
    mood: AgentCompanionMood.waiting,
    action: AgentCompanionAction.standing,
    icon: Icons.sentiment_dissatisfied_outlined,
    aliases: ['blocked', 'error', '卡點', '苦惱', 'retry', '重試'],
  ),
  CompanionStatusSpec(
    id: 'idea',
    label: '有好點子了',
    stage: AgentActivityStage.composing,
    mood: AgentCompanionMood.proud,
    action: AgentCompanionAction.pointing,
    icon: Icons.emoji_objects_outlined,
    aliases: ['insight', 'solution', 'breakthrough', '靈感', '好方法'],
  ),
  CompanionStatusSpec(
    id: 'pointing',
    label: '指路',
    stage: AgentActivityStage.routing,
    mood: AgentCompanionMood.routing,
    action: AgentCompanionAction.pointing,
    icon: Icons.assistant_direction_outlined,
    aliases: ['route', 'routing', '指向'],
  ),
  CompanionStatusSpec(
    id: 'bridging',
    label: '橋接',
    stage: AgentActivityStage.bridge,
    mood: AgentCompanionMood.bridging,
    action: AgentCompanionAction.spinning,
    icon: Icons.account_tree_outlined,
    aliases: ['bridge', 'connecting', '連接'],
  ),
  CompanionStatusSpec(
    id: 'celebrating',
    label: '慶祝',
    stage: AgentActivityStage.composing,
    mood: AgentCompanionMood.proud,
    action: AgentCompanionAction.bouncing,
    icon: Icons.celebration_outlined,
    aliases: ['celebrate', 'proud', '成功'],
  ),
  CompanionStatusSpec(
    id: 'wandering',
    label: '漫遊',
    stage: AgentActivityStage.understanding,
    mood: AgentCompanionMood.curious,
    action: AgentCompanionAction.wandering,
    icon: Icons.explore_outlined,
    aliases: ['wander', 'curious', '探索'],
  ),
];

/// [迦勒 Sprint 7 前置 2026-06-24] companion 狀態預覽共用方法鏈。
///
/// 原為 chat_screen.dart `_ChatScreenState` 的實例方法（行 7657-7815），
/// 此處改為 static 方法，邏輯完全不變。
class CompanionStatusHelper {
  CompanionStatusHelper._();

  /// [迦勒 Sprint 7 前置 2026-06-24] 原行 7693-7724
  static CompanionStatusSpec statusSpecForRuntime(
    CompanionRuntimeState runtime,
  ) {
    final snapshot = runtime.activity;
    for (final spec in companionStatusSpecs) {
      if (spec.stage == snapshot.stage &&
          spec.mood == snapshot.mood &&
          spec.action == snapshot.action) {
        return spec;
      }
    }
    if (snapshot.active) {
      switch (snapshot.stage) {
        case AgentActivityStage.context:
          return statusSpecById('reading');
        case AgentActivityStage.waiting:
          // [教練 Agent 2026-07-03] 修正：waiting 是正常思考，不是卡住
          // 等待 AI 回應時顯示 reading（閱讀/思考中）
          return statusSpecById('reading');
        case AgentActivityStage.composing:
          return statusSpecById('writing');
        case AgentActivityStage.routing:
          return statusSpecById('pointing');
        case AgentActivityStage.bridge:
          return statusSpecById('bridging');
        case AgentActivityStage.understanding:
          return statusSpecById('reading');
      }
    }
    for (final spec in companionStatusSpecs) {
      if (spec.mood == snapshot.mood && spec.action == snapshot.action) {
        return spec;
      }
    }
    return companionStatusSpecs.first;
  }

  /// [迦勒 Sprint 7 前置 2026-06-24] 原行 7726-7731
  static CompanionStatusSpec statusSpecById(String id) {
    return companionStatusSpecs.firstWhere(
      (spec) => spec.id == id,
      orElse: () => companionStatusSpecs.first,
    );
  }

  /// [迦勒 Sprint 7 前置 2026-06-24] 原行 7733-7751
  static String? stateImagePathFor(
    Companion? companion,
    CompanionStatusSpec spec,
  ) {
    if (companion == null || companion.stateImagePaths.isEmpty) return null;
    final candidates = {
      spec.id,
      spec.label,
      ...spec.aliases,
    }.map(normalizeStateKey).toSet();
    for (final entry in companion.stateImagePaths.entries) {
      if (candidates.contains(normalizeStateKey(entry.key))) {
        final value = entry.value.trim();
        if (value.isNotEmpty) return value;
      }
    }
    final legacyCustomPath = legacyCustomStateImagePathFor(companion, spec);
    if (legacyCustomPath != null && legacyCustomPath.isNotEmpty) {
      return legacyCustomPath;
    }
    return null;
  }

  /// [小葵 2026-09-24 出道令] 狀態動畫查找——stateAnimationPaths 鍵比照 stateImagePathFor
  /// 的候選集（id/label/aliases 正規化比對），只接受 .mp4。
  static String? stateAnimationPathFor(
    Companion? companion,
    CompanionStatusSpec spec,
  ) {
    if (companion == null || companion.stateAnimationPaths.isEmpty) return null;
    final candidates = {
      spec.id,
      spec.label,
      ...spec.aliases,
    }.map(normalizeStateKey).toSet();
    for (final entry in companion.stateAnimationPaths.entries) {
      if (candidates.contains(normalizeStateKey(entry.key))) {
        final value = entry.value.trim();
        if (value.isNotEmpty && value.endsWith('.mp4')) return value;
      }
    }
    return null;
  }

  /// [迦勒 Sprint 7 前置 2026-06-24] 原行 7753-7755
  static String normalizeStateKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }

  /// [迦勒 Sprint 7 前置 2026-06-24] 原行 7757-7772
  static String? legacyCustomStateImagePathFor(
    Companion companion,
    CompanionStatusSpec spec,
  ) {
    const upgradedKeys = ['writing', 'stuck', 'idea'];
    final index = upgradedKeys.indexOf(spec.id);
    if (index < 0) return null;
    final customEntries = companion.stateImagePaths.entries
        .where((entry) => entry.key.startsWith('custom_'))
        .where((entry) => entry.value.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (customEntries.length <= index) return null;
    return customEntries[index].value.trim();
  }

  /// [迦勒 Sprint 7 前置 2026-06-24] 原行 7774-7815
  static Widget buildStoredStatusImage(String imagePath) {
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
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
      } catch (_) {
        return const Icon(
          Icons.broken_image_outlined,
          color: AppTheme.textMuted,
        );
      }
    }
    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return Image.network(
        imagePath,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.broken_image_outlined,
          color: AppTheme.textMuted,
        ),
      );
    }
    if (kIsWeb) {
      return const Icon(
        Icons.image_not_supported_outlined,
        color: AppTheme.textMuted,
      );
    }
    // [教練 Agent 2026-06-29] 檔案路徑也去白背景
    try {
      final rawBytes = File(imagePath).readAsBytesSync();
      final cleanedBytes = BackgroundRemover.removeWhiteBackground(
            Uint8List.fromList(rawBytes),
          ) ??
          Uint8List.fromList(rawBytes);
      return Image.memory(
        cleanedBytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } catch (_) {
      return Image.file(
        File(imagePath),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.broken_image_outlined,
          color: AppTheme.textMuted,
        ),
      );
    }
  }

  /// [迦勒 Sprint 7 前置 2026-06-24] 原行 7657-7691
  static Widget buildStatusPreviewImage({
    required CompanionRuntimeState runtime,
    required Companion? companion,
    required CompanionStatusSpec spec,
    required double size,
  }) {
    // [小葵 2026-09-24 出道令] 狀態動畫優先：stateAnimationPaths 命中 .mp4 播循環影片
    final stateAnimPath = stateAnimationPathFor(companion, spec);
    if (stateAnimPath != null && stateAnimPath.isNotEmpty) {
      return SizedBox(
        width: size,
        child: CompanionLoopVideo(path: stateAnimPath, size: size),
      );
    }
    final stateImagePath = stateImagePathFor(companion, spec);
    if (stateImagePath != null && stateImagePath.isNotEmpty) {
      // [教練 Agent 2026-07-01] 只限制寬度，高度由 BoxFit.contain 自然決定，
      // 避免去白背景後非 1:1 圖片被強制拉成正方形而變形。
      return SizedBox(
        width: size,
        child: buildStoredStatusImage(stateImagePath),
      );
    }
    if (companion == null) {
      return CompanionArt(
        mbtiCode: 'ENFP',
        seed: runtime.activeCompanionName.hashCode,
        name: runtime.activeCompanionName,
        mood: spec.mood,
        action: spec.action,
        size: size,
        framed: false,
      );
    }
    return CompanionAvatarImage(
      companion: companion,
      mbtiCode: companion.mbtiCode,
      seed: 0, // [教練 Agent 2026-08-04] appearanceSeed 已刪除
      name: companion.name,
      mood: spec.mood,
      action: spec.action,
      size: size,
      framed: false,
    );
  }

  // === [教練 Agent 2026-07-03] 關鍵字觸發系統（方案 C 快車道）===

  /// 內建關鍵字表：每個狀態 ID 對應一組觸發關鍵字。
  /// 使用者在角色編輯器裡設定的關鍵字會存進 companion.stateTriggerKeywords，
  /// 與此表合併使用。
  static const _builtinKeywords = <String, List<String>>{
    'idea': ['好點子', '好方法', '靈感', '想到了', '想到', '突破', '發現', '正確方向'],
    'wandering': ['隨便聊聊', '陪我', '逛逛', '放輕鬆', '隨便', '聊聊'],
    'celebrating': ['太棒了', '完成', '成功', '漂亮', '做得好'],
    'stuck': ['卡住了', '卡點', '失敗', '錯誤', '等等', '重試'],
    'reading': ['整理', '摘要', '讀一下', '幫我看', '查一下'],
    'writing': ['編輯', '寫', '執行', '程式', '文案', '草稿'],
    'pointing': ['下一步', '怎麼做', '帶我', '建議', '方向'],
    'bridging': ['連接', '生成', '呼叫', '橋接', '對接'],
  };

  /// 掃描文字，回傳命中的狀態 spec，沒命中回傳 null。
  ///
  /// 合併來源：
  /// 1. 內建關鍵字表 `_builtinKeywords`
  /// 2. Companion 自訂關鍵字 `companion.stateTriggerKeywords`
  /// 3. Companion 有對應狀態圖才觸發（沒圖就不切）
  static CompanionStatusSpec? scanTextForState({
    required String text,
    required Companion? companion,
  }) {
    if (text.trim().isEmpty) return null;
    final lowerText = text.toLowerCase();

    // 合併關鍵字表
    final allKeywords = <String, List<String>>{};
    allKeywords.addAll(_builtinKeywords);
    if (companion != null) {
      for (final entry in companion.stateTriggerKeywords.entries) {
        allKeywords.update(
          entry.key,
          (existing) => [...existing, ...entry.value],
          ifAbsent: () => entry.value,
        );
      }
    }

    // 只對有對應狀態圖的狀態做掃描
    for (final entry in allKeywords.entries) {
      final stateId = entry.key;
      // 確認 companion 有這張狀態圖（或沒有 companion 時允許內建）
      if (companion != null &&
          companion.stateImagePaths.isNotEmpty &&
          !_companionHasStateImage(companion, stateId)) {
        continue;
      }
      for (final keyword in entry.value) {
        if (lowerText.contains(keyword.toLowerCase())) {
          return statusSpecById(stateId);
        }
      }
    }
    return null;
  }

  /// 檢查 companion 是否有指定狀態的圖片（含 alias 匹配）
  static bool _companionHasStateImage(Companion companion, String stateId) {
    final spec = statusSpecById(stateId);
    final candidates = {
      spec.id,
      spec.label,
      ...spec.aliases,
    }.map(normalizeStateKey).toSet();
    for (final entry in companion.stateImagePaths.entries) {
      if (candidates.contains(normalizeStateKey(entry.key)) &&
          entry.value.trim().isNotEmpty) {
        return true;
      }
    }
    return false;
  }
}
