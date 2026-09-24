// [教練 Agent Sprint 17 Step 3 2026-07-07]
// BridgeActionUIHelper — 橋樑動作的純函式 helpers（icon、label、route、metadata 解析）。
// 從 chat_screen.dart 搬出，零狀態依賴。
import 'package:flutter/material.dart';

import '../../../models/bridge_action.dart';
import '../../../services/bridge_action_executor.dart';

class BridgeActionUIHelper {
  BridgeActionUIHelper._();

  /// 橋樑動作圖標
  static IconData icon(String type) {
    switch (type.toLowerCase()) {
      case 'generate_image':
        return Icons.image;
      case 'generate_music':
        return Icons.music_note;
      case 'generate_video':
        return Icons.videocam;
      case 'browse':
        return Icons.public;
      case 'vision':
        return Icons.image_search_outlined;
      case 'document':
        return Icons.description;
      case 'desktop_files':
        return Icons.desktop_windows;
      default:
        return Icons.build;
    }
  }

  /// 橋樑動作標籤
  static String label(String type) {
    switch (type.toLowerCase()) {
      case 'generate_image':
        return '生成圖片';
      case 'generate_music':
        return '生成音樂';
      case 'generate_video':
        return '生成影片';
      case 'browse':
        return '瀏覽網頁';
      case 'vision':
        return '圖片辨識';
      case 'document':
        return '產出文件';
      case 'desktop_files':
        return '桌面整理';
      default:
        return type;
    }
  }

  /// 橋樑動作 Chip 標籤（vision 類型根據 prompt 細分）
  static String chipLabel(BridgeAction action) {
    if (action.type == BridgeActionType.vision) {
      final prompt = action.prompt;
      if (prompt.contains('讀到的文字') || prompt.contains('辨識')) {
        return '擷取文字';
      }
      if (prompt.contains('問題') ||
          prompt.contains('排版') ||
          prompt.contains('錯誤')) {
        return '找問題';
      }
      if (prompt.contains('視覺參考') || prompt.contains('參考')) {
        return '作為參考';
      }
      return '描述內容';
    }
    return label(action.type.legacyType);
  }

  /// 橋樑動作設定路由
  static String setupRoute(BridgeActionResult result) {
    final metadataRoute = result.metadata?['setupRoute']?.toString();
    if (metadataRoute != null && metadataRoute.trim().isNotEmpty) {
      return metadataRoute.trim();
    }
    switch (result.metadata?['type']?.toString()) {
      case 'browse':
        return '/golden-keys?returnTo=/chat';
      case 'vision':
        return '/golden-keys?returnTo=/chat';
      case 'generate_music':
      case 'generate_video':
      case 'generate_animation':
      case 'generate_image':
        return '/golden-keys?returnTo=/chat';
      case 'document':
      default:
        return '/settings?returnTo=/chat';
    }
  }

  /// 能力圖標
  static IconData capabilityIcon(String iconName) {
    switch (iconName) {
      case 'image_search':
        return Icons.image_search_outlined;
      case 'travel_explore':
        return Icons.travel_explore_outlined;
      case 'music_note':
        return Icons.music_note_outlined;
      case 'desktop_windows':
        return Icons.desktop_windows_outlined;
      case 'movie_creation':
        return Icons.movie_creation_outlined;
      case 'add_link':
        return Icons.add_link_outlined;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'hub':
        return Icons.hub_outlined;
      default:
        return Icons.vpn_key_outlined;
    }
  }

  /// 判斷是否自動執行 assistant 動作
  static bool shouldAutoExecuteAssistantAction(BridgeAction action) {
    switch (action.type) {
      case BridgeActionType.browse:
      case BridgeActionType.vision:
      case BridgeActionType.document:
      case BridgeActionType.desktopFiles:
        return true;
      case BridgeActionType.generateImage:
      case BridgeActionType.generateAnimation:
      case BridgeActionType.generateMusic:
      case BridgeActionType.generateVideo:
      case BridgeActionType.unknown:
        return false;
    }
  }

  /// 精簡摘要文字
  static String compactExcerpt(String value, {int maxChars = 240}) {
    final clean = value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[#*_`]+'), '')
        .trim();
    if (clean.length <= maxChars) return clean;
    return '${clean.substring(0, maxChars).trim()}...';
  }

  /// 從 metadata 解析字串列表
  static List<String> stringListFromMetadata(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  /// 從 metadata 解析桌面樣本名稱
  static List<String> desktopSampleNames(Object? samples) {
    if (samples is! List) return const <String>[];
    return samples
        .whereType<Map>()
        .map((item) => item['name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  /// 從 metadata 解析搜尋來源 maps
  static List<Map<String, dynamic>> searchSourceMaps(
      Map<String, dynamic>? metadata) {
    final sources = metadata?['searchSources'];
    if (sources is! List) return const [];
    return sources
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}
