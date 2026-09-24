// hover_insight_service.dart
// [教練 Agent 2026-08-21] 「為什麼亮」後半 — AI 一句話關聯摘要（lazy）
//
// hover 浮牌第四行（規則文字：星等/樞紐/星座）已有，但 使用者 要的
// 是「講人話的為什麼」。本服務：hover 停留超過 1.2 秒的節點，背景
// 用 LLM 生成一句話關聯摘要（節點標題＋鄰居標題＋規則線索當輸入），
// LRU 快取 128 筆。UI 端拿到就顯示成浮牌第五行；拿不到就維持規則
// 第四行——規則先行，AI 增強，不阻塞不閃爍。
//
// 節流紀律：
// - 同一節點只問一次（快取）
// - 一次只飛一個請求（_busy 互斥）
// - 失敗靜默（摘要缺席不是錯誤）

import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../agent_loop/production_agent_loop_llm_client.dart';

class HoverInsightService {
  HoverInsightService._();
  static final HoverInsightService instance = HoverInsightService._();

  final LinkedHashMap<String, String> _cache = LinkedHashMap();
  static const _maxCache = 128;
  bool _busy = false;

  /// 節點 hover 摘要。null＝還沒好（呼叫端維持規則文字）。
  String? cached(String nodeId) => _cache[nodeId];

  /// lazy 觸發：UI 在 hover 停留 1.2s 後呼叫。
  void request({
    required String nodeId,
    required String nodeTitle,
    required List<String> neighborTitles,
    required String ruleHint, // 浮牌第四行的規則文字（當線索）
  }) {
    if (_cache.containsKey(nodeId) || _busy) return;
    _busy = true;

    Future(() async {
      try {
        final neighbors = neighborTitles.take(6).join('、');
        final prompt = '你在圖譜裡看到一個節點「$nodeTitle」。'
            '它與這些節點有語義連結：$neighbors。'
            '規則線索：$ruleHint。'
            '請用一句繁體中文（30字內）說明「這個節點為什麼在這個位置發光」'
            '——講關聯的本質，不要複述清單。直接輸出那句話，不要引號。';

        final client = ProductionAgentLoopLLMClient();
        final reply = await client.complete([
          {'role': 'user', 'content': prompt},
        ]);
        final text = reply.trim();
        if (text.isNotEmpty && text.length <= 80) {
          _cache[nodeId] = text;
          _trim();
          debugPrint('[HoverInsight] $nodeId → $text');
        }
      } catch (e) {
        debugPrint('[HoverInsight] 失敗（靜默）: $e');
      } finally {
        _busy = false;
      }
    });
  }

  void _trim() {
    while (_cache.length > _maxCache) {
      _cache.remove(_cache.keys.first);
    }
  }
}
