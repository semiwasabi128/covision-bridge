// dream_reflection.dart
// [小葵 2026-09-22 Blue 規格] LLM 做夢版——大腦容器檢視歷史教訓/遺憾，
// 選出「值得給 LLM 看」的題材（帶標竿、標的物、明確難題），
// 交 LLM 敘事反思。每場夢 ≤8K tokens。
//
// 核心價值（Blue）：夢最珍貴的不是「告訴你解決了什麼」，
// 是明天主動告訴使用者「你想到了什麼」——也許是好答案也許不是，
// 所以成本不能太高。
//
// 設計：
// - 選材：EmbeddingGemma 向量檢索（本地零 token）——同主題的
//   傷口/教訓/遺憾聚類，選出「有明確要解決的事」的議題
// - 反思：單輪 LLM（雲端）只做敘事與聯想——輸入是向量選好的題材包，
//   輸出是「我想到了什麼」的提醒（非解決報告）
// - 預算：硬上限 8K tokens/場（題材包截斷 + 輸出 1K 內）
// - fail-open：向量或 LLM 失敗 → 退規則版（不因做夢卡死系統）
//
// 與規則版關係：規則版是地基本身（對帳、銷案、紅燈——確定論）；
// LLM 版處理「重評遺憾/跨域聯想」這種需要判斷力的題材。
// 兩者同場跑：規則版先收帳，LLM 版再做深夢。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api_service.dart';
import '../brain_container/embedding/embedding_service.dart';
import 'life_tree_store.dart';

/// 一個深夢題材（向量選出——帶標竿與難題）
class DreamTopic {
  final String theme; // 主題（傷口/教訓/遺憾群聚的質心語意）
  final List<String> clues; // 題材線索原文（截斷版）
  final String target; // 標的物：這個議題明確要解決的事
  final List<int> sourceIds; // 來源（pitfall id / branch id）

  const DreamTopic({
    required this.theme,
    required this.clues,
    required this.target,
    required this.sourceIds,
  });
}

/// LLM 深夢結果
class DeepDreamResult {
  final bool usedLlm; // false = 向量/LLM 失敗退規則版
  final String reflection; // 「我想到了什麼」——給使用者的提醒
  final int tokensIn;
  final int tokensOut;
  final String modelUsed;

  const DeepDreamResult({
    required this.usedLlm,
    required this.reflection,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.modelUsed = 'rule-engine',
  });
}

class DreamReflection {
  DreamReflection._();
  static final DreamReflection instance = DreamReflection._();

  /// 單場夢 token 硬上限（Blue 規格）
  static const int kTokenBudget = 8000;

  /// ── 第一步：向量選材（本地零 token）──
  ///
  /// 把傷口/教訓/遺憾全部 embed，以「目標議程」（紅燈+遺憾）為錨，
  /// 選出 cosine 最高的前幾群——每一群就是一個帶標竿的題材。
  Future<List<DreamTopic>> selectTopics({
    required List<String> anchors, // 議程錨（紅燈描述、遺憾原文）
    required List<(int, String)> corpus, // (id, text) 全歷史教訓/遺憾
    int maxTopics = 3,
  }) async {
    if (anchors.isEmpty || corpus.isEmpty) return [];
    final embedder = EmbeddingService.instance;

    // 錨向量
    final anchorVecs = <List<double>>[];
    for (final a in anchors.take(5)) {
      try {
        anchorVecs.add(await embedder.embedQuery(a));
      } catch (_) {}
    }
    if (anchorVecs.isEmpty) return []; // 向量不可用 → 退規則版

    // 全 corpus 評分（取對任一錨的最大相似度）
    final scored = <(double, int, String)>[];
    for (final (id, text) in corpus) {
      try {
        final v = await embedder.embedQuery(text);
        var best = 0.0;
        for (final a in anchorVecs) {
          best = best > _cos(a, v) ? best : _cos(a, v);
        }
        scored.add((best, id, text));
      } catch (_) {}
    }
    scored.sort((x, y) => y.$1.compareTo(x.$1));

    // 分群：高分線索按向量相近聚合（簡易貪婪——同主題歸一題材）
    final topics = <DreamTopic>[];
    final used = <int>{};
    for (final (score, id, text) in scored) {
      if (topics.length >= maxTopics) break;
      if (score < 0.45 || used.contains(id)) continue;
      // 聚合相近線索
      final clues = <String>[text];
      final ids = [id];
      try {
        final tv = await embedder.embedQuery(text);
        for (final (s2, id2, text2) in scored) {
          if (id2 == id || used.contains(id2) || clues.length >= 4) continue;
          final v2 = await embedder.embedQuery(text2);
          if (_cos(tv, v2) >= 0.75) {
            clues.add(text2);
            ids.add(id2);
          }
        }
      } catch (_) {}
      used.addAll(ids);
      topics.add(DreamTopic(
        theme: _firstLine(text),
        clues: clues.map(_clip).toList(),
        target: '從這些教訓與遺憾中，找出還沒被解決的那件事',
        sourceIds: ids,
      ));
    }
    debugPrint('[DreamReflection] 選材 ${topics.length} 群'
        '（corpus=${corpus.length}）');
    return topics;
  }

