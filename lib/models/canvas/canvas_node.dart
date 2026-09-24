// canvas_node.dart
// 畫布節點 — 包裝 Memory + 位置 + 衍生視覺屬性
// Sprint 18-2

import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:flutter/material.dart';

/// 畫布上的一個節點，對應一則 [Memory]。
///
/// 包含世界座標位置與衍生視覺屬性（配色、大小、標籤）。
/// 位置由 force layout 或拖曳產生，不由 Memory 自帶。
class CanvasNode {
  /// 對應的 Memory ID
  final String id;

  /// 世界座標位置
  final Offset position;

  /// 節點大小（直徑，世界座標）
  final double size;

  /// 底層記憶
  final Memory memory;

  /// 是否被拖曳中（由 widget state 管理，此欄位用於 render 判斷）
  final bool isDragging;

  /// 是否被選中
  final bool isSelected;

  /// [教練 Agent 2026-07-28] 是否為檔案節點（來自 asset_index，非記憶）
  /// 檔案節點用淡色光點渲染，區別於記憶節點的亮色
  final bool isFileNode;

  /// [教練 Agent 2026-08-19] 檔案節點的絕對路徑（雙擊開檔用）；非檔案節點為 null
  final String? filePath;

  // [教練 Agent 2026-08-20] P1 合集節點（使用者 點菜）：重複性高的檔案
  // （巡查紀錄系列、鹿角蕨照片群…）聚合為一個大點；點開 detail
  // panel 看成員清單。Agent 吃細粒度（asset_index 原樣不動），
  // 使用者看合集——視覺層聚合，DB 不動。
  /// 合集成員（此節點為合集節點時非空）：asset id → 檠名
  final Map<String, String> collectionMembers;

  /// 是否為合集節點
  bool get isCollection => collectionMembers.isNotEmpty;

  /// 合集成員數
  int get memberCount => collectionMembers.length;

  /// [教練 Agent 2026-08-20] 掃描根目錄（asset_index.folder_root）——絕對路徑拼接用
  final String? folderRoot;

  /// [教練 Agent 2026-08-20] 絕對路徑（folder_root + file_path，處理缺斜線拼接）。
  /// DB 的 folder_root 有的帶尾斜線有的不帶（農場資料庫就不帶→拼接全錯）。
  String? get absoluteFilePath {
    final raw = filePath;
    if (raw == null) return null;
    if (raw.startsWith('/')) return raw; // 已是絕對路徑
    final root = folderRoot;
    if (root == null || root.isEmpty) return raw;
    if (root.endsWith('/')) return '$root$raw';
    return '$root/$raw';
  }

  CanvasNode({
    required this.id,
    required this.position,
    required this.memory,
    this.size = 48.0,
    this.isDragging = false,
    this.isSelected = false,
    this.isFileNode = false,
    this.filePath,
    this.folderRoot,
    this.collectionMembers = const {},
  });

  /// 從 Memory 建構節點（初始位置在原點，需後續 layout 計算）
  ///
  /// [isFileNode] — true 表示此節點來自 asset_index（檔案），用淡色渲染
  factory CanvasNode.fromMemory(Memory memory,
      {Offset? position, bool isFileNode = false, String? filePath,
      String? folderRoot}) {
    return CanvasNode(
      id: memory.id,
      position: position ?? Offset.zero,
      memory: memory,
      size: _sizeForImportance(memory.importance),
      isFileNode: isFileNode,
      filePath: filePath,
      folderRoot: folderRoot,
    );
  }

  /// importance 1-5 → 節點直徑 32~72
  static double _sizeForImportance(int importance) {
    switch (importance.clamp(1, 5)) {
      case 1:
        return 32.0;
      case 2:
        return 40.0;
      case 3:
        return 48.0;
      case 4:
        return 58.0;
      case 5:
        return 72.0;
      default:
        return 48.0;
    }
  }

  // ── 衍生視覺屬性 ──

  /// 房間對應的配色
  Color get color => isFileNode ? roomColor(memory.room).withValues(alpha: 0.4) : roomColor(memory.room);

  /// [教練 Agent 2026-07-28] 檔案節點的淡色填充（比記憶節點更暗）
  Color get fileFillColor => roomColor(memory.room).withValues(alpha: 0.08);

