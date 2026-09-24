// workflow_executor.dart
// SemiCanvas Phase 2b: 資料流傳遞 + 節點執行
// 按 DAG 拓撲順序執行節點，傳遞輸出→輸入
//
// 設計文件: semicanvas-design.md §2.4
// [教練 Agent 2026-08-01] v2: 支援圖片 binary data 在節點間傳遞

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/models/entity_graph/canvas_props.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/semicanvas/dag_engine.dart';
import 'package:bridge_app/services/routines/system_routine_store.dart'; // [Blue 拍板] 招式節點
import 'package:bridge_app/services/routines/system_routine_player.dart'; // [Blue 拍板] 招式節點

/// 單一節點的執行結果
class NodeExecutionResult {
  final String nodeId;
  final bool success;
  final String? output;
  final String? errorMessage;

  /// [教練 Agent 2026-08-01] 圖片 binary data（生成的圖片位元組）
  final Uint8List? imageData;

  /// [教練 Agent 2026-08-01] 圖片 URL（如果 API 回傳 URL 而非 b64）
  final String? imageUrl;

  /// [教練 Agent 2026-08-25 F-1] 附加參數 — 節點執行後想寫回 params 的額外資料。
  /// 素材池用它把 AI 候選寫回節點 params，供採用 UI 讀取。
  final Map<String, dynamic>? extraParams;

  const NodeExecutionResult({
    required this.nodeId,
    required this.success,
    this.output,
    this.errorMessage,
    this.imageData,
    this.imageUrl,
    this.extraParams,
  });

  /// 工廠：成功（純文字）
  factory NodeExecutionResult.text(String nodeId, String output) {
    return NodeExecutionResult(nodeId: nodeId, success: true, output: output);
  }

  /// 工廠：成功（文字 + 圖片）
  /// [小葵 2026-09-24 定案圖組] 加 extraParams——gallery 整組圖寫回 params
  factory NodeExecutionResult.withImage(
    String nodeId,
    String output, {
    Uint8List? imageData,
    String? imageUrl,
    Map<String, dynamic>? extraParams,
  }) {
    return NodeExecutionResult(
      nodeId: nodeId,
      success: true,
      output: output,
      imageData: imageData,
      imageUrl: imageUrl,
      extraParams: extraParams,
    );
  }

  /// 工廠：失敗
  factory NodeExecutionResult.failure(String nodeId, String error) {
    return NodeExecutionResult(
      nodeId: nodeId,
      success: false,
      errorMessage: error,
    );
  }
}

/// 上游輸出 — 包含文字和圖片
/// [教練 Agent 2026-08-01] 取代 Map<String, String>，支援圖片傳遞
class UpstreamData {
  /// 文字輸出（ nodeId → output text ）
  final Map<String, String> texts;

  /// 圖片輸出（ nodeId → base64 encoded image ）
  final Map<String, String> base64Images;

  /// 圖片 URL 輸出（ nodeId → url ）
  final Map<String, String> imageUrls;

  const UpstreamData({
    this.texts = const {},
    this.base64Images = const {},
    this.imageUrls = const {},
  });

  /// 所有文字合併
  String get combinedText => texts.values.join('\n');

  /// 是否有任何圖片
  bool get hasImage => base64Images.isNotEmpty || imageUrls.isNotEmpty;

  /// 第一張圖片的 base64（如果有）
  String? get firstBase64Image =>
      base64Images.values.isNotEmpty ? base64Images.values.first : null;

  /// 第一張圖片的 URL（如果有）
  String? get firstImageUrl =>
      imageUrls.values.isNotEmpty ? imageUrls.values.first : null;
}

/// 節點執行回調 — 由外部注入實際執行邏輯
///
/// 接收：節點 ID、節點型別、參數、上游輸出（文字+圖片）
/// 回傳：執行結果（成功/失敗 + 輸出 + 可選圖片）
/// [教練 Agent 2026-08-01] v2: upstreamData 取代 upstreamOutputs
typedef NodeExecutor = Future<NodeExecutionResult> Function(
  String nodeId,
  WorkflowNodeType? nodeType,
  Map<String, dynamic> params,
  UpstreamData upstreamData,
);

/// 執行進度回調
///
/// 每個節點狀態變更時呼叫：
/// - nodeId, CanvasVisualState (active/done/blocked)
/// [教練 Agent 2026-08-01] v2: 加 imageData + imageUrl 支援圖片結果
typedef ExecutionProgressCallback = void Function(
  String nodeId,
  CanvasVisualState state,
  String? output, {
  Uint8List? imageData,
  String? imageUrl,
  Map<String, dynamic>? extraParams, // [教練 Agent 2026-08-25 F-1] 素材池候選寫回
});

