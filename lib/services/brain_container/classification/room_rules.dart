// room_rules.dart
// 規則分類引擎 — 關鍵詞庫 + 評分
// 建立日期: 2026-07-03
//
// 從 transurfing_brain_service.dart 移植關鍵詞庫，
// 重新對應到六大房間 + 子分類。

import 'package:bridge_app/models/brain_container/brain_room.dart';

/// 六大房間 + 子分類的關鍵詞對應表。
///
/// 評分邏輯：
/// - [scoreRooms]：每個房間的命中數佔所有房間命中總數的比例。
/// - [scoreSubCategories]：該房間內每個子分類的命中數佔比。
/// - [evaluate]：回傳最高分房間 + 子分類 + 信心度。
class RoomRules {
  RoomRules._();

  /// 關鍵詞庫：BrainRoom → (子分類 → 關鍵詞列表)
  static const Map<BrainRoom, Map<String, List<String>>> roomKeywords = {
    BrainRoom.stream: {
      'smoothFlow': ['順暢', '輕鬆', '流動', '自然', '不費力'],
      'repeatedObstacle': ['卡住', '反覆', '一直', '每次都', '又來了'],
      'synchronicity': ['剛好', '同步', '巧合', '同時', '意外地'],
      'energyFluctuation': ['累', '沒力', '興奮', '低潮', '能量'],
    },
    BrainRoom.doors: {
      'invitationAppeared': ['邀請', '機會', '出現', '收到', '被問'],
      'doorEntered': ['開始做', '繼續', '下一步', '執行', '進去'],
      'doorMissed': ['錯過', '來不及', '沒趕上', '可惜'],
      'doorWaiting': ['等待', '觀望', '還沒', '考慮中'],
    },
    BrainRoom.pendulums: {
      'mustMoment': ['必須', '一定要', '不得不', '非...不可'],
      'anxietySource': ['怕', '焦慮', '完了', '不安', '怎麼辦'],
      'comparisonTarget': ['大家都', '別人', '新聞說', '很紅', '流行'],
      'groupPressure': ['應該', '對不起', '愧疚', '都是我的錯'],
    },
    BrainRoom.heartMind: {
      'mindSaid': ['想到', '覺得應該', '理性上', '分析', '判斷'],
      'heartFelt': ['想要', '喜歡', '有感覺', '心裡', '直覺'],
      'splitMoment': ['可是', '但是', '不過', '矛盾', '掙扎'],
      'integrationResult': ['整合', '決定', '確定了', '想通了'],
    },
    BrainRoom.fraile: {
      'makesMeGlow': ['發光', '興奮', '我的風格', '創作', '熱情'],
      'judgmentMoment': ['批評', '看不起', '嫉妒', '比較'],
      'resonance': ['共鳴', '共振', '對', '就是這個'],
      'pseudoFraile': ['應該喜歡', '好像不錯', '別人說好'],
    },
    BrainRoom.bridges: {
      'activeBridging': ['連結', '橋接', '好像跟', '有關', '聯想'],
      'weirdConnection': ['奇怪', '莫名其妙', '說不上來'],
      'temporalResonance': ['又來了', '跟上次一樣', '歷史重演'],
      'analogicalInsight': ['好像', '就像', '類似', '比喻'],
    },
  };

  /// 評分：給定內容，回傳每個房間的分數（0.0 ~ 1.0）。
  ///
  /// 分數 = 該房間命中關鍵詞數 / 所有房間命中關鍵詞總數。
  /// 若無任何命中，所有房間回傳 0.0。
  static Map<BrainRoom, double> scoreRooms(String content) {
    final lowerContent = content.toLowerCase();
    final scores = <BrainRoom, int>{};
    var totalHits = 0;

    for (final room in BrainRoom.values) {
      final subCats = roomKeywords[room] ?? {};
      var roomHits = 0;
      for (final keywords in subCats.values) {
        for (final keyword in keywords) {
          if (lowerContent.contains(keyword.toLowerCase())) {
            roomHits++;
          }
        }
      }
      scores[room] = roomHits;
      totalHits += roomHits;
    }

    if (totalHits == 0) {
      return {for (final room in BrainRoom.values) room: 0.0};
    }

    return {
      for (final room in BrainRoom.values)
        room: (scores[room] ?? 0) / totalHits,
    };
  }

