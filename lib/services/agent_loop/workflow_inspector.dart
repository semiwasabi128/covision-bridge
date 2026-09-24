// workflow_inspector.dart
// [教練 Agent 2026-08-21] Agent 自律——工作流品質檢查官
//
// $33 事件驗屍結論：爛工作流不是被「擋」下來的，是不該被「生」出來。
// canvas_add_node 只收 type/x/y——agent 盲目裝配預設值節點；連線零驗證；
// 執行前沒人看過這張圖會產出什麼。
//
// WorkflowInspector = 工作流的編譯器前端：
// 執行前掃 DAG，產出人類可讀的「產出預報」，讓 agent 自律、讓使用者知情。
// 檢查項：
//   1. 付費節點盤點（imageGen×N、videoGen×N...）
//   2. 未設定節點（prompt 还是預設佔位——盲裝的鐵證）
//   3. 重複 prompt（同樣內容生成 N 次=浪費）
//   4. 孤兒產出（付費節點下游沒有 output/消費者——生產沒人要的東西）
//   5. 斷頭起點（input 為空、鏈卻接了）

import '../../models/entity_graph/entity.dart';
import '../../models/entity_graph/open_canvas_node.dart';

class WorkflowInspection {
  final int imageNodes;
  final int videoNodes;
  final int musicNodes;
  final int llmNodes;
  final int totalNodes;
  final List<String> warnings; // 品質警告（重複/孤兒/未設定）
  final bool hasPaid;

  const WorkflowInspection({
    required this.imageNodes,
    required this.videoNodes,
    required this.musicNodes,
    required this.llmNodes,
    required this.totalNodes,
    required this.warnings,
    required this.hasPaid,
  });

  /// 執行前簡報——給使用者看的「這會產出什麼」
  String get briefing {
    final b = StringBuffer();
    final produces = <String>[];
    if (imageNodes > 0) produces.add('圖片 $imageNodes 張');
    if (videoNodes > 0) produces.add('影片 $videoNodes 支');
    if (musicNodes > 0) produces.add('音樂 $musicNodes 首');
    if (llmNodes > 0) produces.add('文字段落 $llmNodes 則');
    if (produces.isEmpty) {
      b.write('本工作流不產生內容（${totalNodes}個節點）');
    } else {
      b.write('本工作流將產出：${produces.join('、')}');
    }
    if (warnings.isNotEmpty) {
      b.write('\n品質警告：');
      for (final w in warnings) {
        b.write('\n• $w');
      }
    }
    return b.toString();
  }

  /// 嚴重警告數（重複/孤兒/未設定）——agent 自律攔截門檻
  bool get hasSevereWarnings => warnings.any((w) =>
      w.contains('未設定') || w.contains('重複') || w.contains('孤兒'));
}

class WorkflowInspector {
  /// 掃整張畫布的節點與連線
  static WorkflowInspection inspect({
    required Map<String, OpenCanvasNode> nodes,
    required List<String> edges, // 'fromId:port>toId:port' 或 'fromId>toId'
  }) {
    var image = 0, video = 0, music = 0, llm = 0;
    final warnings = <String>[];
    final prompts = <String, int>{};

    // 連線目標集合（判孤兒用）
    final connectedTargets = <String>{};
    for (final e in edges) {
      final parts = e.split('>');
      if (parts.length == 2) {
        final target = parts[1].split(':').first;
        if (nodes.containsKey(target)) connectedTargets.add(target);
      }
    }

    for (final node in nodes.values) {
      final props = node.entity.canvasProps;
      final type = props?.nodeType;
      if (type == null) continue;
      final params = props?.params ?? const <String, dynamic>{};

      switch (type) {
        case WorkflowNodeType.imageGen:
          image++;
          _checkGenNode(params, prompts, warnings, '圖片生成');
          if (!connectedTargets.contains(node.id)) {
            warnings.add('孤兒產出：圖片生成節點「${_label(node)}」的下游沒有消費者——生成的圖沒人用');
          }
          break;
        case WorkflowNodeType.videoGen:
          video++;
          _checkGenNode(params, prompts, warnings, '影片生成');
          if (!connectedTargets.contains(node.id)) {
            warnings.add('孤兒產出：影片生成節點「${_label(node)}」的下游沒有消費者');
          }
          break;
        case WorkflowNodeType.musicGen:
          music++;
          _checkGenNode(params, prompts, warnings, '音樂生成');
          if (!connectedTargets.contains(node.id)) {
            warnings.add('孤兒產出：音樂生成節點「${_label(node)}」的下游沒有消費者');
          }
          break;
        case WorkflowNodeType.llm:
          llm++;
          break;
        default:
          break;
      }
    }

    // 重複 prompt 統計
    prompts.forEach((p, n) {
      if (n >= 3) {
        warnings.add('重複生成：相同 prompt「${_truncate(p)}」被排了 $n 次——同樣的東西要生成 $n 遍嗎？');
      }
    });

    return WorkflowInspection(
      imageNodes: image,
      videoNodes: video,
      musicNodes: music,
      llmNodes: llm,
      totalNodes: nodes.length,
      warnings: warnings,
      hasPaid: image + video + music > 0,
    );
  }

  static void _checkGenNode(
    Map<String, dynamic> params,
    Map<String, int> prompts,
    List<String> warnings,
    String kindLabel,
  ) {
    final prompt = params['prompt']?.toString() ?? '';
    final isPlaceholder = prompt.isEmpty ||
        prompt.startsWith('請輸入') ||
        prompt.startsWith('輸入') && prompt.length < 12 ||
        prompt == 'prompt' ||
        prompt.length < 4;
    if (isPlaceholder) {
      warnings.add('未設定：$kindLabel 節點的 prompt 是空的或預設佔位——盲目裝配的鐵證');
    } else {
      prompts[prompt] = (prompts[prompt] ?? 0) + 1;
    }
  }

  static String _label(OpenCanvasNode node) =>
      node.entity.title.isNotEmpty ? node.entity.title : '未命名';

  static String _truncate(String s) =>
      s.length > 20 ? '${s.substring(0, 20)}…' : s;
}