/// 工作流執行器 — 按 DAG 拓撲順序執行節點。
class WorkflowExecutor {
  final EntityGraphService entityGraph;
  final DagEngine dagEngine;
  final NodeExecutor nodeExecutor;

  /// [教練 Agent 2026-08-26 跨畫布洩漏修復] 只執行這個畫布的節點。
  final String? canvasId;

  /// [教練 Agent 2026-08-21] 自律——首張檢查點回調
  /// 第一個付費資產（圖/影/音）生成完成後暫停執行，讓使用者看預覽決定。
  /// 回傳 true=繼續跑完；false=中止。
  /// reason: 'image' | 'video' | 'music'
  /// [教練 Agent 2026-08-26 使用者 三刀之三] pendingPaidCount＝本輪待生成的付費節點總數
  /// （含本張）。彈窗直接告訴使用者「繼續＝還會生成 N-1 張」，不必心算。
  final Future<bool> Function(String reason, Uint8List? imageData, String? imageUrl,
      int pendingPaidCount)?
      onFirstPaidCheckpoint;

  /// 首張檢查點只問一次（本輪執行內）
  bool _paidCheckpointDone = false;

  WorkflowExecutor({
    required this.entityGraph,
    required this.dagEngine,
    required this.nodeExecutor,
    this.canvasId,
    this.onFirstPaidCheckpoint,
  });

  Future<List<NodeExecutionResult>> execute({
    ExecutionProgressCallback? onProgress,
    void Function(String fromId, String toId)? onFlowParticle,
  }) async {
    // 1. DAG 分析
    final dagResult = await dagEngine.analyze();
    if (dagResult.hasCycle) return [];

    // 2. 取得所有畫布節點
    final canvasEntries = await entityGraph.getCanvasNodes(canvasId: canvasId);
    final nodeMap = <String, CanvasEntry>{};
    for (final entry in canvasEntries) {
      nodeMap[entry.entity.id] = entry;
    }

    // 3. 收集上游輸出（隨執行推進填充）
    final textOutputs = <String, String>{};
    final imageB64Outputs = <String, String>{};
    final imageUrlOutputs = <String, String>{};
    final results = <NodeExecutionResult>[];

    // [小葵 2026-09-24 Blue 令·智慧閘門] 本輪生成上限＝畫布付費節點數。
    // 原則（Blue 原話）：滑鼠鍵盤點的執行都是使用者執行，應該 PASS；
    // 要控制的是「自動執行超過節點內容數量的生成」——超過＝迴圈/重試
    // 失控，叫停任務（不是殺 App）。取代外部 burn_watch 數檔案的粗暴法。
    int paidNodeCount = 0;
    for (final entry in nodeMap.values) {
      final t = entry.entity.canvasProps?.nodeType;
      if (t == WorkflowNodeType.imageGen ||
          t == WorkflowNodeType.videoGen ||
          t == WorkflowNodeType.musicGen ||
          t == WorkflowNodeType.characterLock ||
          t == WorkflowNodeType.tts) {
        paidNodeCount++;
      }
    }
    int generatedCount = 0;
    const kMaxPaidPerRun = 20; // 保險絲：節點數再多也不超過 20（正常 workflow 遠不及）
    final runLimit = paidNodeCount > kMaxPaidPerRun ? kMaxPaidPerRun : paidNodeCount;

    // 4. 逐層執行
    for (final level in dagResult.executionLevels) {
      final levelResults = await Future.wait(
        level.map((nodeId) => _executeNode(
              nodeId,
              nodeMap,
              textOutputs,
              imageB64Outputs,
              imageUrlOutputs,
              onProgress,
              onFlowParticle,
            )),
      );
      results.addAll(levelResults);

      // [小葵 2026-09-24 智慧閘門] 本層有新生成 → 計數；超過本輪上限＝
      // 疑似失控（一個節點不該生成兩次以上），立即中止後續層。
      // 已生成的成果照常回傳（不浪費已花的錢），任務停止而非殺 App。
      for (final r in levelResults) {
        if (r.success && (r.imageData != null || r.imageUrl != null)) {
          final t = nodeMap[r.nodeId]?.entity.canvasProps?.nodeType;
          if (t == WorkflowNodeType.imageGen ||
              t == WorkflowNodeType.videoGen ||
              t == WorkflowNodeType.musicGen ||
              t == WorkflowNodeType.characterLock ||
              t == WorkflowNodeType.tts) {
            generatedCount++;
          }
        }
      }
      if (generatedCount > runLimit) {
        onProgress == null
            ? null
            : onProgress(
                level.last,
                CanvasVisualState.blocked,
                '🛑 智慧閘門：本輪已生成 $generatedCount 張超過付費節點數 $paidNodeCount——疑似失控，任務中止（App 不關閉）。',
              );
        return results;
      }

      // [教練 Agent 2026-08-21] 自律——首張檢查點
      // 本層產出付費資產且尚未檢查過 → 暫停，使用者看過預覽才繼續。
      // $33 教訓：100 張跑完才看見全廢；第一張就該停下來。
      if (onFirstPaidCheckpoint != null && !_paidCheckpointDone) {
        String? paidReason;
        Uint8List? paidImage;
        String? paidUrl;
        // [教練 Agent 2026-08-26 使用者 三刀之三] 本輪付費節點總數（圖/影/音）
        int pendingPaidCount = 0;
        for (final entry in nodeMap.values) {
          final t = entry.entity.canvasProps?.nodeType;
          if (t == WorkflowNodeType.imageGen ||
              t == WorkflowNodeType.videoGen ||
              t == WorkflowNodeType.musicGen) {
            pendingPaidCount++;
          }
        }
        for (final r in levelResults) {
          if (r.success && (r.imageData != null || r.imageUrl != null)) {
            final type = nodeMap[r.nodeId]?.entity.canvasProps?.nodeType;
            if (type == WorkflowNodeType.imageGen ||
                type == WorkflowNodeType.videoGen ||
                type == WorkflowNodeType.musicGen) {
              paidReason = type == WorkflowNodeType.imageGen
                  ? 'image'
                  : (type == WorkflowNodeType.videoGen ? 'video' : 'music');
              paidImage = r.imageData;
              paidUrl = r.imageUrl;
              break;
            }
          }
        }
        if (paidReason != null) {
          _paidCheckpointDone = true;
          final goOn = await onFirstPaidCheckpoint!(
              paidReason, paidImage, paidUrl, pendingPaidCount);
          if (!goOn) {
            // 使用者喊停——後續層不執行，已有成果照常回傳
            return results;
          }
        }
      }

      // 收集輸出供下層使用
      for (final result in levelResults) {
        if (result.success) {
          if (result.output != null) {
            textOutputs[result.nodeId] = result.output!;
          }
          if (result.imageData != null) {
            // 把 binary 轉成 base64 傳遞
            imageB64Outputs[result.nodeId] =
                _bytesToBase64(result.imageData!);
          }
          if (result.imageUrl != null) {
            imageUrlOutputs[result.nodeId] = result.imageUrl!;
          }
        }
      }
    }

    return results;
  }

