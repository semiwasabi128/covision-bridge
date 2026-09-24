// system_routine_recorder.dart
// [刀 5 延伸 SR.2 2026-09-09 Blue 令] 全電腦示範錄製——Dart 端。
//
// 「錄全電腦的動作，agent 一學就會——解決 MCP 不完備時的代操作問題。」
//
// 架構（設計稿 §2 跨平台分層約束）：
//   Dart 層平台中立——SystemRoutineEvent 是正規化 schema，
//   macOS 後端（SystemRoutineNative.swift）餵原始 dict，這裡正規化。
//   未來 Windows 後端（UIA）餵同款 dict 即可，Dart 層零改動。
//
// 隱私鐵則：Swift 端已遮罩密碼框；Dart 端再驗一次（雙保險）。

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 正規化事件——平台中立的 routine 檔本體
class SystemRoutineEvent {
  final int seq;
  final double t; // epoch 秒
  final String action; // click | key | scroll
  final String app;
  final String window;
  final String role; // AX 角色（AXButton 等）——重播優先錨點
  final String title; // 元素標題——重播優先錨點
  final String? value; // 值（已遮罩/截斷）
  final bool masked;
  final double? x;
  final double? y;
  final int? keyCode;
  final List<String>? mods;
  final String? text; // [層 1 SR.5] type 事件的重組文字（密碼框遮罩）
  final int? maskedLength; // masked type 事件的字數（重播提示用）

  const SystemRoutineEvent({
    required this.seq,
    required this.t,
    required this.action,
    required this.app,
    this.window = '',
    this.role = '',
    this.title = '',
    this.value,
    this.masked = false,
    this.x,
    this.y,
    this.keyCode,
    this.mods,
    this.text,
    this.maskedLength,
  });

  /// 從原生 dict 正規化（macOS 後端格式；未來 Windows 同款）
  factory SystemRoutineEvent.fromMap(Map<dynamic, dynamic> m, int seq) {
    final masked = (m['masked'] as bool?) ?? false;
    var value = m['value'] as String?;
    // 雙保險：Swift 已遮罩，這裡再驗
    if (masked) value = '****';
    if (value != null && value.length > 30) {
      value = '${value.substring(0, 30)}…';
    }
    return SystemRoutineEvent(
      seq: seq,
      t: (m['t'] as num?)?.toDouble() ?? 0,
      action: (m['action'] as String?) ?? '',
      app: (m['app'] as String?) ?? '',
      window: (m['window'] as String?) ?? '',
      role: (m['role'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      value: value,
      masked: masked,
      x: (m['x'] as num?)?.toDouble(),
      y: (m['y'] as num?)?.toDouble(),
      keyCode: (m['keyCode'] as num?)?.toInt(),
      mods: (m['mods'] as List?)?.cast<String>(),
    );
  }

  /// 人類可讀操作故事（刀 5 同款哲學）
  String get story {
    switch (action) {
      case 'click':
        final target = title.isNotEmpty
            ? '「$title」'
            : (role.isNotEmpty ? role : '位置');
        return '在 $app 點了 $target';
      case 'key':
        final mod = (mods ?? []).isEmpty ? '' : '${mods!.join("+")}+';
        return '在 $app 按了 $mod${_keyLabel(keyCode ?? -1)}';
      case 'scroll':
        final dir = (y ?? 0) >= 0 ? '下' : '上';
        return '在 $app 滾動向$dir';
      default:
        return '$app $action';
    }
  }

  static String _keyLabel(int code) {
    const map = {
      36: 'Return', 48: 'Tab', 49: 'Space', 51: 'Delete', 53: 'Esc',
      123: '←', 124: '→', 125: '↓', 126: '↑',
    };
    return map[code] ?? 'key$code';
  }

  Map<String, dynamic> toMap() => {
        'seq': seq, 't': t, 'action': action, 'app': app,
        'window': window, 'role': role, 'title': title,
        'value': value, 'masked': masked, 'x': x, 'y': y,
        'keyCode': keyCode, 'mods': mods,
      };
}

/// 全電腦示範錄製器——單例
class SystemRoutineRecorder {
  SystemRoutineRecorder._();
  static final SystemRoutineRecorder instance = SystemRoutineRecorder._();

  static const _methodCh = MethodChannel('bridge.system_routine.macos.v1');
  static const _eventCh =
      EventChannel('bridge.system_routine.macos.v1/events');

  StreamSubscription? _sub;
  final List<SystemRoutineEvent> _events = [];
  DateTime? _startedAt;
  bool _recording = false;
  int _seq = 0;

  bool get isRecording => _recording;
  int get eventCount => _events.length;
  List<SystemRoutineEvent> get events => List.unmodifiable(_events);
  List<String> get story => _events.map((e) => e.story).toList();

  /// 開始錄製（冪等）
  Future<void> start() async {
    if (_recording) return;
    _ensureSubscription();
    try {
      await _methodCh.invokeMethod('start');
    } on PlatformException catch (e) {
      debugPrint('[SystemRoutine] start 失敗: ${e.message}');
      rethrow;
    }
    _recording = true;
    _startedAt = DateTime.now();
    _events.clear();
    _seq = 0;
    debugPrint('[SystemRoutine] 開始錄製（全電腦）');
  }

  void _ensureSubscription() {
    _sub ??= _eventCh.receiveBroadcastStream().listen((raw) {
      if (!_recording || raw is! Map) return;
      final e = SystemRoutineEvent.fromMap(raw, _seq++);
      _events.add(e);
      debugPrint('[SystemRoutine] ${e.seq + 1}. ${e.story}');
    }, onError: (e) {
      debugPrint('[SystemRoutine] 事件流錯誤: $e');
    });
  }

  /// 停止——回傳事件快照（呼叫端存檔/轉範本）
  Future<List<SystemRoutineEvent>?> stop() async {
    if (!_recording) return null;
    try {
      await _methodCh.invokeMethod('stop');
    } on PlatformException {
      // 停止失敗也要清狀態（寧可漏事件不可卡錄製）
    }
    _recording = false;
    debugPrint('[SystemRoutine] 停止：${_events.length} 個事件');
    return List.of(_events);
  }

  /// 放棄
  Future<void> discard() async {
    if (_recording) {
      try {
        await _methodCh.invokeMethod('stop');
      } on PlatformException {
        // ignore
      }
    }
    _recording = false;
    _events.clear();
    _seq = 0;
  }

  /// 匯出 routine 檔（平台中立 JSON）
  Map<String, dynamic> export() => {
        'version': 1,
        'recordedAt': _startedAt?.toIso8601String(),
        'events': _events.map((e) => e.toMap()).toList(),
      };
}
