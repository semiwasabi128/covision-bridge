# Phase F Sprint Plan — 共視功能化

> **狀態**：✅ **已收尾（2026-09-13）**——見 [PHASE_G_TIMELINE.md](PHASE_G_TIMELINE.md) § 1 交接說明
> **收尾判定**：共視宣言未死，已走進 9 月三大主軸實作（時間感/因果/Agent 平台）。F-1 指標由 COVISION_METRIC_DESIGN.md 的機制設計取代；F-2 素材池節點被 Vault 知識節點+向量資料庫 v2 超越；F-3 BridgePack 留待社群階段。
> **指示者**：Blue（2026-08-09：「排進下週開發」→ F-1 選擇「先深化設計理念再動手」）
> **上游**：[共視宣言](COVISION_MANIFESTO.md) · [核心發想規格](BRIDGE_CORE_IDEAS_PHASE_F.md)
> **期間**：2026-08-10（週一）→ 2026-08-16（週日）

---

## Sprint 目標

把共視從「定位宣言」變成「畫面上看得到的東西」。

---

## v2.0 重大變更（使用者 2026-08-09 決策）

**F-1 共視時長指標從「先做 code」改為「先深化設計」。**

使用者 的判斷：共視時長如果只做到「人跟 Agent 都在 canvas 上 = 計時」，那它跟 session length 的差別會很薄。vanity metric 做出來比不做更危險。

**v2.0 Sprint 重排**：
- F-1 code 暫緩 → 改為設計理念深化（產出定義文件，不定 code）
- F-2 發想素材池節點提前 → 從週四提前到週一，成為本 sprint 主線
- F-3 BridgePack → 順移到週四～週日

---

## 現有技術地基（已驗證存在）

| 模組 | 路徑 | 狀態 | Phase F 用途 |
|---|---|---|---|
| V2 Canvas State | `lib/widgets/canvas/v2/canvas_state.dart` | ✅ 不可變 state + controller | F-2 的狀態層 |
| Canvas SubWorkflow Runner | `lib/services/semicanvas/canvas_sub_workflow_runner.dart` | ✅ DAG 執行 (383 行) | F-2 素材池節點的執行引擎 |
| Native Agent Loop | `lib/services/native_agent_loop.dart` | ✅ 890 行，事件驅動 + idle timer | F-1 設計參考（Agent 注意力來源） |
| Agent Event Bus | `lib/services/agent_loop/agent_event_bus.dart` | ✅ | F-1 設計參考（事件流） |
| Canvas Node Model | `lib/models/canvas/canvas_node.dart` | ✅ Memory wrapper | F-2 新節點類型擴展點 |
| Brain Canvas graphMode | `lib/widgets/canvas/brain_canvas.dart` | ✅ mode 0-6 | F-2 可能需 mode 7+ |
| Canvas Snapshot Service | `lib/services/vault/canvas_snapshot_service.dart` | ✅ JSON 序列化 | F-3 `.bridgepack` 匯出基礎 |

---

## Sprint 順序（v2.0）

### F-0：共視／共識機制設計（週一，設計不寫 code）

**使用者 決策（2026-08-09）**：指標是表面工程。先做出真正的共視／共識機制，指標是過程中自然掉出來的信號。

**設計軸心**：共視 → 共識 → 互補加速 → 指標是副產物

**產出**：`docs/COVISION_METRIC_DESIGN.md`

4 個產品機制：
1. **AI 注意力光暈** — Agent 正在處理的節點上方有微妙光暈，讓人知道「AI 在看這裡」
2. **人意圖信號** — 人在畫布上的停留/選取/標記變成對 Agent 的意圖信號（雙向 Event Bus）
3. **共識往返** — AI 以「幽靈節點」提議 → 人接受/修改/拒絕 → AI 執行（不是 ConfirmDialog，是「我覺得可以這樣，你覺得呢？」）
4. **共視產物標記** — 經過共識往返的節點標記 `coCreated: true`

指標是機制運作的日誌，不需要額外 tracker。

**驗收**：
- [ ] 使用者 簽核 4 個機制的定義 = 「真正的共視」
- [ ] 使用者 確認「共視→共識→互補→加速」的鏈條正確
- [ ] 隱私邊界明確列出（不追蹤 cursor 軌跡、不上傳注意力資料）

---

### F-1：發想素材池節點化 + 共識往返首版（週二～週四）

**為什麼是主線**：素材池節點是第一個能實際展示「共識往返」（機制 3）的功能。AI 產出候選發想（提議）→ 人接受/修改/拒絕（回應）→ 被採用的標記 `coCreated: true`。這是共視宣言 Layer 3「共同建造」的第一個可運作實例。

#### Day 4（週四）：IdeaPoolNode Model + Widget

