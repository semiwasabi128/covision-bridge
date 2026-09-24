// dream_buffer.dart
// [小葵 2026-09-22 Blue 偷學令③] Dreaming 緩衝層——訊息積批後一次做夢。
//
// 借鏡 supermemory dreaming：逐則抽取看不到跨訊息因果；相關訊息
// 分組一起分析，修正/補充/推翻才有機會浮現。
//
// 觸發：滿 10 則 或 閒置 5 分鐘（先到者觸發）。做夢期間新訊息進新批。
// 防呆：做夢中不重入；失敗訊息留在 buffer 下輪再夢（最多重試 2 輪
// 後丟棄——避免毒訊息永遠堵住）。

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:bridge_app/services/brain_container/extraction/smart_memory_extractor.dart';
import 'package:bridge_app/services/memory_store.dart';

/// Dreaming 緩衝器（單例）。
class DreamBuffer {
  DreamBuffer._();
  static final DreamBuffer instance = DreamBuffer._();

  static const _triggerCount = 10; // 滿 N 則觸發
  static const _idleTimeout = Duration(minutes: 5);
  static const _maxRetries = 2;

  final List<_BufferedMessage> _buffer = [];
  Timer? _idleTimer;
  bool _dreaming = false;

  String _agentName = '夥伴';
  String _companionId = '';

  /// 訊息入列。由 chat_controller 每則使用者訊息呼叫。
  ///
  /// [alreadyExtracted] 該則訊息快車道（正則）已提取的記憶——做夢時
  /// 統一去重用。
  void add(String message, {required String agentName, required String companionId, List<String> alreadyExtracted = const []}) {
    _agentName = agentName;
    _companionId = companionId;
    _buffer.add(_BufferedMessage(
      message: message,
      fastLaneExtracted: List.unmodifiable(alreadyExtracted),
    ));

    // 防毒訊息堆積：buffer 上限 30（超過丟最舊）
    if (_buffer.length > 30) {
      _buffer.removeRange(0, _buffer.length - 30);
    }

    if (_buffer.length >= _triggerCount) {
      _dream(); // 滿批即夢（不用等閒置）
    } else {
      _idleTimer?.cancel();
      _idleTimer = Timer(_idleTimeout, _dream);
    }
  }

  /// 做夢：批次抽取 + 寫入。
  Future<void> _dream() async {
    _idleTimer?.cancel();
    if (_dreaming || _buffer.isEmpty) return;
    _dreaming = true;

    final batch = List<_BufferedMessage>.from(_buffer);
    _buffer.clear();

    try {
      final messages = batch.map((b) => b.message).toList();
      final alreadyExtracted = batch
          .expand((b) => b.fastLaneExtracted)
          .toSet()
          .toList();

      final result = await SmartMemoryExtractor.instance.extractBatch(
        messages: messages,
        alreadyExtracted: alreadyExtracted,
      );

      if (result.hasFacts) {
        final written = await SmartMemoryExtractor.instance
            .writeToBrainContainer(
          facts: result.facts,
          agent: _agentName,
          companionId: _companionId,
        );
        if (written.isNotEmpty) {
          debugPrint('[DreamBuffer] 做夢完成: ${batch.length} 則 → '
              '${written.length} 筆記憶');
          for (final fact in written) {
            await MemoryStore.add(fact.content);
          }
        }
      }
      // 成功（含無事實）→ 不回存，訊息功成身退
    } catch (e) {
      debugPrint('[DreamBuffer] 做夢失敗: $e');
      // 失敗 → 回存重試（帶 retry 計數）
      for (final b in batch) {
        final retry = b.retries + 1;
        if (retry <= _maxRetries) {
          _buffer.insert(0, b.copyWithRetries(retry));
        }
      }
    } finally {
      _dreaming = false;
      // 若做夢期間又有新訊息進來且已滿批 → 再夢
      if (_buffer.length >= _triggerCount) {
        _dream();
      } else if (_buffer.isNotEmpty) {
        _idleTimer = Timer(_idleTimeout, _dream);
      }
    }
  }

  /// 測試/除錯用：當前緩衝狀態。
  int get pendingCount => _buffer.length;
  bool get isDreaming => _dreaming;
}

class _BufferedMessage {
  final String message;
  final List<String> fastLaneExtracted;
  final int retries;

  const _BufferedMessage({
    required this.message,
    this.fastLaneExtracted = const [],
    this.retries = 0,
  });

  _BufferedMessage copyWithRetries(int r) => _BufferedMessage(
        message: message,
        fastLaneExtracted: fastLaneExtracted,
        retries: r,
      );
}