  /// ── 第二步：LLM 深夢（雲端，單輪，≤8K）──
  Future<DeepDreamResult> reflect({
    required List<DreamTopic> topics,
    String? model,
  }) async {
    if (topics.isEmpty) {
      return const DeepDreamResult(
          usedLlm: false, reflection: '沒有值得深夢的題材，安睡');
    }

    // 題材包（控制大小：每線索 ~100 chars，總輸入含 prompt ≤7K tokens）
    final buf = StringBuffer();
    for (var i = 0; i < topics.length; i++) {
      buf.writeln('### 題材 ${i + 1}：${topics[i].theme}');
      buf.writeln('標的：${topics[i].target}');
      for (final c in topics[i].clues) {
        buf.writeln('- $c');
      }
      buf.writeln();
    }
    final material = buf.toString();
    // 硬截斷（中文 ~2 chars/token，保留 2K 給 prompt+輸出）
    final capped = material.length > 10000
        ? '${material.substring(0, 10000)}\n…（題材截斷）'
        : material;

    const sys = '你是橋樑 App 的原生 Agent，正在做一場夢（離線反思）。'
        '規則：1) 夢的價值是「想到了什麼」不是「解決了什麼」——'
        '輸出的是給使用者的提醒，也許是好答案也許不是，誠實標示。'
        '2) 只依題材推論，禁止發明題材外的事實。3) 輸出 ≤5 行白話，'
        '禁工程術語。4) 每個想法標明來自哪個題材。';

    final user = '以下是白天累積的教訓與遺憾（向量檢索選出，'
        '已按相關度聚類）：\n\n$capped\n'
        '請從中提出 1-3 個「我想到了什麼」的提醒：每個想法一句話，'
        '說清楚它為什麼值得使用者注意（連到哪個未解難題）。'
        '寧可少而準，不要多而泛。';

    try {
      final r = await ApiService.completeWithReceipt(
        systemPrompt: sys,
        userPrompt: user,
        model: model,
      );
      // 預算檢查（超標記錄但不擋——下次選材收緊）
      // receipt 無 token 欄位——用字數估計（中文 ~2 chars/token）監控預算
      final estTokens = (sys.length + user.length + r.text.length) ~/ 2;
      if (estTokens > kTokenBudget) {
        debugPrint('[DreamReflection] ⚠️ 估計超預算 $estTokens/$kTokenBudget');
      }
      debugPrint('[DreamReflection] LLM 夢完成 ~${estTokens} tokens '
          'model=${r.provider}/${r.model}');
      return DeepDreamResult(
        usedLlm: true,
        reflection: r.text,
        tokensIn: estTokens,
        modelUsed: '${r.provider}/${r.model}',
      );
    } catch (e) {
      debugPrint('[DreamReflection] LLM 失敗退規則版: $e');
      return const DeepDreamResult(
          usedLlm: false, reflection: '夢的深層反思暫停（LLM 不通），僅規則對帳');
    }
  }

  // ── 工具 ──
  double _cos(List<double> a, List<double> b) {
    final len = a.length < b.length ? a.length : b.length;
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  String _firstLine(String t) =>
      t.split('\n').firstWhere((l) => l.trim().isNotEmpty,
          orElse: () => t);

  String _clip(String t) =>
      t.length > 120 ? '${t.substring(0, 120)}…' : t;
}

// dart:math 導入（cos 用）