**新建檔案**：
- `lib/models/canvas/idea_pool_node.dart` — 素材池節點資料模型
- `lib/widgets/canvas/v2/nodes/idea_pool_node_widget.dart` — 節點渲染

設計：
- 節點有 1 個 input port（種子主題）、1 個 output port（發想卡片陣列）
- 內部循環：載入素材池 → LLM 排序 → 產出 3 條候選
- 每條候選可被拖出成為獨立 CanvasNode
- 標記「採用」「跳過」「改寫」→ 回饋排序權重

素材池來源：
- 初期從 `docs/CEO/橋樑發想素材池.md` 讀取（如果存在）
- 或從 `BridgeDatabase` 的 memories 查詢 `tag: idea` 的條目
- 格式：JSON array of { id, title, description, tags, status }

#### Day 5（週五）：SubWorkflow 整合 + 測試

整合到現有 `CanvasSubWorkflowRunner`：
- 新增範本 `idea_pool`（在 `VaultTemplateService` 註冊）
- 連接 SubWorkflow Runner → 執行素材池循環 → 回傳發想卡片

**驗收**：
- [ ] 素材池節點出現在節點選擇器
- [ ] 連接種子主題後 Agent 產出候選發想
- [ ] 發想可被拖出成為獨立節點
- [ ] 標記回饋有被記錄
- [ ] `flutter analyze` 零錯誤

---

### F-2：走你的橋（週五～週日，可能延後）

**風險提示**：F-2 的完整版需要社群 Registry（Phase 2），本 sprint 只做 F-2a。

#### Day 5-7（週五～週日）：F-2a — BridgePack 匯出/匯入

**新建檔案**：
- `lib/services/bridgepack/bridgepack_exporter.dart` — 畫布 → `.bridgepack`
- `lib/services/bridgepack/bridgepack_importer.dart` — `.bridgepack` → 唯讀畫布

`.bridgepack` 格式草案：
```json
{
  "format": "bridgepack",
  "version": "0.1",
  "exported_at": "2026-08-15T...",
  "canvas_snapshot": { /* CanvasSnapshot JSON，已 sanitized */ },
  "metadata": {
    "title": "...",
    "author": "optional",
    "description": "optional"
  }
}
```

Sanitization 規則（安全第一）：
- 移除所有 API key、OAuth token、使用者個人記憶
- 移除 Memory 的 content（只保留 type + tags + summary）
- 保留節點結構、連線、Agent 軌跡

**驗收**：
- [ ] 畫布可匯出 `.bridgepack`
- [ ] `.bridgepack` 不含敏感資料（grep `key|token|password` 結果為空）
- [ ] 唯讀共視模式可瀏覽節點連線
- [ ] Fork 後的新版本可編輯

---

## 風險與依賴

| 風險 | 影響 | 緩解 |
|---|---|---|
| 使用者 指定的 8/10 三問題（圖片生成失敗、儀表板不準、provider 標示失真）可能需要優先處理 | F-1 可能延後 | 如果 使用者 指示先修三問題，Phase F 整體順延一天 |
| F-1 需要素材池資料來源 | 素材池節點可能空轉 | 先用 memories 查詢兜底，不依賴外部檔案 |
| F-2 唯讀模式需要 canvas controller 改造 | 工時可能超估 | 如果 Day 5 進度不足，F-2 移到下下週 |
| macOS sandbox 擋 debugPrint | 測試需靠 MCP 端點 | 沿用教練模式 curl 驗證法 |

---

## 每日驗收節奏

| 日 | 交付物 | 驗收方式 |
|---|---|---|
| 週一 | `COVISION_METRIC_DESIGN.md` 指標定義文件 | 使用者 讀過確認不是 vanity metric |
| 週二 | IdeaPoolNode model + widget | 節點出現在選擇器 |
| 週三 | SubWorkflow 整合（種子→排序→候選） | Agent 產出候選發想 |
| 週四 | 發想拖出 + 標記回饋 | 發想可被拖出成獨立節點 |
| 週五 | `.bridgepack` exporter | 匯出檔案 + sanitized 驗證 |
| 週六 | `.bridgepack` importer + 唯讀模式 | Fork 後可編輯 |
| 週日 | 緩衝 / 收尾 | `flutter analyze` 零錯誤 |

---

## 與 使用者 8/10 三問題的關係

使用者 在 8/9 指定的 8/10 待解三問題（圖片生成失敗、儀表板不準、provider 標示失真）優先級**高於** Phase F。

**建議**：
- 週一上午先處理三問題
- 週一下午開始 Phase F
- 如果三問題需要超過 1 天，Phase F 整體順延，不犧牲品質

---

> 共視不是功能，是橋樑的品牌動詞。這個 Sprint 讓它從文件走進畫面。
