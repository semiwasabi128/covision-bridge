// file_export_service.dart
// AD-05 檔案層匯出服務 — 對話/記憶/洞察 → 檔案層
// Sprint 13-7（含 S13-4 快取搬移）
//
// 職責：
// 1. 匯出對話到 /專案/[name]/產出/ 或 /記憶庫/
// 2. 匯出大腦容器記憶到 /記憶庫/
// 3. 匯出舊 MemoryStore 記憶到 /記憶庫/（快取搬移）
// 4. 匯出 Transurfing 洞察到 /圖書館/
// 5. 匯出後自動打標籤

import 'dart:convert';

import 'package:bridge_app/services/brain_container/brain_container_service.dart';
import 'package:bridge_app/services/conversation_store.dart';
import 'package:bridge_app/services/file_layer_service.dart';
import 'package:bridge_app/services/file_tag_store.dart';
import 'package:bridge_app/services/master_folder_store.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:flutter/foundation.dart';

/// 匯出結果
class ExportResult {
  final bool success;
  final String? filePath;
  final String? error;
  final int itemCount;

  const ExportResult({
    required this.success,
    this.filePath,
    this.error,
    this.itemCount = 0,
  });
}

/// 檔案層匯出服務。
///
/// 把 App sandbox 裡的資料（對話、記憶、洞察）匯出成
/// 使用者可見的 Markdown / JSON 檔案，存入檔案層。
class FileExportService {
  final FileLayerService _fileLayer;
  final FileTagStore _tagStore;
  final MasterFolderStore _folderStore;

  FileExportService({
    FileLayerService? fileLayer,
    FileTagStore? tagStore,
    MasterFolderStore? folderStore,
  })  : _fileLayer = fileLayer ?? FileLayerService(),
        _tagStore = tagStore ?? const FileTagStore(),
        _folderStore = folderStore ?? const MasterFolderStore();

  // ═══════════════════════════════════════════════════
  // 對話匯出
  // ═══════════════════════════════════════════════════

