// memory_source.dart
// 記憶來源 enum
// 建立日期: 2026-07-02

/// 記憶的原始來源類型。
enum MemorySource {
  chat,
  file,
  web,
  book,
  idea;

  /// 存入 SQLite 時使用的值（enum name）
  String get dbValue => name;

  /// 從 SQLite 讀回時解析（找不到時 throw StateError）。
  static MemorySource fromDb(String v) =>
      values.firstWhere((e) => e.name == v);

  /// 從 SQLite 讀回時嘗試解析，找不到時回傳 null（不 throw）。
  static MemorySource? tryFromDb(String? v) {
    if (v == null) return null;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return null;
  }

  /// 從 SQLite 讀回時解析，找不到時回傳 [defaultValue]（不 throw）。
  static MemorySource fromDbOrDefault(String? v,
      {MemorySource defaultValue = MemorySource.chat}) {
    return tryFromDb(v) ?? defaultValue;
  }
}

/// [出處戳 provenance 2026-09-15] 記憶的「誰說的」——與 [MemorySource]
/// （媒介：chat/file/web/...）正交的另一個維度。
///
/// 源頭：時間感提案抓包案 #7——AI 把自己生產的農場文誤歸為
/// 使用者說過的話（偽造親密證據鏈）。speaker 由**寫入點架構層**
/// 強制填寫（寫入時角色已知），永不讓模型事後猜測。
///
/// 規則：
/// - user：使用者親口說的 → 回顧時可說「你說過」
/// - agent：夥伴（AI）生產的內容 → 禁止說「你說過」
/// - external：第三方文件/書籍/網路 → 引用需標明出處
/// - unknown：出處不明（含 2026-09-15 前的既有記憶）→ 禁止歸屬，只能說「不確定」
enum MemorySpeaker {
  user,
  agent,
  external,
  unknown;

  String get dbValue => name;

  static MemorySpeaker fromDbOrDefault(String? v,
      {MemorySpeaker defaultValue = MemorySpeaker.unknown}) {
    if (v == null) return defaultValue;
    for (final e in values) {
      if (e.name == v) return e;
    }
    return defaultValue;
  }
}
