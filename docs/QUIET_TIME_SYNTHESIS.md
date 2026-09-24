# 安靜時刻 — 最終整合結論（下午動手前的討論稿）

> 教練 Agent 2026-08-20 10:00 — 給 使用者。
> 這是五份研究文件的交叉比對＋我自己的批判性覆核。
> **目的：下午動手前，我們先對齊這份。你看完我們討論，討論完才動手。**

---

## 一、我對「點擊錯位」驗屍報告的覆核（重要）

驗屍 subagent 把根因排在「setState 非同步延遲」（90%）。**我不同意這個排序**，理由：

1. 使用者 的症狀是「**穩定地**點 A 選到遠處 B」「有些點**怎麼點都**沒反應」——這是**可重現的結構性錯位**，不是偶發的時序 race。時序問題的症狀應該是「動畫期間偶爾不準」，不是「永遠點不到」。
2. Flutter 的 setState 雖非同步，但 pointer event 與 paint 都在相同 frame pipeline——實務上「看到的」與「點到的」差一幀（16ms）的機率極低，且 Q 彈只發生在拖曳後 450ms 內。

**我判斷的真正根因組合**（待下午實測驗證）：

| # | 根因 | 解釋 使用者 的哪個症狀 | 信心 |
|---|---|---|---|
| A | **hitTest 半徑是「世界單位」，不隨縮放補償** | 遠景（scale 0.05）時半徑+8 世界單位＝螢幕上 0.4px——**怎麼點都沒反應** | 高 |
| B | **重疊時取「陣列第一個命中」而非「螢幕上最近的」** | 密集星系裡視覺上點 A，但 z 序更早的 B 也在容差內——**選到遙遠的 B** | 高 |
| C | **hitTest 不考慮視覺半徑的動態放大**（星等 ×1.3、hover ×1.15、檔案節點 ×0.3） | 渲染半徑與點擊半徑脫鉤——視覺大點反而難點中、視覺小點容差過大 | 中 |

**修復設計（三合一，總計 ~30 行改動）**：

```dart
// canvas_node.dart — hitTest 改吃「螢幕座標 + 當前 scale」
bool hitTestScreen(Offset screenPoint, Offset screenCenter, double scale) {
  final distance = (screenPoint - screenCenter).distance;
  final hitRadius = (radius * scale * 2.5).clamp(12.0, 80.0); // 螢幕像素
  return distance <= hitRadius;
}

// infinite_canvas.dart — _hitTestNode 改「最近者勝」
CanvasNode? _hitTestNode(Offset screenPoint) {
  CanvasNode? best; double bestDist = double.infinity;
  for (final n in widget.nodes) {
    final sc = _viewport.toScreen(n.position);
    final d = (screenPoint - sc).distance;
    if (d <= hitRadiusOf(n) && d < bestDist) { best = n; bestDist = d; }
  }
  return best; // 螢幕上離滑鼠最近的，不是列表第一個
}
```

驗收標準：任意縮放（2%~800%）任一模式，點擊所見即所得；密集區點擊選最近。

---

## 二、標籤系統：資料面先決（下午動手順序的關鍵）

標籤四層制（L0 色塊/L1 標題/L2 hover/L3 側欄）的**渲染改動不難**，難在 `display_title` 從哪來。分兩步：

**第一步（無需 ingest）**：用現有資料即時推導 fallback 標題——
- 記憶節點：content 剝掉「使用者正在/目前」句式後前 12 字（現有 subCategoryLabel 邏輯可復用）
- 檔案節點：檔名剝掉副檔名與 `inspection-record-` 等機器前綴，日期轉白話（`2026-07-13_晨間拾穗.md` → 「晨間拾穗 7/13」）

**第二步（ingest 治本）**：`display_title` 欄位進 schema（見偵探式導入研究 §5），舊資料用第一步的 fallback 永遠接得住——**向後相容，不鎖死**。

## 三、線的「葉脈層」設計定稿

- 資料：同房間 top-1 嵌入相似邊（每點只連最強的 1 條 → 天然樹狀/葉脈，不回毛球）
- 視覺：0.8px 半透明、**scale ≥ 0.7 才顯示**（近景語義）
- 這層同時解決 使用者 的「點跟點之間沒有聚攏效果」＋「拉近可以看到樹狀或葉脈結構」

## 四、與七模式的對照（哪些模式直接受惠）

| 模式 | 受惠 |
|---|---|
| 0 現狀全景 | 標題去重（最大改善——不再滿屏「共振」）＋顏色圖例 |
| 1 能量流向 | 葉脈層讓流向有「河道」可循 |
| 2 選擇路口 | 點擊修好後「找門看門」才可用；門色碼已上線 |
| 3 慣性擺動 | 同上（5 顆擺錘變可點） |
| 4 跨島聯想 | 點擊修好＝驗證跨島橋兩端是誰 |
| 5 成長軌跡 | 刻度帶已上線；標題讓每個時刻是「事件」不是編號 |
| 6 資產地圖 | fallback 標題讓 641 檔案節點從機器名變人話 |

## 五、下午動手順序（定稿提案）

1. **P0 點擊三合一修復**（~30 行）→ 實測：使用者 你親自點 20 顆
2. **P0 標籤四層制＋顏色圖例去 emoji**（渲染層＋fallback 標題）
3. **P1 葉脈層**（top-1 近景線）
4. **P1 ingest 三欄位**（display_title / origin_kind / topic_cluster——新檔案走新管線，舊檔案 fallback）
5. **P2 之後**：偵探式安裝精靈、Leiden 自動聚類（Obsidian 研究建議 5）、Orphan/Hub/Bridge 視覺標記（建議 10）

---
*教練 Agent 2026-08-20 — 「研究的價值不在文件多，在下午那 30 行改對地方。」*
