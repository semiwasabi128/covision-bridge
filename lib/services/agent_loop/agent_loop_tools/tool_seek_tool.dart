// tool_seek_tool.dart
// [小葵 2026-09-22 Blue 設計] 工具櫃檯——工具區從「型錄」變「櫃檯」。
//
// 舊設計：36 個工具一句話簡介全塞 prompt（8.5K chars/輪，靜態大戶）。
// 新設計（Blue 拍板 2026-09-22）：prompt 只留一行「要做事先問精靈」，
// Agent 把意圖告訴 compass_toolseek，本地向量大腦（EmbeddingGemma）
// 直接吐出最相關的工具＋完整用法（含參數）。零 API token、~100ms。
//
// 拿錯工具（不夠用）→ Agent 換意圖詞重問或 tool_help 查全部清單，
// 過程記入 causal_ledger（toolName=tool_seek）——迭代成長的經驗素材，
// 夢境回顧時會變成檢索調校的養分。
//
// 對齊：羅盤（compass）= 導航中樞；生命樹 = 經驗積累。工具遞送屬於
// 「導航」職責，掛 compass_ 前綴與 compass_read/compass_seek 同族。

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../agent_tool.dart';
import '../agent_tool_registry.dart';
import '../../brain_container/embedding/embedding_service.dart';
import '../../causal/causal_ledger_service.dart';

/// CompassToolSeekTool — 向量工具櫃檯
///
/// Agent 用自然語言描述「我要做什麼」，本工具用 embedding 餘弦相似度
/// 從註冊表 36+ 工具中即時檢索最相關的 top-K，回傳完整用法。
class CompassToolSeekTool extends AgentTool {
  final AgentToolRegistry registry;

  CompassToolSeekTool(this.registry);

  @override
  String get name => 'compass_toolseek';

  @override
  String get description =>
      '工具櫃檯：告訴精靈你要做什麼（如「改程式碼」「看畫布」「查記憶」），'
      '即時用向量大腦遞給你最相關的工具與完整用法。不確定該用哪個工具時先問這裡。';

