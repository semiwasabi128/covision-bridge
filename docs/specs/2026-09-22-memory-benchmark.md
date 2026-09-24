# 記憶系統評測 Benchmark（golden set + recall@k/MRR）

建立：2026-09-22（小葵，Blue 偷學令——supermemory 比較分析後的自建評測層）

## 為什麼存在

記憶系統此前零正式評測（評測分 3/10），改動憑感覺。此 harness 提供可重現的數字基準：
每次改檢索/寫入邏輯，跑一次對比，量化好壞。

## 怎麼跑

```bash
cd ~/Developer/bridge_app
dart run tool/memory_benchmark/run_benchmark.dart
```

- 語料寫入**臨時 DB**（`Directory.systemTemp`，跑完自動清除）——絕不碰真實 brain_container.db
- 報表輸出：終端表格 + `tool/memory_benchmark/results.json`

## 指標

- recall@1 / recall@5 / recall@10：期望記憶（expected_content_substring 命中）是否出現在前 k 名
- MRR：平均倒數排名
- 兩條路徑分開計分：`pipeline_vector`（MemoryRetrievalPipeline）與 `hybrid_fts`（HybridSearchService FTS5）

## 黃金集格式（golden_set.json）

```json
{
  "corpus": [ {"content": "...", "room": "stream", "speaker": "user", "importance": 4} ],
  "queries": [ {"query": "...", "expected_content_substring": ["..."], "note": "偏好類"} ]
}
```

加新測例：在 `queries` 加一條，`expected_content_substring` 必須是 corpus 某 content 的**精確子字串**。
涵蓋類型：偏好/事實/暫時事實（expires_at）/多人稱（小夏/阿川/小菲/Blue）/新舊版本衝突（superseded_by）/專案事實。

## 首跑基準（2026-09-22，25 queries × 32 corpus）

| 路徑 | recall@1 | recall@5 | MRR |
|---|---|---|---|
| pipeline_vector | N/A（CLI 環境 TFLite 不可用，誠實標記；需 flutter test 內測） | | |
| hybrid_fts | **0.000** | 0.000 | 0.000 |

**首跑即抓到結構性弱點**：FTS5 預設 tokenizer 不分詞中文——query 與 corpus 字面不同即零命中。
25 題全軍覆沒證實：中文記憶檢索長期只有向量一條腿，向量模型 fallback 時檢索全盲。
## 進度更新（2026-09-23）

- ✅ FTS 中文化：CJK bigram 路徑落地，recall 0.000 → **0.520**（`_searchMemoriesCjkBigram`）
- ✅ 向量路徑補測：`vector_benchmark_test.dart`（flutter test 環境載真 Gemma 300M）
  → **recall@1=0.960 / MRR=0.980**——並抓到 memories 向量 JOIN 炸彈（`m.id=TEXT` vs `v.rowid=INT` 永遠不中，production 向量檢索全盲的根因，四處全修）
- ✅ 回歸鎖死：`test/brain_container/vector_join_regression_test.dart`（行為＋靜態掃描雙保險）
- ✅ CI：`.github/workflows/memory_benchmark.yml`——回歸套件＋FTS 基準＋recall@5<0.4 劣化門檻；向量基準 CI 無模型檔自動 SKIP，本地跑 `flutter test tool/memory_benchmark/vector_benchmark_test.dart`
- 本地向量基準前置：LiteRT dylib 需放 `native/litert_lm/prebuilt/macos_arm64/`（從 `build/native_assets/macos/` 複製；gitignore 已排除）