  /// 評分：給定內容 + 房間，回傳每個子分類的分數（0.0 ~ 1.0）。
  ///
  /// 分數 = 該子分類命中數 / 該房間命中總數。
  /// 若無任何命中，所有子分類回傳 0.0。
  static Map<String, double> scoreSubCategories(
    String content,
    BrainRoom room,
  ) {
    final lowerContent = content.toLowerCase();
    final subCats = roomKeywords[room] ?? {};
    final scores = <String, int>{};
    var totalHits = 0;

    for (final entry in subCats.entries) {
      var hits = 0;
      for (final keyword in entry.value) {
        if (lowerContent.contains(keyword.toLowerCase())) {
          hits++;
        }
      }
      scores[entry.key] = hits;
      totalHits += hits;
    }

    if (totalHits == 0) {
      return {for (final key in subCats.keys) key: 0.0};
    }

    return {
      for (final key in subCats.keys)
        key: (scores[key] ?? 0) / totalHits,
    };
  }

  /// 綜合評估：回傳最高分房間 + 子分類 + 信心度 + 命中關鍵詞。
  ///
  /// 若無任何命中，回傳 stream + smoothFlow + confidence 0.0。
  static RoomClassificationResult evaluate(String content) {
    final lowerContent = content.toLowerCase();
    final roomScores = scoreRooms(content);

    // 找最高分房間
    BrainRoom bestRoom = BrainRoom.stream;
    var bestRoomScore = 0.0;
    for (final entry in roomScores.entries) {
      if (entry.value > bestRoomScore) {
        bestRoomScore = entry.value;
        bestRoom = entry.key;
      }
    }

    // 無命中 → 預設
    // [教練 Agent 2026-08-20] 修正：agent 的作業快照（「使用者正在…」「使用者目前…」
    // 開頭）落在這裡的機率極高——它們不是「順暢流動」的心理狀態，
    // 是觀察日誌。歸入中性 observation，圖譜端降為背景塵埃呈現。
    if (bestRoomScore == 0.0) {
      final isSnapshot = content.startsWith('使用者正在') ||
          content.startsWith('使用者目前') ||
          content.startsWith('使用者剛');
      return RoomClassificationResult(
        room: BrainRoom.stream,
        subCategory: isSnapshot ? 'observation' : 'smoothFlow',
        confidence: 0.0,
        matchedKeywords: [],
      );
    }

    // 找最高分子分類
    final subScores = scoreSubCategories(content, bestRoom);
    var bestSub = 'smoothFlow';
    var bestSubScore = 0.0;
    for (final entry in subScores.entries) {
      if (entry.value > bestSubScore) {
        bestSubScore = entry.value;
        bestSub = entry.key;
      }
    }

    // 收集命中關鍵詞（最佳房間的所有子分類）
    final matchedKeywords = <String>[];
    final subCats = roomKeywords[bestRoom] ?? {};
    for (final keywords in subCats.values) {
      for (final keyword in keywords) {
        if (lowerContent.contains(keyword.toLowerCase())) {
          matchedKeywords.add(keyword);
        }
      }
    }

    return RoomClassificationResult(
      room: bestRoom,
      subCategory: bestSub,
      confidence: bestRoomScore,
      matchedKeywords: matchedKeywords,
    );
  }
}

/// 分類結果。
class RoomClassificationResult {
  final BrainRoom room;
  final String subCategory;
  final double confidence;
  final List<String> matchedKeywords;

  const RoomClassificationResult({
    required this.room,
    required this.subCategory,
    required this.confidence,
    required this.matchedKeywords,
  });
}