  /// 房間對應的配色（靜態，供外部使用）
  static Color roomColor(BrainRoom room) {
    switch (room) {
      case BrainRoom.stream:
        return const Color(0xFF4FC3F7); // 淺藍
      case BrainRoom.doors:
        return const Color(0xFFFFB74D); // 橙
      case BrainRoom.pendulums:
        return const Color(0xFFEF5350); // 紅
      case BrainRoom.heartMind:
        return const Color(0xFFEC407A); // 粉紅
      case BrainRoom.fraile:
        return const Color(0xFFCE93D8); // 紫
      case BrainRoom.bridges:
        return const Color(0xFF66BB6A); // 綠
    }
  }

  /// 房間對應的深色背景（節點內部填充用）
  static Color roomColorDark(BrainRoom room) {
    return roomColor(room).withValues(alpha: 0.15);
  }

  /// [教練 Agent 2026-08-19] 標籤文字 — 三層文字制第一層：
  /// 平時只顯示 sub_category 短分類（如「順暢流動」「門已進入」），
  /// 不再顯示 content 開頭（agent 句式固定，開頭都一樣＝視覺噪音）。
  /// hover → 標題（title）；點擊 → 完整內容（detail panel）。
  String get label {
    // [教練 Agent 2026-08-20] 標籤四層制（使用者：sub_category 用顏色表達、
    // 節點上的字＝它的標題）——L1 常態顯示「內容標題」：
    // 檔案節點→displayTitle（人話檔名）；記憶節點→title（剝句式後
    // 的 content 摘要）。sub_category 不再以文字出現（顏色＋圖例承擔）。
    // [教練 Agent 2026-08-20] P1 合集：標籤＝系列名 × 成員數
    if (isCollection) return '$displayTitle ×$memberCount';
    if (isFileNode) return displayTitle;
    // [教練 Agent 2026-08-22 使用者 共視抓包#3] 記憶節點平常不掛環境標籤。
    // content 前幾個字不是標題——掛在節點上方＝視覺噪音，還會跟
    // hover 文字卡疊字。平常只顯示真標題（檔案 displayTitle），
    // 記憶節點 hover 卡看資訊即可（Obsidian Graph 同款行為）。
    return '';
  }

  // [教練 Agent 2026-08-20] 檔案節點人話標題（fallback 推導，ingest 治本前的
  // 過渡）：剝機器前綴（inspection-record- 等）與副檔名、日期轉白話。
  /// 檔案節點的人類可讀標題（L1 層顯示用）
  String get displayTitle {
    if (!isFileNode) return title;
    var name = memory.content.trim();
    // 副檔名
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    // [教練 Agent 2026-08-22 使用者 共視抓包#2] 通用淨化——
    // ① 剝時間戳尾巴（_1786125863332 這種毫秒戳不是信息是噪音）
    name = name.replaceAll(RegExp(r'[_\-]?\d{10,}$'), '');
    // ② 剝 prompt 模板前綴（「請根據以下資料_整理一份專業的_」
    //    這類 agent 生成檔的固定句式＝視覺噪音；字典式通用，全部節點生效）
    for (final boiler in [
      '請根據以下資料_整理一份專業的_',
      '請根據以下資料，',
      '請根據以下資料_',
      '請根據以下資料',
      '整理一份專業的_',
      '整理一份專業的',
      '請幫我_',
    ]) {
      if (name.startsWith(boiler)) {
        name = name.substring(boiler.length);
        break;
      }
    }
    name = name.trim();
    // ③ 限長：節點標題是「名字」不是「句子」——16 字封頂
    if (name.length > 16) name = '${name.substring(0, 15)}…';
    // 機器前綴
    for (final prefix in [
      'inspection-record-',
      'bridge_image_',
      'canvas-workflow-',
      'pack_',
    ]) {
      if (name.startsWith(prefix)) {
        name = name.substring(prefix.length);
        // 剩下的時間戳截短
        if (name.length >= 8 && RegExp(r'^\d{8,}').hasMatch(name)) {
          name = '紀錄 ${name.substring(0, 8)}';
        }
        break;
      }
    }
    // 日期前綴白話化：2026-07-13_晨間拾穗 → 晨間拾穗 7/13
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[_-](.+)\$').firstMatch(name);
    if (m != null) {
      name = '${m.group(5)} ${m.group(2)}/${m.group(3)}';
    }
    if (name.isEmpty) return '未命名';
    if (name.length <= 14) return name;
    return '${name.substring(0, 13)}…';
  }

