# 夥伴 Rig 素材生成規格 v1.1

> [小葵 2026-09-12] Blue 拍板兩條鐵則：
> ① 暗碼不能渲染出來——角色圖上不可見任何標記
> ② 生圖規則統一化：未來鍊成的每個夥伴（任何形象）都自動貼合動態系統

## 核心設計：雙檔暗碼（Sidecar Rig Map）

**角色主圖永遠乾淨**——暗碼不是主圖上的像素，是**配套的第二張檔案**。

```
companion_x/
  body_full.png   ← 乾淨角色圖（使用者看到的）
  rig_map.png     ← 暗碼圖（系統用的，絕不顯示給使用者）
```

### rig_map 暗碼圖格式
與主圖同尺寸的稀疏標註圖（黑底）：
- 每個樞紐點一個 5px 色點＋色環：
  - 紅 `(255,0,0)` = 頸根樞紐（頭 pivot）
  - 綠 `(0,255,0)` = 右肩樞紐
  - 藍 `(0,0,255)` = 左肩樞紐
  - 黃 `(255,255,0)` = 髮頂（head bbox 上界）
  - 洋紅 `(255,0,255)` = 腕部（arm bbox 下界）
- CV 讀取：掃色點 → 座標即 pivot/bbox，零模糊

### 暗碼怎麼產生（管線，全自動）
1. **生圖**（規則保證可辨識性，但不產生任何可見標記）：
   - 全身：A-pose、手臂與身體有縫隙、頭髮不垂肩胸、腳下留白、置中
   - 胸像：頭頂留白、下巴到腰
2. **VLM 定位**（GLM-4.6V，bbox×1000）：問「頸根/左右肩/髮頂/左右腕的座標」
   —— 姿勢規則讓 VLM 回答穩定可靠（縫隙=肩點明確、髮不垂=頸點明確）
3. **暗碼寫入**：系統把座標畫成 rig_map.png 落盤（這步是純程式，永不失誤）
4. **切片執行**：rig_map 座標 → bbox → 切 head/arm_L/arm_R
5. **資格驗證**（必過）：合成無損 diff<1.5、連通元件分離、±0.25rad 鬼影測試
6. **rig 註冊**：RigGeometry 自動生成，factor 依驗證結果自動 1.0/0.0

> 關鍵洞察：**「生圖時埋暗碼」的真正含義是埋「可辨識性」**——姿勢規則
> （縫隙/髮不垂肩/置中留白）讓任意形象（章魚/長頸鹿/怪獸）的樞紐都能被
> VLM 穩定定位。暗碼資訊本身由系統在定位後寫入 sidecar，主圖永遠乾淨。

## 提示詞模板（寫進系統的生成規則）

### 全身（fullBody）
```
[造型描述], full body, standing, feet visible with margin below,
arms slightly apart from torso with clear gap,
hair styled up, not touching shoulders or chest,
centered, entire figure head to toe visible, plain background
```

### 胸像（bust）
```
[造型描述], bust portrait framing chin to waist,
entire head visible with headroom above hair,
centered, plain background
```

（注意：模板裡**沒有任何標記物**——choker/armlet 已撤回）

## 構圖模式
| 模式 | layout |
|------|--------|
| fullBody | 等比 fit、置中、全身含腳 |
| bust | 寬度填滿、頂部對齊−5% 邊距 |

## 驗收清單
- [ ] 主圖無任何可見標記（暗碼隱形鐵則）
- [ ] VLM 定位五樞紐穩定（重問 3 次座標差 < 2%）
- [ ] rig_map 落盤且色點正確
- [ ] 分離驗證＋鬼影測試通過
- [ ] 懸浮窗實機零破圖

## 教訓（MimeMi v1）
- 切片只切 2/3 頭 → 鬼影；髮垂肩=相連 → 不可旋轉
- 可見暗碼（項圈臂環）= 污染造型，Blue 否決 → sidecar 方案


## v1.2 三帶呼吸 sidecar（2026-09-13，Blue 拍板三層分帶）

### 檔案約定（每張立繪一份，同目錄同名）
- `<image>_rigmap.json` — 呼吸地籍（錨點＋三帶＋振幅，座標相對 0-1）
- `<image>_band0.png` — 胸腰帶（amp 1.0）
- `<image>_band1.png` — 腿帶（amp 0.4）
- `<image>_band2.png` — 小腿腳帶（amp 0.1）
- 每帶上下端 18px alpha 羽化；與主圖同源裁切（絕不重新生成）

### rigmap.json schema
```json
{
  "version": 1,
  "anchor": {"x": 0.5, "y": 0.29, "note": "站姿"},
  "bands": [
    {"from": 0.23, "to": 0.52, "amp": 1.0, "note": "胸腰"},
    {"from": 0.52, "to": 0.79, "amp": 0.4, "note": "腿"},
    {"from": 0.79, "to": 1.0, "amp": 0.1, "note": "小腿腳"}
  ],
  "breath": {"period_s": 2.8, "amp": 0.018, "style": "smooth"}
}
```

### 生成規則（未來煉成夥伴管線適用）
1. 錨點=該生物的「呼吸器官中心」：人形→胸口；章魚→外套膜；魚→鰓蓋；龍獸→胸腔；
   幽靈史萊姆→核心光球。由生成形象的 LLM 在出圖時順帶輸出 rigmap（語意決策，非視覺反推）。
2. 帶邊界以錨點為基準：band0 = anchor-0.06 → anchor+0.23；band1 → +0.50；band2 → 圖底 1.0。
   特殊構圖（坐姿/跪姿/跳躍）錨點下移，帶跟著平移。
3. 檢驗清單：錨點必須在 band0 內部且離帶緣 ≥0.04；不合格退回重出 rigmap（圖不重生成）。
4. 主圖零暗碼不變；rigmap/bands 全走 sidecar，缺檔自動 fallback（torso 單帶→整圖微縮），永不壞畫。
5. 已套用：小橋 9 張、MimeMi 9 張（含 avatar 與狀態圖組）全數生成 rigmap+三帶。


### v2 多圓心矩形帶（2026-09-13 進階版，Blue 拍板）

v1 限制：橫帶（全寬）＋共用胸口錨點。v2 通用化：**每帶任意矩形 rect{x,y,w,h}＋獨立圓心 center{x,y}**。

```json
{"version": 2,
 "bands": [
   {"rect": {"x":0.06,"y":0.02,"w":0.30,"h":0.30}, "center": {"x":0.22,"y":0.08}, "amp": 1.0, "note": "燈泡手指"},
   {"rect": {"x":0.30,"y":0.20,"w":0.40,"h":0.42}, "center": {"x":0.48,"y":0.34}, "amp": 0.4,  "note": "胸口"},
   {"rect": {"x":0.30,"y":0.70,"w":0.35,"h":0.28}, "center": {"x":0.45,"y":0.86}, "amp": 0.1,  "note": "小腿"}]}
```

- 應用①（多錨點）：橋接狀態=雙手各一圓心 amp 1.0（雙手同時脈動）
- 應用②（三帶各異圓心）：idea 狀態=燈泡 1.0／胸口 0.4／小腿 0.1 各自輻射
- runtime v1/v2 自動判讀（帶含 rect/center=v2；否則橫帶 v1）
- 檢驗不變：圓心必須在帶內且距緣 ≥0.04；四邊 16px 羽化
