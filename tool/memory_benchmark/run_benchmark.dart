// run_benchmark.dart
// bridge_app 記憶系統評測 harness — golden set + recall@k / MRR 報表
// 建立日期: 2026-09-22
//
// 用法（擇一）：
//   flutter run 概念不適用，本工具純 Dart：
//   1) dart run tool/memory_benchmark/run_benchmark.dart
//      （在 repo 根目錄；需要 flutter pub get 過的 .dart_tool）
//   2) flutter test tool/memory_benchmark/run_benchmark_test.dart 不需要——
//      本檔本身有 main()，直接 dart run。
//
// 做什麼：
//   1. 讀 tool/memory_benchmark/golden_set.json（corpus + queries）
//   2. 在系統暫存目錄開一顆臨時 BrainDatabase（絕不碰真實 DB）
//   3. 把 corpus 逐條寫入（真實 embedding；模型不可用時 fallback 零向量——
//      會誠實標記 vectorUnavailable，只測 FTS 路徑）
//   4. 逐 query 跑 MemoryRetrievalPipeline（向量）與
//      HybridSearchService（FTS5/hybrid），算 recall@1/@5/@10 + MRR
//   5. 輸出 tool/memory_benchmark/results.json + 終端表格
//
// 誠實原則：EmbeddingService 模型不可用 → isVectorUsable=false，
// 向量欄位數字直接標 N/A，不假裝有測到。

import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/services/brain_container/brain_schema_sql.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:sqlite_vector/sqlite_vector.dart';

// ═══════════════════════════════════════════════════
// Golden set 資料結構
// ═══════════════════════════════════════════════════

class GoldenCorpusEntry {
  final String content;
  final String room;
  final String speaker;
  final int importance;
  final int? expiresInDays;

  const GoldenCorpusEntry({
    required this.content,
    required this.room,
    required this.speaker,
    required this.importance,
    this.expiresInDays,
  });

  factory GoldenCorpusEntry.fromJson(Map<String, dynamic> j) =>
      GoldenCorpusEntry(
        content: j['content'] as String,
        room: j['room'] as String? ?? 'stream',
        speaker: j['speaker'] as String? ?? 'user',
        importance: j['importance'] as int? ?? 3,
        expiresInDays: j['expires_in_days'] as int?,
      );
}

class GoldenQuery {
  final String query;
  final List<String> expectedContentSubstring;
  final String note;

  const GoldenQuery({
    required this.query,
    required this.expectedContentSubstring,
    required this.note,
  });

  factory GoldenQuery.fromJson(Map<String, dynamic> j) => GoldenQuery(
        query: j['query'] as String,
        expectedContentSubstring:
            (j['expected_content_substring'] as List).cast<String>(),
        note: j['note'] as String? ?? '',
      );

  /// 排名清單中第一條含任一期望子字串的 rank（1-based；無命中=null）
  int? bestRank(List<String> rankedContents) {
    for (var i = 0; i < rankedContents.length; i++) {
      for (final sub in expectedContentSubstring) {
        if (rankedContents[i].contains(sub)) return i + 1;
      }
    }
    return null;
  }
}

class GoldenSet {
  final int version;
  final List<GoldenCorpusEntry> corpus;
  final List<GoldenQuery> queries;

  const GoldenSet({
    required this.version,
    required this.corpus,
    required this.queries,
  });