  /// 執行單一節點
  Future<NodeExecutionResult> _executeNode(
    String nodeId,
    Map<String, CanvasEntry> nodeMap,
    Map<String, String> allTextOutputs,
    Map<String, String> allImageB64,
    Map<String, String> allImageUrls,
    ExecutionProgressCallback? onProgress,
    void Function(String, String)? onFlowParticle,
  ) async {
    final entry = nodeMap[nodeId];
    if (entry == null) {
      return NodeExecutionResult.failure(nodeId, '節點不存在於畫布');
    }

    final props = entry.props;
    final nodeType = props.nodeType;
    final params = props.params;

    // 收集上游輸出（文字 + 圖片）
    final upstreamTexts = <String, String>{};
    final upstreamImagesB64 = <String, String>{};
    final upstreamImageUrls = <String, String>{};
    final upstream = await dagEngine.getUpstream(nodeId);
    for (final upId in upstream) {
      if (allTextOutputs.containsKey(upId)) {
        upstreamTexts[upId] = allTextOutputs[upId]!;
        onFlowParticle?.call(upId, nodeId);
      }
      if (allImageB64.containsKey(upId)) {
        upstreamImagesB64[upId] = allImageB64[upId]!;
      }
      if (allImageUrls.containsKey(upId)) {
        upstreamImageUrls[upId] = allImageUrls[upId]!;
      }
    }

    final upstreamData = UpstreamData(
      texts: upstreamTexts,
      base64Images: upstreamImagesB64,
      imageUrls: upstreamImageUrls,
    );

    // 設為 active
    await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.active);
    onProgress?.call(nodeId, CanvasVisualState.active, null);