  /// 匯出單一對話為 Markdown。
  ///
  /// 存入 /專案/[projectName]/產出/ 或 /記憶庫/（無專案時）。
  Future<ExportResult> exportConversation({
    required String conversationId,
    String? projectName,
    List<String> tags = const [],
  }) async {
    try {
      final conversations = await ConversationStore.getAll();
      final conv = conversations.where((c) => c.id == conversationId).firstOrNull;
      if (conv == null) {
        return const ExportResult(success: false, error: '找不到對話');
      }

      final folders = await _folderStore.loadEnabled();
      if (folders.isEmpty) {
        return const ExportResult(success: false, error: '沒有啟用的主資料夾');
      }
      final folder = folders.first;

      // 建 Markdown
      final md = _conversationToMarkdown(conv);

      // 檔名
      final safeTitle = _sanitizeFileName(conv.title);
      final timestamp = _fileTimestamp(conv.updatedAt);
      final fileName = '${timestamp}_$safeTitle.md';

      String filePath;
      if (projectName != null && projectName.isNotEmpty) {
        filePath = await _fileLayer.writeToProjectOutput(
          folder, projectName, fileName, utf8.encode(md),
        );
        // 標籤
        for (final tag in tags) {
          await _tagStore.tagFile(filePath, tag);
        }
        await _tagStore.tagFile(filePath, '對話');
        if (conv.companionId != null) {
          await _tagStore.tagFile(filePath, '夥伴:${conv.companionId}');
        }
      } else {
        filePath = await _fileLayer.writeToMemoryVault(
          folder, fileName, utf8.encode(md),
        );
        await _tagStore.tagFile(filePath, '對話');
      }

      return ExportResult(success: true, filePath: filePath, itemCount: 1);
    } catch (e) {
      debugPrint('[FileExport] 匯出對話失敗: $e');
      return ExportResult(success: false, error: '$e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 記憶匯出（大腦容器 + 舊 MemoryStore）
  // ═══════════════════════════════════════════════════

  /// 匯出大腦容器記憶為 JSON。
  ///
  /// 存入 /記憶庫/brain_memories_[timestamp].json
  /// S13-4 快取搬移：把 sandbox 裡的大腦容器資料搬到檔案層。
  Future<ExportResult> exportBrainMemories({
    int limit = 500,
  }) async {
    try {
      final service = BrainContainerService.instance;
      if (!service.isInitialized) {
        return const ExportResult(success: false, error: '大腦容器未初始化');
      }

      final memories = await service.getAllMemories(limit: limit);
      final connections = await service.getAllConnections(limit: limit * 2);

      final folders = await _folderStore.loadEnabled();
      if (folders.isEmpty) {
        return const ExportResult(success: false, error: '沒有啟用的主資料夾');
      }
      final folder = folders.first;

      final data = {
        'exportedAt': DateTime.now().toIso8601String(),
        'memoryCount': memories.length,
        'connectionCount': connections.length,
        'memories': memories.map((m) => m.toMap()).toList(),
        'connections': connections.map((c) => c.toMap()).toList(),
      };

      final json = const JsonEncoder.withIndent('  ').convert(data);
      final fileName = 'brain_memories_${_fileTimestamp(DateTime.now())}.json';
      final filePath = await _fileLayer.writeToMemoryVault(
        folder, fileName, utf8.encode(json),
      );

      await _tagStore.tagFile(filePath, '大腦記憶');
      await _tagStore.tagFile(filePath, '匯出');

      return ExportResult(
        success: true,
        filePath: filePath,
        itemCount: memories.length,
      );
    } catch (e) {
      debugPrint('[FileExport] 匯出大腦記憶失敗: $e');
      return ExportResult(success: false, error: '$e');
    }
  }

  /// 匯出舊 MemoryStore 記憶為 Markdown。
  ///
  /// S13-4 快取搬移：把 SharedPreferences 裡的舊記憶搬到檔案層。
  Future<ExportResult> exportLegacyMemories() async {
    try {
      final memories = await MemoryStore.getAll();
      if (memories.isEmpty) {
        return const ExportResult(success: false, error: '沒有舊記憶');
      }

      final folders = await _folderStore.loadEnabled();
      if (folders.isEmpty) {
        return const ExportResult(success: false, error: '沒有啟用的主資料夾');
      }
      final folder = folders.first;

      final buffer = StringBuffer();
      buffer.writeln('# 舊記憶匯出');
      buffer.writeln();
      buffer.writeln('> 匯出時間：${DateTime.now().toIso8601String()}');
      buffer.writeln('> 來源：MemoryStore (SharedPreferences)');
      buffer.writeln('> 數量：${memories.length}');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();

      for (int i = 0; i < memories.length; i++) {
        buffer.writeln('## ${i + 1}');
        buffer.writeln();
        buffer.writeln(memories[i]);
        buffer.writeln();
      }

      final fileName = 'legacy_memories_${_fileTimestamp(DateTime.now())}.md';
      final filePath = await _fileLayer.writeToMemoryVault(
        folder, fileName, utf8.encode(buffer.toString()),
      );

      await _tagStore.tagFile(filePath, '舊記憶');
      await _tagStore.tagFile(filePath, '匯出');

      return ExportResult(
        success: true,
        filePath: filePath,
        itemCount: memories.length,
      );
    } catch (e) {
      debugPrint('[FileExport] 匯出舊記憶失敗: $e');
      return ExportResult(success: false, error: '$e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 洞察匯出
  // ═══════════════════════════════════════════════════

  /// 匯出 Transurfing 洞察記錄到 /圖書館/。
  Future<ExportResult> exportInsights() async {
    try {
      final insights = await MemoryStore.getTransurfingInsightRecords();
      if (insights.isEmpty) {
        return const ExportResult(success: false, error: '沒有洞察記錄');
      }

      final folders = await _folderStore.loadEnabled();
      if (folders.isEmpty) {
        return const ExportResult(success: false, error: '沒有啟用的主資料夾');
      }
      final folder = folders.first;

      final buffer = StringBuffer();
      buffer.writeln('# Transurfing 洞察匯出');
      buffer.writeln();
      buffer.writeln('> 匯出時間：${DateTime.now().toIso8601String()}');
      buffer.writeln('> 數量：${insights.length}');
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();

      for (final insight in insights) {
        buffer.writeln('## 洞察');
        buffer.writeln();
        buffer.writeln(insight.insight);
        buffer.writeln();
        if (insight.feedback != null) {
          buffer.writeln('- 回饋：${insight.feedback!.name}');
        }
        buffer.writeln('- 信任分數：${insight.trustScore}');
        buffer.writeln('- 在記憶中：${insight.inMemory ? "是" : "否"}');
        if (insight.room != null) {
          buffer.writeln('- 房間：${insight.room!.displayName}');
        }
        buffer.writeln();
      }

      final fileName = 'insights_${_fileTimestamp(DateTime.now())}.md';
      final filePath = await _fileLayer.writeToLibrary(
        folder, fileName, utf8.encode(buffer.toString()),
      );

      await _tagStore.tagFile(filePath, '洞察');
      await _tagStore.tagFile(filePath, '匯出');

      return ExportResult(
        success: true,
        filePath: filePath,
        itemCount: insights.length,
      );
    } catch (e) {
      debugPrint('[FileExport] 匯出洞察失敗: $e');
      return ExportResult(success: false, error: '$e');
    }
  }

  // ═══════════════════════════════════════════════════
  // 全量匯出（S13-4 快取搬移）
  // ═══════════════════════════════════════════════════

  /// 一鍵匯出所有資料到檔案層。
  ///
  /// 依序匯出：大腦記憶 → 舊記憶 → 洞察。
  /// 回傳每項的結果。
  Future<List<ExportResult>> exportAll() async {
    return [
      await exportBrainMemories(),
      await exportLegacyMemories(),
      await exportInsights(),
    ];
  }

  // ═══════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════

  String _conversationToMarkdown(dynamic conv) {
    final buffer = StringBuffer();
    buffer.writeln('# ${conv.title}');
    buffer.writeln();
    buffer.writeln('> 建立時間：${conv.createdAt.toIso8601String()}');
    buffer.writeln('> 更新時間：${conv.updatedAt.toIso8601String()}');
    if (conv.companionId != null) {
      buffer.writeln('> 夥伴：${conv.companionId}');
    }
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final msg in conv.messages) {
      final role = msg.role == 'user' ? '👤 使用者' : '🤖 AI';
      buffer.writeln('### $role');
      buffer.writeln();
      buffer.writeln(msg.content);
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _sanitizeFileName(String input) {
    return input
        .replaceAll(RegExp(r'[\/\\\:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .substring(0, input.length.clamp(0, 50));
  }

  String _fileTimestamp(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}${dt.minute.toString().padLeft(2, '0')}';
  }
}
