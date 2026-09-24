// text_utils.dart
// Sprint 1 — 從 TransurfingBrainService 提取的共用文字工具
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 純剪下貼上，不改邏輯。所有 rule analyzer 共用這些 helper。

/// AI 服務關鍵字列表（從 transurfing_brain_service.dart 原樣搬過來）。
const aiServiceMarkers = [
  'ai 服務',
  'ai服務',
  '影片生成',
  '音樂生成',
  '圖片生成',
  '新工具',
  '新平台',
  '平台',
  'discord',
  'openai',
  'kimi',
  'gimi',
  'claude',
  'gemini',
  'midjourney',
  'runway',
  'suno',
];

/// 轉小寫 + 壓縮空白（原 TransurfingBrainService._normalize）。
String normalize(String message) {
  return message.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 檢查 text 是否包含 markers 中任一字串（原 _containsAny）。
bool containsAny(String text, List<String> markers) {
  return markers.any(text.contains);
}

/// 回傳第一個命中的 marker，沒有則 null（原 _firstMarker）。
String? firstMarker(String text, List<String> markers) {
  for (final marker in markers) {
    if (text.contains(marker)) return marker;
  }
  return null;
}
