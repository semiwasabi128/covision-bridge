// layer_cache.dart
// Sprint 10 — 層結果快取
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 用 user input 的 normalize hash 做 key，
// 命中就回 cached LayerResult，evidence 標 source=cached。
//
// 快取策略：
// - key = normalize(message) 的 hashCode
// - 每層獨立快取（同一訊息不同層的結果分開存）
// - 最大 100 筆（LRU 簡化版：超過就清最早的）
// - 快取有 TTL（預設 5 分鐘），過期自動失效

import 'layer_result.dart';
import 'text_utils.dart';

/// 一筆快取紀錄。
class _CacheEntry {
  final LayerResult<dynamic> result;
  final DateTime createdAt;

  const _CacheEntry({
    required this.result,
    required this.createdAt,
  });
}

/// 層結果快取。
///
/// 使用方式：
/// ```dart
/// final cache = LayerCache();
/// final key = cache.keyFor(message);
/// final cached = cache.get(layerIndex: 2, key: key);
/// if (cached != null) {
///   // 用快取結果
/// } else {
///   // 跑 analyzer，然後存快取
///   cache.put(layerIndex: 2, key: key, result: result);
/// }
/// ```
class LayerCache {
  /// key = 'layerIndex:hash' → _CacheEntry
  final Map<String, _CacheEntry> _cache = {};

  /// 最大快取筆數
  final int maxEntries;

  /// TTL（預設 5 分鐘）
  final Duration ttl;

  /// 可注入的時鐘
  final DateTime Function() _clock;

  LayerCache({
    this.maxEntries = 100,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 生成 message 的快取 key。
  /// 用 normalize(message).hashCode 確保大小寫/空白差不影響命中。
  String keyFor(String message) {
    return normalize(message).hashCode.toString();
  }

  /// 取得快取的 LayerResult。
  /// 過期或不存在回傳 null。
  LayerResult<dynamic>? get({
    required int layerIndex,
    required String key,
  }) {
    final cacheKey = '$layerIndex:$key';
    final entry = _cache[cacheKey];
    if (entry == null) return null;

    // TTL 檢查
    if (_clock().difference(entry.createdAt) > ttl) {
      _cache.remove(cacheKey);
      return null;
    }

    // 回傳標記為 cached 的副本
    return LayerResult<dynamic>(
      value: entry.result.value,
      source: LayerSource.cached,
      confidence: entry.result.confidence,
      evidence: entry.result.evidence,
      latencyMs: 0, // 快取命中 = 0ms
      metadata: entry.result.metadata,
    );
  }

  /// 存入快取。
  void put({
    required int layerIndex,
    required String key,
    required LayerResult<dynamic> result,
  }) {
    final cacheKey = '$layerIndex:$key';

    // 超過上限 → 清最早的
    if (_cache.length >= maxEntries && !_cache.containsKey(cacheKey)) {
      final oldestKey = _cache.keys.first;
      _cache.remove(oldestKey);
    }

    _cache[cacheKey] = _CacheEntry(
      result: result,
      createdAt: _clock(),
    );
  }

  /// 清除某層的快取。
  void invalidateLayer(int layerIndex) {
    final prefix = '$layerIndex:';
    _cache.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// 清除所有快取。
  void clear() {
    _cache.clear();
  }

  /// 目前快取筆數。
  int get size => _cache.length;

  /// 命中率統計（供 E2E 測試用）。
  int _hits = 0;
  int _misses = 0;

  void recordHit() => _hits++;
  void recordMiss() => _misses++;

  double get hitRate {
    final total = _hits + _misses;
    if (total == 0) return 0.0;
    return _hits / total;
  }

  int get hitCount => _hits;
  int get missCount => _misses;
}
