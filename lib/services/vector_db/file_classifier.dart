// file_classifier.dart
// [教練 Agent 2026-07-28] 六大房間檔案分類規則引擎
//
// 設計文件：vector-db-brain-fusion-design.md §二
//
// 兩層分類：
// 1. 檔案類型規則（優先級 1 — 快速，純規則）
// 2. 內容分析（優先級 2 — 本地 Gemma，可覆蓋類型分類）
//
// 無孤兒原則：任何檔案都必須歸入一個房間，無法判斷 → 橋

/// 六大房間（與 BrainRoom enum 對齊）
enum FileRoom {
  stream,      // 🌊 水流軌跡 — 日常流動與能量變化
  doors,       // 🚪 門的紀錄 — 機會、選擇、轉折點
  pendulums,   // 🔔 擺錘警報 — 內在張力、壓力
  heartMind,   // 💗 心腦對話 — 理性與感受的交會
  fraile,      // ✨ 靈魂頻率 — 價值觀、直覺、美感
  bridges,     // 🌉 跨島連結 — 工具、方法、連接
}

/// 房間定義（tooltip 用）
extension FileRoomDef on FileRoom {
  String get label {
    switch (this) {
      case FileRoom.stream: return '水流軌跡';
      case FileRoom.doors: return '門的紀錄';
      case FileRoom.pendulums: return '擺錘警報';
      case FileRoom.heartMind: return '心腦對話';
      case FileRoom.fraile: return '靈魂頻率';
      case FileRoom.bridges: return '跨島連結';
    }
  }

  String get icon {
    switch (this) {
      case FileRoom.stream: return '🌊';
      case FileRoom.doors: return '🚪';
      case FileRoom.pendulums: return '🔔';
      case FileRoom.heartMind: return '💗';
      case FileRoom.fraile: return '✨';
      case FileRoom.bridges: return '🌉';
    }
  }

  String get definition {
    switch (this) {
      case FileRoom.stream:
        return '日常流動與能量變化 — 持續在發生的事';
      case FileRoom.doors:
        return '機會出現、進入、錯過 — 選擇和轉折點';
      case FileRoom.pendulums:
        return '內在張力、壓力、比較 — 需要警覺的東西';
      case FileRoom.heartMind:
        return '理性與感受的交會 — 思考和感受的記錄';
      case FileRoom.fraile:
        return '發光、判斷、共振 — 價值觀和直覺';
      case FileRoom.bridges:
        return '主動連結、奇異連結、時序共振 — 工具和方法';
    }
  }

  /// 顏色碼（與 brain_canvas.dart 房間色碼對齊）
  int get colorValue {
    switch (this) {
      case FileRoom.stream: return 0xFF4ECDC4;
      case FileRoom.doors: return 0xFFFFD700;
      case FileRoom.pendulums: return 0xFFB388FF;
      case FileRoom.heartMind: return 0xFFFF6B9D;
      case FileRoom.fraile: return 0xFF66BB6A;
      case FileRoom.bridges: return 0xFF4A9EFF;
    }
  }
}

/// 分類結果
class ClassificationResult {
  final FileRoom room;
  final double confidence;  // 0.0 - 1.0
  final String reason;      // 為什麼這樣分類

  const ClassificationResult({
    required this.room,
    required this.confidence,
    required this.reason,
  });

  bool get isLowConfidence => confidence < 0.5;
}

/// 來源類型
enum SourceType {
  imported,    // 使用者手動匯入
  system,      // App 自動產生（對話歷史、專案存檔、工作流存檔）
  agent,       // Agent 運作產生（程式碼修改、分析結果、截圖）
}

/// 六大房間檔案分類引擎
///
/// 兩層分類策略：
/// 1. 依檔案類型（快速規則， confidence = 0.7）
/// 2. 依內容分析（本地 Gemma， confidence = 0.85+，可覆蓋類型分類）
///
/// 無孤兒原則：無法判斷 → 橋，confidence = 0.3
class FileClassifier {
  FileClassifier._();
  static final FileClassifier instance = FileClassifier._();

