// app_log_buffer.dart
// [Phase 1 2026-07-17] 原生 Agent 自維修工具 #4 基礎：App Log Ring Buffer
//
// 收集 App 運行時的 debugPrint 輸出到記憶體 ring buffer。
// 讓 Agent 能讀取最近的 log 來診斷問題。
//
// 原理：覆蓋 debugPrint = 自訂函數，同時寫 ring buffer + 原始 debugPrint。
// Ring buffer 上限 500 行（約 50KB），超出自動丟棄最舊的。

import 'dart:collection';
import 'package:flutter/foundation.dart';

/// 全域 ring buffer，Agent 可透過 read_app_log 工具讀取
final AppLogBuffer appLogBuffer = AppLogBuffer();

class AppLogBuffer {
  final Queue<String> _lines = Queue();
  static const int _maxLines = 2000;

  bool _installed = false;

  /// 安裝：攔截 debugPrint 輸出
  void install() {
    if (_installed) return;
    _installed = true;

    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      // 寫入 ring buffer
      add(message ?? '');

      // 同時呼叫原始 debugPrint（保持 console 輸出）
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };

    add('[AppLogBuffer] 已安裝，開始收集 log');
  }

  /// 新增一行 log
  void add(String line) {
    // [教練 Agent 2026-07-18] 過濾掉刷屏的 render error，保留有用的 log
    if (line.startsWith('Another exception was thrown: RenderBox was not laid out')) {
      return; // 丟棄刷屏的 render error
    }
    _lines.add(line);
    while (_lines.length > _maxLines) {
      _lines.removeFirst();
    }
  }

  /// 讀取最近的 N 行 log
  /// [tailLines] = 取最後幾行（預設 100）
  /// [filter] = 可選關鍵字過濾
  String read({int tailLines = 100, String? filter}) {
    if (_lines.isEmpty) {
      return '（log buffer 為空）';
    }

    var lines = _lines.toList();

    // 過濾
    if (filter != null && filter.isNotEmpty) {
      lines = lines.where((l) => l.toLowerCase().contains(filter.toLowerCase())).toList();
    }

    // 取最後 N 行
    final start = lines.length > tailLines ? lines.length - tailLines : 0;
    final sliced = lines.sublist(start);

    final buffer = StringBuffer();
    buffer.writeln('=== App Log（最近 ${sliced.length} 行${filter != null ? "，過濾：$filter" : ""}）===');
    for (var i = 0; i < sliced.length; i++) {
      buffer.writeln(sliced[i]);
    }
    buffer.writeln('=== 共 ${_lines.length} 行在 buffer 中 ===');

    return buffer.toString();
  }

  /// 清空 buffer
  void clear() {
    _lines.clear();
    add('[AppLogBuffer] 已清空');
  }
}
