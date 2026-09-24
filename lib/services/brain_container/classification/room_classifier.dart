// room_classifier.dart
// 記憶房間分類器 — 包裝 RoomRules，未來可加 LLM hook
// 建立日期: 2026-07-03

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/services/brain_container/classification/room_rules.dart';

/// 記憶分類器。
///
/// P1: 純規則版。未來可加 LLM hook。
class RoomClassifier {
  const RoomClassifier();

  /// 分類記憶到房間 + 子分類。
  ///
  /// [tags] 目前未參與規則評分，保留給未來 LLM hook 使用。
  RoomClassification classify({
    required String content,
    List<String> tags = const [],
  }) {
    final result = RoomRules.evaluate(content);
    return RoomClassification(
      room: result.room,
      subCategory: result.subCategory,
      confidence: result.confidence,
      strategy: ClassificationStrategy.ruleOnly,
      matchedKeywords: result.matchedKeywords,
      needsLLMReview: result.confidence < 0.6,
    );
  }
}

/// 分類結果。
class RoomClassification {
  final BrainRoom room;
  final String subCategory;
  final double confidence;
  final ClassificationStrategy strategy;
  final List<String> matchedKeywords;
  final bool needsLLMReview;

  const RoomClassification({
    required this.room,
    required this.subCategory,
    required this.confidence,
    required this.strategy,
    required this.matchedKeywords,
    required this.needsLLMReview,
  });
}

/// 分類策略。
enum ClassificationStrategy {
  /// 純規則
  ruleOnly,

  /// 規則 + LLM 裁決
  ruleWithLLMTiebreak,

  /// LLM 主導
  llmPrimary,
}
