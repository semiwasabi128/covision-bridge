// agent_checkpoint.dart
// [2026-07-18] Checkpoint 協議 — 解決「重啟雞與蛋」問題
//
// 問題：Agent 重啟 App = 殺死自己。死後無法驗證、無法收口、無法回報。
// 解法：
//   1. 重啟前：寫 checkpoint（改了什麼、任務鏈跑到哪、重啟後要驗證什麼）
//   2. 重啟後：NativeAgentLoop 啟動時檢查 checkpoint → 載入 → 截圖驗證 → 推結果
//   3. 驗證完刪除 checkpoint（用完即丟）

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AgentCheckpoint {
  final String checkpointId;
  final String reason;           // 為什麼重啟（「驗證首頁改善」）
  final String? chainId;         // 如果在任務鏈中，鏈 ID
  final int? chainStepIndex;     // 鏈跑到第幾步
  final int? totalChainSteps;    // 鏈總共幾步
  final List<String> changedFiles; // 改了哪些檔案
  final String? expectedEffect;  // 預期看到什麼效果（給驗證用）
  final DateTime createdAt;

  AgentCheckpoint({
    required this.checkpointId,
    required this.reason,
    this.chainId,
    this.chainStepIndex,
    this.totalChainSteps,
    required this.changedFiles,
    this.expectedEffect,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'checkpoint_id': checkpointId,
    'reason': reason,
    if (chainId != null) 'chain_id': chainId,
    if (chainStepIndex != null) 'chain_step_index': chainStepIndex,
    if (totalChainSteps != null) 'total_chain_steps': totalChainSteps,
    'changed_files': changedFiles,
    if (expectedEffect != null) 'expected_effect': expectedEffect,
    'created_at': createdAt.toIso8601String(),
  };

  factory AgentCheckpoint.fromJson(Map<String, dynamic> j) => AgentCheckpoint(
    checkpointId: j['checkpoint_id'] as String,
    reason: j['reason'] as String,
    chainId: j['chain_id'] as String?,
    chainStepIndex: j['chain_step_index'] as int?,
    totalChainSteps: j['total_chain_steps'] as int?,
    changedFiles: (j['changed_files'] as List).cast<String>(),
    expectedEffect: j['expected_effect'] as String?,
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  bool get isPartOfChain => chainId != null;
  bool get hasMoreSteps =>
      chainStepIndex != null && totalChainSteps != null && chainStepIndex! < totalChainSteps! - 1;
}

/// Checkpoint 管理器
class AgentCheckpointManager {
  static final AgentCheckpointManager _instance = AgentCheckpointManager._();
  factory AgentCheckpointManager() => _instance;
  AgentCheckpointManager._();

  static const _fileName = 'restart_checkpoint.json';

  Future<String> get _checkpointPath async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/$_fileName';
  }

  /// 寫入 checkpoint（重啟前呼叫）
  Future<void> write(AgentCheckpoint checkpoint) async {
    final path = await _checkpointPath;
    final file = File(path);
    await file.writeAsString(jsonEncode(checkpoint.toJson()));
    debugPrint('[Checkpoint] 已寫入：${checkpoint.checkpointId} — ${checkpoint.reason}');
  }

  /// 讀取 checkpoint（重啟後呼叫）
  Future<AgentCheckpoint?> read() async {
    try {
      final path = await _checkpointPath;
      final file = File(path);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return AgentCheckpoint.fromJson(json);
    } catch (e) {
      debugPrint('[Checkpoint] 讀取失敗: $e');
      return null;
    }
  }

  /// 刪除 checkpoint（驗證完呼叫）
  Future<void> clear() async {
    try {
      final path = await _checkpointPath;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('[Checkpoint] 已清除');
      }
    } catch (e) {
      debugPrint('[Checkpoint] 清除失敗: $e');
    }
  }

  /// 是否有未完成的 checkpoint
  Future<bool> hasPending() async {
    final cp = await read();
    return cp != null;
  }
}