  @override
  List<AgentToolParamSpec> get paramSpecs => [
        const AgentToolParamSpec(
          name: 'intent',
          description: '你想做的事（自然語言，如「重啟 App」「搜尋本地知識」）',
          required: true,
        ),
        const AgentToolParamSpec(
          name: 'top_k',
          description: '回傳工具數（預設 3）',
          required: false,
          defaultValue: '3',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    final intent = args['intent'] as String?;
    if (intent == null || intent.trim().isEmpty) {
      return AgentToolResult.failure('請提供 intent 參數（你想做什麼）');
    }
    final topK = int.tryParse(args['top_k']?.toString() ?? '3') ?? 3;

    // 本地向量檢索（零 token）——EmbeddingGemma，K1 同款管線
    final embedder = EmbeddingService.instance;
    List<double>? queryVec;
    try {
      queryVec = await embedder.embedQuery(intent);
    } catch (e) {
      // fail-open：embedding 不可用時退回關鍵字比對（desc/name 包含）
      debugPrint('[ToolSeek] embedding 失敗退關鍵字: $e');
    }

    final candidates = <MapEntry<AgentTool, double>>[];
    for (final tool in registry.all) {
      if (tool.name == name) continue; // 不遞迴推薦自己
      double score = 0;
      if (queryVec != null) {
        final tv = _toolVector(tool);
        if (tv != null) score = _cosine(queryVec, tv);
      } else {
        final hay = '${tool.name} ${tool.description}'.toLowerCase();
        final hits = intent
            .toLowerCase()
            .split(RegExp(r'\s+'))
            .where((w) => w.length > 1)
            .where(hay.contains)
            .length;
        score = hits.toDouble();
      }
      candidates.add(MapEntry(tool, score));
    }
    candidates.sort((a, b) => b.value.compareTo(a.value));
    final top = candidates.take(topK).toList();

    // 記入因果帳本——「遞錯工具」回滾時這些記錄是調校素材（生命樹養分）
    try {
      CausalLedger.instance.record(CausalEntry(
        toolName: 'tool_seek',
        intervention: '意圖「$intent」→ 遞 ${top.map((t) => t.key.name).join(", ")}',
        contextDigest: 'score=${top.map((t) => t.value.toStringAsFixed(2)).join(",")}',
        observedOutcome: 'Agent 按收到的工具繼續任務；若回滾（工具不合用）'
            '此記錄即檢索調校素材',
        success: true,
        at: DateTime.now(),
      ));
    } catch (_) {}

    final buf = StringBuffer();
    buf.writeln('精靈遞給你的工具（依相關度排序）：');
    for (final entry in top) {
      buf.writeln('\n${entry.key.toFullDescription()}');
      buf.writeln('（媒合度 ${(entry.value * 100).toStringAsFixed(0)}%）');
    }
    buf.writeln('\n這些不夠用？換個說法再問一次，或用 tool_help 查全部工具清單。'
        '拿錯了沒關係——說出你真正要做的，精靈會記住這次教訓。');
    return AgentToolResult.success(buf.toString());
  }

  // ── 工具向量快取（首次建、終身用；工具註冊表靜態）──
  static final Map<String, List<double>> _vecCache = {};

  Future<List<double>?> _toolVecFuture(String key, String text) async {
    if (_vecCache.containsKey(key)) return _vecCache[key];
    try {
      final v = await EmbeddingService.instance.embedQuery(text);
      _vecCache[key] = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  List<double>? _toolVector(AgentTool tool) {
    // 同步版：讀快取（首次呼叫前需先 warm；見 warmup()）
    return _vecCache[tool.name];
  }

  /// 啟動時預熱——把所有工具描述嵌入向量快取（一次 ~36 次 embed，本地免費）
  Future<void> warmup() async {
    for (final tool in registry.all) {
      if (tool.name == name) continue;
      await _toolVecFuture(tool.name, '${tool.name}：${tool.description}');
    }
    debugPrint('[ToolSeek] 工具向量快取預熱完成（${_vecCache.length} 工具）');
  }


  /// [小葵 2026-09-22 Blue 令] 任務配備——精靈全項向量搜索，動態配備：
  /// 需要一把給一把，需要三把給三把，需要全副武裝就全給。
  /// 判斷標準＝相關度門檻（cosine ≥ 0.50 至少保 top1）：
  /// 不是固定數量，是「這個任務真正需要的全部」。
  /// 給 agent loop 出發前配備——不先給三把再退回來換全副武裝。
  Future<List<AgentTool>> topToolsFor(String intent,
      {double threshold = 0.50}) async {
    List<double>? queryVec;
    try {
      queryVec = await EmbeddingService.instance.embedQuery(intent);
    } catch (_) {}
    final scored = <MapEntry<AgentTool, double>>[];
    for (final tool in registry.all) {
      if (tool.name == name) continue;
      double score = 0;
      final tv = _vecCache[tool.name];
      if (queryVec != null && tv != null) {
        score = _cosine(queryVec, tv);
      } else {
        final hay = '${tool.name} ${tool.description}'.toLowerCase();
        final hits = intent.toLowerCase().split(RegExp(r'\s+'))
            .where((w) => w.length > 1)
            .where(hay.contains).length;
        score = hits.toDouble();
      }
      scored.add(MapEntry(tool, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    if (scored.isEmpty) return [];
    // 動態配備：門檻以上的全要（至少 top1——它就是最相關的）。
    // 複雜任務多工具高相關 → 自然全副武裝；簡單任務只有一兩把過門檻。
    final kit = <AgentTool>[];
    for (final e in scored) {
      if (kit.isEmpty || e.value >= threshold) {
        kit.add(e.key);
      } else {
        break;
      }
    }
    return kit;
  }

  double _cosine(List<double> a, List<double> b) {
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
}
