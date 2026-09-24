// companion_rig.dart
// [小葵 2026-09-11] 夥伴活體 rig 註冊表——每個夥伴一份「素材幾何」，
// 動畫參數表（kRigParamsByState）全夥伴共用（狀態=參數，與角色無關）。
// [小葵 2026-09-12] Blue 令：幅度加大到肉眼明顯可見（約原本 2~2.5 倍）。

class RigGeometry {
  final String assetBase;
  final double fullW;
  final double fullH;
  // bbox 與 pivot（原圖座標）
  final List<double> headBox; // x1,y1,x2,y2
  final List<double> headPivot; // x,y
  final List<double> armRBox;
  final List<double> armRPivot;
  final List<double> armLBox;
  final List<double> armLPivot;

  const RigGeometry({
    required this.assetBase,
    required this.fullW,
    required this.fullH,
    required this.headBox,
    required this.headPivot,
    required this.armRBox,
    required this.armRPivot,
    required this.armLBox,
    required this.armLPivot,
  });
}

/// 目前有 rig 素材的夥伴——之後新夥伴只要：切層 png 進 assets + 這裡加一筆
const Map<String, RigGeometry> kRigByCompanion = {
  '小橋': RigGeometry(
    assetBase: 'assets/companions/xiaoqiao',
    fullW: 561,
    fullH: 914,
    headBox: [233, 0, 427, 212],
    headPivot: [321, 200],
    armRBox: [203, 183, 352, 372],
    armRPivot: [285, 215],
    armLBox: [313, 223, 482, 432],
    armLPivot: [348, 250],
  ),
  'MimeMi': RigGeometry(
    assetBase: 'assets/companions/mimemi',
    // [小葵 2026-09-12] v3 全身重製（MiniMax 圖生圖＋自動切片管線）
    fullW: 864,
    fullH: 1152,
    headBox: [285, 0, 579, 278],
    headPivot: [371, 264],
    armRBox: [552, 275, 660, 767],
    armRPivot: [518, 299],
    armLBox: [212, 264, 302, 744],
    armLPivot: [319, 288],
  ),
};