  /// hover 標題 — content 前 20 字（去掉「使用者」開頭的固定句式）
  String get title {
    var text = memory.content.trim();
    // 去掉 agent 固定句式開頭
    for (final prefix in ['使用者正在', '使用者目前', '使用者要求',
        '使用者（或使用者方農場）正在', '使用者（或使用者所在農場）正在',
        '使用者已', '使用者需要', '使用者故意', '使用者設定', '使用者使用',
        '使用者期望', '使用者進行', '使用者']) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
        break;
      }
    }
    text = text.trim();
    if (text.length <= 20) return text;
    return '${text.substring(0, 18)}…';
  }

  /// 房間圖示 emoji
  String get icon => memory.room.icon;

  /// 來源夥伴的顯示名稱（用於畫布 tooltip / detail panel）
  String get companionLabel {
    final cid = memory.companionId;
    if (cid.isEmpty) return '';
    return memory.agent;
  }

  /// 來源夥伴的色碼（用於畫布節點邊框標記 provenance）
  /// 同一個夥伴永遠拿到同一個顏色
  Color get companionBorderColor {
    final cid = memory.companionId;
    if (cid.isEmpty) return Colors.transparent;
    return companionColor(cid);
  }

  /// 根據 companion ID 產生穩定的色碼（跨 Agent 共享大腦 provenance）
  static Color companionColor(String companionId) {
    if (companionId.isEmpty) return Colors.transparent;
    // 從 ID 字串 hash → 色相
    var hash = 0;
    for (final c in companionId.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.65, 0.55).toColor();
  }

  /// 節點半徑
  double get radius => size / 2;

  /// 點擊測試：世界座標 [point] 是否在節點範圍內
  bool hitTest(Offset point) {
    final distance = (point - position).distance;
    // [教練 Agent 2026-08-19] +8 世界單位 padding——粒子核心比視覺半徑小，
    // 用核心點 hit 會「看得到點不到」（使用者 6 號回報）
    return distance <= radius + 8;
  }

  // [教練 Agent 2026-08-20] P0 點擊錯位修復①——螢幕座標 hitTest：
  // 舊版用「世界單位半徑」，遠景縮放（scale 5%）時 +8 世界單位
  // 在螢幕上不到 1px →「怎麼點都沒反應」；世界↔螢幕換算一率走
  // 呼叫端傳入的 scale，半徑以螢幕像素計：max(視覺×2.5, 12px)。
  /// 螢幕座標點擊測試：[screenPoint] 與 [screenCenter] 皆為螢幕像素，
  /// [scale] 為當前 viewport 縮放。
  bool hitTestScreen(
      Offset screenPoint, Offset screenCenter, double scale) {
    final distance = (screenPoint - screenCenter).distance;
    final visualRadiusPx = radius * scale;
    final hitRadiusPx =
        (visualRadiusPx * 2.5).clamp(12.0, 80.0); // 螢幕像素下限 12px
    return distance <= hitRadiusPx;
  }

  CanvasNode copyWith({
    Offset? position,
    double? size,
    Memory? memory,
    bool? isDragging,
    bool? isSelected,
    bool? isFileNode,
    String? filePath,
    String? folderRoot,
    Map<String, String>? collectionMembers,
  }) {
    return CanvasNode(
      id: id,
      position: position ?? this.position,
      size: size ?? this.size,
      memory: memory ?? this.memory,
      isDragging: isDragging ?? this.isDragging,
      isSelected: isSelected ?? this.isSelected,
      isFileNode: isFileNode ?? this.isFileNode,
      filePath: filePath ?? this.filePath,
      folderRoot: folderRoot ?? this.folderRoot,
      collectionMembers:
          collectionMembers ?? this.collectionMembers,
    );
  }

  @override
  String toString() =>
      'CanvasNode(id: $id, room: ${memory.room.name}, pos: ${position.dx.toStringAsFixed(0)},${position.dy.toStringAsFixed(0)})';
}
