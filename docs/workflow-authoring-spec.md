# 工作流編排規範

> 從 8 張理想與現況截圖比對歸納出的編排原則。目標：排出的工作流像截圖 2/4/6/8 一樣整齊、清晰、無重疊、無連線交叉。

## 核心原則

### 1. 視覺流向 = 資料流向：嚴格左到右
- 所有節點一律從左到右排列
- x 座標必須隨資料流遞增，不可回頭
- 同一「階段」（column）的節點 x 座標相同

### 2. 分支對稱展開，不合併的分支不交會
- 分支時：主線在 y=400，上分支 y=100，下分支 y=700
- **上分支的連線往下彎**（從 y=100 彎向 y=400 的合併點）
- **下分支的連線往上彎**（從 y=700 彎向 y=400 的合併點）
- 兩條分支連線在合併點交會，但**不交叉**：上分支走上方，下分支走下方

### 3. 分支後的節點要錯開 x 座標
- **這是最關鍵的規則**：分支後的節點如果 x 座標相同，LLM 等大節點會疊在一起
- 分支後每一級的 x 座標必須錯開（遞增 500px）
- 範例：condition(x=1100) → imageGen(x=1600) → tts(x=2100)，不能 condition(x=1100) → imageGen(x=1100)

### 4. 合併點放在分支節點的右側中央
- merge 節點的 y 座標 = (上分支 y + 下分支 y) / 2
- merge 節點的 x 座標 = 最後一個分支節點的 x + 500
- 確保合併連線不穿過其他節點

### 5. 大節點（LLM）獨立一列
- LLM 節點視覺寬度約 280px，高度約 200px
- LLM 節點的前後 x 間距至少 500px
- 不要把其他節點放在 LLM 的正上方或正下方（會被遮擋）

### 6. 階層式佈局（Layered Layout）
- 每個「階層」是一個 x 座標 column
- 同一 column 的節點垂直排列
- 相鄰 column 之間 x 差 = 500px
- 範例 column 結構：
  ```
  Col1(x=100)  Col2(x=600)  Col3(x=1100)  Col4(x=1600)  Col5(x=2100)
  input        tool(上)     merge         llm           output
               tool(下)
  ```

## 四種範本的理想佈局

### 範本 1：角色扮演 IG（直線 4 節點）
```
input(100,400) → llm(600,400) → imageGen(1100,400) → output(1600,400)
```
直線，無分支，無合併。所有節點同一 y 值。

### 範本 2：晨間情報站（分支→合併→直線 6 節點）
```
                    tool(600,100)  ──→  merge.a
input(100,400)  ──→                    merge(1100,400) → llm(1600,400) → output(2100,400)
                    tool(600,700)  ──→  merge.b
```
input 分叉到兩個 tool（上下對稱），合併後直線到 llm 和 output。

### 範本 3：短影音製作所（分支→平行處理→合併 9 節點）
```
                                     imageGen(1600,100)  →  tts(2100,100)   ──→  merge.a
input(100,400) → llm(600,400) → condition(1100,400)                                           merge(2600,400) → output(3100,400)
                                     videoGen(1600,700)  →  musicGen(2100,700) ──→ merge.b
```
condition 分支後，上下各兩個節點（x 遞增），最後合併。**分支後的節點 x 必須錯開！**

### 範本 4：多重宇宙簡報（三分支→cascade合併→LLM→condition→merge 11 節點）
```
                                  subA(600,100)  ──→  merge1.a(1100,250)
input(100,400) →                                                              merge1(1100,250) → merge2.a(1100,550) → llm(1600,400) → condition(2100,400) → merge.a(2600,400) → output(3100,400)
                                  subB(600,400)  ──→  merge1.b(1100,250)                                              condition.false(2100,400) → llm2(2600,100) → merge.b(2600,400)
                                  subC(600,700)  ──→  merge2.b(1100,550)
```
- 三條子工作流垂直排列（y=100/400/700）
- cascade merge（merge1 合併 A+B，merge2 合併 merge1+C）
- condition true → merge.a（直通）
- condition false → llm2（往上）→ merge.b（往下彎）
- merge → output

## 座標計算公式

| 項目 | 公式 |
|------|------|
| 水平間距 | `350px` |
| 垂直主線 | `y = 400` |
| 上分支 y | `y = 200`（主線 - 200） |
| 下分支 y | `y = 600`（主線 + 200） |
| 第 n column 的 x | `x = 100 + (n-1) * 350` |
| merge 的 y | `(上分支 y + 下分支 y) / 2` |

## Port 對照表

| 節點類型 | Input Ports | Output Ports | 視覺寬度 |
|---------|-------------|-------------|---------|
| input | — | output | ~180px |
| llm | input | output | ~280px |
| tool | input | output | ~200px |
| imageGen | prompt | output | ~240px |
| videoGen | prompt | output | ~240px |
| musicGen | prompt | output | ~240px |
| tts | text | output | ~200px |
| condition | input | true, false | ~200px |
| merge | a, b | output | ~180px |
| output | input | — | ~180px |
| subWorkflow | trigger | output | ~220px |

## Merge 規則

- 每個 merge 最多 2 個 input（`a` 和 `b`）
- output/llm/condition/tool 節點只有一個 input port — 多來源必須先用 merge 合併
- N 個來源需要 N-1 個 merge（cascade）

## Condition 分支規則

- condition 輸出 port 是 `true` 和 `false`，不是 `output`
- true 和 false 分支如果最終都流向同一個節點，必須用 merge 合併（不能兩條線連到同一個 input port）
- true 分支通常走上路，false 分支通常走下路