  /// 檔案類型 → 房間的快速規則表
  static const Map<String, FileRoom> _typeRules = {
    // 專案檔 → 門
    '.bridge-project': FileRoom.doors,
    '.door': FileRoom.doors,
    // 工作流 → 橋
    '.bridge-workflow': FileRoom.bridges,
    // Skill → 橋
    // (SKILL.md 用檔名匹配，不在此表)
    // 程式碼 → 橋
    '.py': FileRoom.bridges,
    '.dart': FileRoom.bridges,
    '.js': FileRoom.bridges,
    '.ts': FileRoom.bridges,
    '.sh': FileRoom.bridges,
    '.bash': FileRoom.bridges,
    '.yaml': FileRoom.bridges,
    '.yml': FileRoom.bridges,
    // 圖片 → 靈魂頻率
    '.jpg': FileRoom.fraile,
    '.jpeg': FileRoom.fraile,
    '.png': FileRoom.fraile,
    '.webp': FileRoom.fraile,
    '.heic': FileRoom.fraile,
    '.gif': FileRoom.fraile,
    '.svg': FileRoom.fraile,
    // 影片 → 靈魂頻率
    '.mp4': FileRoom.fraile,
    '.mov': FileRoom.fraile,
    '.avi': FileRoom.fraile,
    '.mkv': FileRoom.fraile,
    // 音訊 → 水流
    '.mp3': FileRoom.stream,
    '.wav': FileRoom.stream,
    '.m4a': FileRoom.stream,
    '.flac': FileRoom.stream,
    // 文件筆記 → 心腦
    '.md': FileRoom.heartMind,
    '.txt': FileRoom.heartMind,
    // 文檔 → 心腦
    '.pdf': FileRoom.heartMind,
    '.docx': FileRoom.heartMind,
    '.doc': FileRoom.heartMind,
    '.rtf': FileRoom.heartMind,
    // 資料檔 → 水流
    '.csv': FileRoom.stream,
    '.xlsx': FileRoom.stream,
    '.xls': FileRoom.stream,
    '.db': FileRoom.stream,
    '.sqlite': FileRoom.stream,
    // 設定檔 → 橋
    '.env': FileRoom.bridges,
    '.config': FileRoom.bridges,
    '.plist': FileRoom.bridges,
    '.toml': FileRoom.bridges,
    '.ini': FileRoom.bridges,
    // 對話歷史 → 水流
    '.conversation': FileRoom.stream,
    '.chat': FileRoom.stream,
    // 記憶檔 → 心腦
    '.memory': FileRoom.heartMind,
    '.brain-memory': FileRoom.heartMind,
    // 暫存檔 → 水流
    '.tmp': FileRoom.stream,
    '.cache': FileRoom.stream,
    '.log': FileRoom.stream,
    // 壓縮檔 → 橋
    '.zip': FileRoom.bridges,
    '.tar': FileRoom.bridges,
    '.gz': FileRoom.bridges,
    '.7z': FileRoom.bridges,
    // JSON → 橋（工作流/設定）
    '.json': FileRoom.bridges,
  };

  /// 檔名匹配規則（特殊檔名，不依副檔名）
  static const Map<String, FileRoom> _nameRules = {
    'SKILL.md': FileRoom.bridges,
    'skill-': FileRoom.bridges,  // prefix match
    'README.md': FileRoom.heartMind,
    'CHANGELOG.md': FileRoom.stream,
  };