  factory GoldenSet.fromJson(Map<String, dynamic> j) => GoldenSet(
        version: j['version'] as int? ?? 1,
        corpus: (j['corpus'] as List)
            .map((e) => GoldenCorpusEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        queries: (j['queries'] as List)
            .map((e) => GoldenQuery.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static GoldenSet load(String path) {
    final raw = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    return GoldenSet.fromJson(raw);
  }
}

// ═══════════════════════════════════════════════════
// 指標
// ═══════════════════════════════════════════════════

class QueryOutcome {
  final GoldenQuery gq;
  final int? rank; // bestRank，null=未命中

  const QueryOutcome(this.gq, this.rank);

  bool get hit => rank != null;
}

class MetricSummary {
  final String name;
  final int total;
  final int recall1, recall5, recall10;
  final double mrr;

  const MetricSummary({
    required this.name,
    required this.total,
    required this.recall1,
    required this.recall5,
    required this.recall10,
    required this.mrr,
  });

  double get r1 => total == 0 ? 0 : recall1 / total;
  double get r5 => total == 0 ? 0 : recall5 / total;
  double get r10 => total == 0 ? 0 : recall10 / total;
}

MetricSummary summarize(String name, List<QueryOutcome> outcomes) {
  var c1 = 0, c5 = 0, c10 = 0;
  var rrSum = 0.0;
  for (final o in outcomes) {
    final r = o.rank;
    if (r != null) {
      rrSum += 1.0 / r;
      if (r == 1) c1++;
      if (r <= 5) c5++;
      if (r <= 10) c10++;
    }
  }
  return MetricSummary(
    name: name,
    total: outcomes.length,
    recall1: c1,
    recall5: c5,
    recall10: c10,
    mrr: outcomes.isEmpty ? 0 : rrSum / outcomes.length,
  );
}

// ═══════════════════════════════════════════════════
// 主流程
// ═══════════════════════════════════════════════════

Future<void> main(List<String> args) async {
  final repoRoot = _findRepoRoot();
  final goldenPath =
      args.isNotEmpty ? args[0] : '$repoRoot/tool/memory_benchmark/golden_set.json';
  final golden = GoldenSet.load(goldenPath);

  stdout.writeln('═' * 64);
  stdout.writeln('bridge_app 記憶系統評測 — golden set v${golden.version}');
  stdout.writeln('corpus: ${golden.corpus.length} 條 / queries: ${golden.queries.length} 條');
  stdout.writeln('═' * 64);

  // ── 1. 臨時 DB（獨立 sqlite3 連線，絕不碰真實 DB）──
  // 不走 BrainDatabase 單例：它依賴 path_provider + SharedPreferences，
  // 純 Dart 環境無法初始化。這裡用同一份 schema SQL 自建臨時庫，
  // 語意等價（建表→建索引→seed→vector_init→FTS 建表）。
  final tmpDir = await Directory.systemTemp.createTemp('bridge_mem_bench_');
  final dbPath = '${tmpDir.path}/brain_container.db';
  stdout.writeln('臨時 DB: $dbPath');

  sqlite3.sqlite3.loadSqliteVectorExtension();
  final db = sqlite3.sqlite3.open(dbPath);
  db.execute('PRAGMA foreign_keys = ON');
  for (final sql in brainCreateTableStatements) {
    db.execute(sql);
  }
  for (final sql in brainCreateIndexStatements) {
    db.execute(sql);
  }
  for (final sql in brainSeedStatements) {
    db.execute(sql);
  }
  db.execute(kVectorInitSql);
  // FTS5 external-content 建表已在 brainCreateTableStatements 內。

  // ── 2. Embedding — 誠實標記：測試環境向量不可用 ──
  //
  // EmbeddingService 依賴 flutter_gemma_embeddings（LiteRT C API via
  // dart:ffi，在 Flutter engine 內初始化），純 `dart run` 環境載入
  // 即拋例外。本 harness 不引進該依賴——所以：
  //   - corpus 的 embedding 欄位存 null（誠實，不造假零向量 BLOB）
  //   - MemoryRetrievalPipeline 的向量路徑無法執行 → 標 N/A
  //   - 只評測 FTS5 路徑（與 HybridSearchService._searchMemoriesFullText
  //     同一條 SQL）
  // 若未來接上可離線跑的 embedding（例如 ONNX CLI），把 embedCorpus
  // 換成真實實作、vectorUsable 設 true，即可同時評測向量路徑。
  const vectorUsable = false;
  stdout.writeln('向量模式: ❌ EmbeddingService（TFLite via flutter_gemma）'
      '在純 Dart CLI 環境不可用 → 只測 FTS5 路徑，向量路徑誠實標 N/A');

  // ── 3. 寫入 corpus ──
  final now = DateTime.now().millisecondsSinceEpoch;
  var memIndex = 0;
  for (final entry in golden.corpus) {
    final expiresAt = entry.expiresInDays == null
        ? null
        : now + entry.expiresInDays! * 86400000;
    db.execute(
      'INSERT INTO memories (id, content, room, sub_category, agent, companion_id, '
      'source, speaker, project, tags, importance, created_at, updated_at, expires_at, '
      'access_count, archived, chunk_index, total_chunks, embedding, vector_model_version) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'bench_${memIndex++}',
        entry.content,
        entry.room,
        'benchmark',
        '小橋',
        '',
        MemorySource.chat.dbValue,
        MemorySpeaker.fromDbOrDefault(entry.speaker).dbValue,
        '',
        '[]',
        entry.importance,
        now,
        now,
        expiresAt,
        0,
        0,
        0,
        1,
        null, // 向量欄位：測試環境無法跑 TFLite embedding，誠實存 null
        'benchmark-no-vector',
      ],
    );
  }
  // FTS5 external-content 表同步（schema 無 trigger，管線外寫入需手動補）
  db.execute(
    "INSERT INTO memories_fts(rowid, content) "
    "SELECT rowid, content FROM memories WHERE content IS NOT NULL",
  );
  final memCount = db.select('SELECT COUNT(*) c FROM memories').first['c'] as int;
  stdout.writeln('corpus 寫入完成: $memCount 條記憶（含 FTS 同步；向量欄位=null）');
  stdout.writeln('');

  // ── 4. 跑查詢 ──
  // 兩條被評測路徑：
  //   (a) MemoryRetrievalPipeline — 純向量 k-NN（vectorUsable=false 時 N/A）
  //   (b) HybridSearchService 的 memories_fts FTS5 路徑（與 hybrid 相同 SQL）

  final pipelineOutcomes = <QueryOutcome>[];
  final ftsOutcomes = <QueryOutcome>[];
  final detailRows = <Map<String, dynamic>>[];

  for (final gq in golden.queries) {
    // (a) MemoryRetrievalPipeline（向量路徑）— vectorUsable=false → 恆為 miss
    const int? pipeRank = null;

    // (b) HybridSearchService 的 memories_fts FTS5 路徑
    //     （與 _searchMemoriesFullText 完全相同的查詢——不走單例，
    //      因為 HybridSearchService 內部依賴 BrainDatabase 單例 +
    //      dart:ui debugPrint，純 Dart 環境不可用）
    final ftsRank = _ftsMemorySearch(db, gq.query, limit: 10);
    final ftsHit = gq.bestRank(ftsRank);

    pipelineOutcomes.add(QueryOutcome(gq, pipeRank));
    ftsOutcomes.add(QueryOutcome(gq, ftsHit));
    detailRows.add({
      'query': gq.query,
      'note': gq.note,
      'pipeline_rank': pipeRank,
      'fts_rank': ftsHit,
    });

    stdout.writeln(
      '[${gq.note}] ${gq.query}\n'
      '    pipeline(vector): N/A   fts: ${ftsHit?.toString() ?? "miss"}',
    );
  }

  // ── 5. 指標 + 報表 ──
  // ignore: dead_code — vectorUsable 是 const false；保留分支是為了
  // 未來打開向量路徑時（見上方 Embedding 註解）指標立即生效。
  final pipeSummary = summarize('pipeline_vector', pipelineOutcomes);
  final ftsSummary = summarize('hybrid_fts', ftsOutcomes);

  stdout.writeln('');
  stdout.writeln('═' * 64);
  stdout.writeln('結果總表');
  stdout.writeln('═' * 64);
  final header = '${'path'.padRight(18)}${'recall@1'.padRight(10)}'
      '${'recall@5'.padRight(10)}${'recall@10'.padRight(10)}MRR';
  stdout.writeln(header);
  stdout.writeln('${'pipeline_vector'.padRight(18)}'
      '${"N/A".padRight(10)}${"N/A".padRight(10)}'
      '${"N/A".padRight(10)}N/A  （向量不可用，見 vector_note）');
  stdout.writeln('${ftsSummary.name.padRight(18)}'
      '${ftsSummary.r1.toStringAsFixed(3).padRight(10)}'
      '${ftsSummary.r5.toStringAsFixed(3).padRight(10)}'
      '${ftsSummary.r10.toStringAsFixed(3).padRight(10)}'
      '${ftsSummary.mrr.toStringAsFixed(3)}');
  stdout.writeln('═' * 64);

  final misses =
      ftsOutcomes.where((o) => !o.hit).map((o) => o.gq.query).toList();
  if (misses.isNotEmpty) {
    stdout.writeln('FTS 未命中（${misses.length} 條）: ${misses.join(" / ")}');
  }

  // ── 6. 落 results.json ──
  final report = {
    'run_at': DateTime.now().toIso8601String(),
    'golden_set_version': golden.version,
    'corpus_size': golden.corpus.length,
    'query_count': golden.queries.length,
    'vector_usable': vectorUsable,
    'vector_note': 'EmbeddingService（TFLite via flutter_gemma）在純 Dart '
        'CLI 環境不可用 → MemoryRetrievalPipeline 向量路徑未測（標 N/A），'
        '只測 FTS5 路徑。corpus 的 embedding 欄位存 null（誠實不造假）。',
    'metrics': {
      // ignore: dead_code — 同上，向量路徑打開後立即生效
      'pipeline_vector': {
        'recall@1': pipeSummary.r1,
        'recall@5': pipeSummary.r5,
        'recall@10': pipeSummary.r10,
        'mrr': pipeSummary.mrr,
        'note': 'N/A — vectorUsable=false',
      },
      'hybrid_fts': {
        'recall@1': ftsSummary.r1,
        'recall@5': ftsSummary.r5,
        'recall@10': ftsSummary.r10,
        'mrr': ftsSummary.mrr,
      },
    },
    'per_query': detailRows,
  };
  final outPath = '$repoRoot/tool/memory_benchmark/results.json';
  File(outPath).writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
  );
  stdout.writeln('報表已寫入: $outPath');

  // 清理臨時 DB
  db.close();
  await tmpDir.delete(recursive: true);
  stdout.writeln('臨時 DB 已清除: ${tmpDir.path}');
}

/// 與 HybridSearchService._searchMemoriesFullText 相同的 FTS5 查詢
/// （memories_fts + bm25 排序）——抽出來是因為 HybridSearchService 單例
/// 依賴 BrainDatabase 單例 + dart:ui debugPrint，純 Dart 環境跑不動。
///
/// 回傳按 bm25 排序的 content 列表。
/// [2026-09-22 FTS 中文化] production _searchMemoriesCjkBigram 的鏡像。
List<String> _cjkBigramSearch(sqlite3.Database db, String query, int limit) {
  final cjkRuns = RegExp(r'[\u4e00-\u9fff]{2,}')
      .allMatches(query)
      .map((m) => m.group(0)!)
      .toList();
  final bigrams = <String>{};
  for (final run in cjkRuns) {
    for (int i = 0; i + 1 < run.length; i++) {
      bigrams.add(run.substring(i, i + 2));
    }
  }
  if (bigrams.isEmpty) return [];
  const stopBigrams = {
    '什麼', '怎麼', '哪個', '哪些', '現在', '時候', '喜歡', '最近',
    '每天', '早上', '可以', '沒有', '這個', '那個', '我們', '他們',
    '工作', '使用', '管理', '計劃', '時要', '偏好',
  };
  final scoring = bigrams.where((b) => !stopBigrams.contains(b)).toList();
  if (scoring.isEmpty) return [];
  final minHits = (scoring.length / 3).ceil().clamp(1, scoring.length);

  final rows = db.select(
    "SELECT id, content FROM memories "
    "WHERE archived = 0 AND chunk_index = 0 "
    "AND superseded_by IS NULL "
    "AND (expires_at IS NULL OR expires_at > ?)",
    [DateTime.now().millisecondsSinceEpoch],
  );
  final scored = <(String, int)>[];
  for (final row in rows) {
    final content = (row['content'] as String?) ?? '';
    var hits = 0;
    for (final b in scoring) {
      if (content.contains(b)) hits++;
    }
    if (hits >= minHits) scored.add((content, hits));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  return scored.take(limit).map((s) => s.$1).toList();
}

List<String> _ftsMemorySearch(sqlite3.Database db, String query,
    {int limit = 10}) {
  // [2026-09-22 FTS 中文化] 與 HybridSearchService._searchMemoriesFullText
  // 同步：CJK 查詢走 bigram 計分路徑（FTS5 unicode61 不分詞中文）。
  final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(query);
  if (hasCjk) {
    final bigramHits = _cjkBigramSearch(db, query, limit);
    if (bigramHits.isNotEmpty) return bigramHits;
  }
  final ftsQuery = '"$query"';
  try {
    final rows = db.select(
      "SELECT m.content, bm25(memories_fts) AS rank "
      "FROM memories_fts "
      "JOIN memories m ON m.rowid = memories_fts.rowid "
      "WHERE m.archived = 0 AND memories_fts MATCH ? "
      "ORDER BY rank "
      "LIMIT ?",
      [ftsQuery, limit],
    );
    return rows.map((r) => r['content'] as String).toList();
  } catch (_) {
    return []; // FTS5 查詢語法不支援（例如純標點）→ 視為未命中
  }
}

/// 從當前工作目錄往上找 pubspec.yaml 定位 repo 根目錄。
String _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('找不到 repo 根目錄（pubspec.yaml）');
    }
    dir = parent;
  }
}