    // 非 workflow 節點
    if (nodeType == null) {
      await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.done);
      onProgress?.call(nodeId, CanvasVisualState.done, entry.entity.title);
      return NodeExecutionResult.text(nodeId, entry.entity.title);
    }

    // 🥋 招式節點 [Blue 拍板 2026-09-12]——重播訓練AI夥伴錄的招式
    // params: moveId（招式 id）或 moveName（名稱模糊匹配）
    // 上游文字若含「overrideText」參數可覆蓋打字內容（參數化招式）
    if (nodeType == WorkflowNodeType.move) {
      final moveId = params['moveId']?.toString();
      final moveName = params['moveName']?.toString();
      final routines = await SystemRoutineStore.instance.list();
      SavedRoutine? move;
      if (moveId != null && moveId.isNotEmpty) {
        move = routines.where((r) => r.id == moveId).firstOrNull;
      }
      move ??= routines
          .where((r) => moveName != null && r.name.contains(moveName))
          .firstOrNull;
      if (move == null) {
        await entityGraph.updateCanvasVisualState(
            nodeId, CanvasVisualState.blocked);
        return NodeExecutionResult.failure(
            nodeId, '找不到招式：${moveId ?? moveName ?? "（未指定）"}');
      }
      onProgress?.call(nodeId, CanvasVisualState.active,
          '🥋 使出「${move.name}」（${move.stepCount} 步）');
      // 執行（gate 圍欄與 Esc 急停在 Player 內建）
      final res = await SystemRoutinePlayer.instance.replay(move.events);
      final summary = '招式「${move.name}」完成：'
          '${res.played} 步執行、${res.skipped} 步跳過';
      await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.done);
      return NodeExecutionResult.text(nodeId, summary);
    }

    // Input 節點
    if (nodeType == WorkflowNodeType.input) {
      final output = params['defaultValue']?.toString() ??
          params['content']?.toString() ??
          '';
      await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.done);
      onProgress?.call(nodeId, CanvasVisualState.done, output);
      return NodeExecutionResult.text(nodeId, output);
    }

    // Output 節點
    if (nodeType == WorkflowNodeType.output) {
      final combined = upstreamData.combinedText;
      await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.done);
      onProgress?.call(nodeId, CanvasVisualState.done, combined);
      return NodeExecutionResult(nodeId: nodeId, success: true, output: combined);
    }

    // Merge 節點
    if (nodeType == WorkflowNodeType.merge) {
      final separator = params['separator']?.toString() ?? '\n';
      final strategy = params['strategy']?.toString() ?? 'concat';
      String merged;
      switch (strategy) {
        case 'first':
          merged = upstreamTexts.values.firstOrNull ?? '';
          break;
        case 'last':
          merged = upstreamTexts.values.lastOrNull ?? '';
          break;
        default:
          merged = upstreamTexts.values.join(separator);
      }
      await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.done);
      onProgress?.call(nodeId, CanvasVisualState.done, merged);
      return NodeExecutionResult(nodeId: nodeId, success: true, output: merged);
    }

    // 其他節點型別：委託給 nodeExecutor
    try {
      final result = await nodeExecutor(nodeId, nodeType, params, upstreamData);
      if (result.success) {
        await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.done);
        // [教練 Agent 2026-08-01] 傳圖片資料到 UI
        onProgress?.call(
          nodeId,
          CanvasVisualState.done,
          result.output,
          imageData: result.imageData,
          imageUrl: result.imageUrl,
          extraParams: result.extraParams, // [教練 Agent 2026-08-25 F-1]
        );
      } else {
        await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.blocked);
        // [小葵 2026-09-24 Blue 令·失敗要顯示] 舊碼 output 送 null——
        // 失敗原因（API 錯誤、金鑰問題）整個被吞掉，畫布只顯示紅點、
        // 使用者完全不知道發生什麼（「懸在心頭」）。
        // 修：errorMessage 隨 blocked 一起送達 UI。
        onProgress?.call(
          nodeId,
          CanvasVisualState.blocked,
          result.errorMessage != null ? '❌ ${result.errorMessage}' : null,
        );
      }
      return result;
    } catch (e) {
      await entityGraph.updateCanvasVisualState(nodeId, CanvasVisualState.blocked);
      onProgress?.call(nodeId, CanvasVisualState.blocked, '❌ $e');
      return NodeExecutionResult.failure(nodeId, e.toString());
    }
  }

  /// 重設所有節點為 idle
  Future<void> reset() async {
    final canvasEntries = await entityGraph.getCanvasNodes(canvasId: canvasId);
    for (final entry in canvasEntries) {
      await entityGraph.updateCanvasVisualState(
        entry.entity.id,
        CanvasVisualState.idle,
      );
    }
  }

  /// Uint8List → base64 string
  static String _bytesToBase64(Uint8List bytes) {
    return base64.encode(bytes);
  }
}