  /// 內容關鍵字 → 房間覆蓋規則
  static const Map<FileRoom, List<String>> _contentKeywords = {
    FileRoom.doors: [
      '決策', '選擇', '計畫', '计划', '机会', '機會', '轉折', '转折',
      '要不要', '方案', '下一步', '計劃書', '计划书', 'proposal',
      'decision', 'choice', 'plan', 'roadmap', 'milestone',
    ],
    FileRoom.pendulums: [
      '壓力', '压力', '焦慮', '焦虑', '衝突', '冲突', '緊張', '紧张',
      '比較', '比较', '擔心', '担心', '恐懼', '恐惧', '挫折',
      'stress', 'anxiety', 'conflict', 'worry', 'fear', 'frustrated',
    ],
    FileRoom.fraile: [
      '價值觀', '价值观', '直覺', '直觉', '美感', '理念', '信念',
      '意義', '意义', '使命', '願景', '愿景', '共振',
      'value', 'intuition', 'aesthetic', 'philosophy', 'mission', 'vision',
    ],
    FileRoom.heartMind: [
      '反思', '回顧', '回顾', '教訓', '教训', '感想', '體會', '体会',
      '心情', '感受', '思考', '領悟', '领悟',
      'reflect', 'review', 'lesson', 'feeling', 'thought', 'realization',
    ],
  };

  /// 分類檔案（純規則，不含本地模型分析）
  ///
  /// [fileName] — 檔名（含副檔名）
  /// [fileExt] — 副檔名（含 .，小寫）
  /// [contentText] — 檔案文字內容（可為 null，文字類檔案才會有）
  /// [projectId] — 如果是專案裡的檔案，專案 ID（不影響分類，但記錄關聯）
  ClassificationResult classify({
    required String fileName,
    required String fileExt,
    String? contentText,
    String? projectId,
  }) {
    // Step 1: 檔名匹配（最高優先）
    for (final entry in _nameRules.entries) {
      if (fileName == entry.key || fileName.startsWith(entry.key)) {
        return ClassificationResult(
          room: entry.value,
          confidence: 0.8,
          reason: '檔名匹配: $fileName → ${entry.value.label}',
        );
      }
    }

    // Step 2: 檔案類型規則
    final typeRoom = _typeRules[fileExt];
    if (typeRoom == null) {
      // 未知副檔名 → 橋（無孤兒原則）
      return ClassificationResult(
        room: FileRoom.bridges,
        confidence: 0.3,
        reason: '未知副檔名 $fileExt → 跨島連結（無孤兒原則）',
      );
    }

    // Step 3: 內容分析（如果有的話，可覆蓋類型分類）
    if (contentText != null && contentText.isNotEmpty) {
      final contentRoom = _analyzeContent(contentText);
      if (contentRoom != null) {
        return ClassificationResult(
          room: contentRoom,
          confidence: 0.85,
          reason: '內容分析覆蓋: $fileExt → ${contentRoom.label}',
        );
      }
    }

    // Step 4: 用類型規則的結果
    return ClassificationResult(
      room: typeRoom,
      confidence: 0.7,
      reason: '檔案類型: $fileExt → ${typeRoom.label}',
    );
  }

  /// 分析文字內容，回傳覆蓋的房間（或 null 如果不覆蓋）
  FileRoom? _analyzeContent(String text) {
    final lowerText = text.toLowerCase();
    final scores = <FileRoom, int>{};

    for (final entry in _contentKeywords.entries) {
      var score = 0;
      for (final keyword in entry.value) {
        if (lowerText.contains(keyword.toLowerCase())) {
          score++;
        }
      }
      if (score > 0) {
        scores[entry.key] = score;
      }
    }

    if (scores.isEmpty) return null;

    // 取最高分的房間
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  /// 判斷檔案是否需要內容分析
  bool needsContentAnalysis(String fileExt) {
    return const ['.md', '.txt', '.pdf', '.docx', '.json'].contains(fileExt);
  }

  /// 判斷檔案是否為圖片/影片（需要 vision 模型解析）
  bool needsVisionAnalysis(String fileExt) {
    return const [
      '.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif', '.svg',
      '.mp4', '.mov', '.avi', '.mkv',
    ].contains(fileExt);
  }

  /// 判斷檔案是否可做向量嵌入（文字類）
  bool canEmbedText(String fileExt) {
    return const ['.md', '.txt', '.pdf', '.docx', '.json'].contains(fileExt);
  }
}
