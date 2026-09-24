// folder_scanner_service.dart
// 夥伴人格機制 — B1 分層資料夾掃描
// [教練 Agent 2026-07-22] Phase H
//
// 兩層掃描：
// Phase 1 — scanMetadata()：秒出元資料（檔案數、類型分布、資料夾深度、命名風格、最近修改）
// Phase 2 — scanContent()：背景讀前 N 個檔案標題/前幾行，推測興趣
//
// 掃描結果用於 PersonaInferenceService 推理人格卡。
// 隱私：只讀元資料和前幾行，不上傳完整檔案內容到雲端。

import 'dart:io';
import 'package:flutter/foundation.dart';

/// 資料夾掃描結果
class FolderScanResult {
  /// 來源路徑
  final String rootPath;

  // Phase 1：元資料
  final int folderDepth;
  final int totalFiles;
  final Map<String, int> fileTypes; // {".md": 320, ".png": 580}
  final String namingStyle; // "chinese_with_date_prefix"
  final List<String> topFolders; // ["01-App-原始碼", "02-架構設計"]
  final DateTime? lastModified;
  final bool isEmpty;

  // Phase 2：內容採樣
  final List<String> sampledTitles; // 前 N 個檔案的標題
  final List<String> inferredInterests; // 推測的興趣領域

  /// Phase 1 是否完成
  final bool phase1Complete;
  /// Phase 2 是否完成
  final bool phase2Complete;

  const FolderScanResult({
    required this.rootPath,
    this.folderDepth = 0,
    this.totalFiles = 0,
    this.fileTypes = const {},
    this.namingStyle = '',
    this.topFolders = const [],
    this.lastModified,
    this.isEmpty = false,
    this.sampledTitles = const [],
    this.inferredInterests = const [],
    this.phase1Complete = false,
    this.phase2Complete = false,
  });

  /// 合併 Phase 2 結果到既有 Phase 1 結果
  FolderScanResult mergePhase2({
    required List<String> sampledTitles,
    required List<String> inferredInterests,
  }) {
    return FolderScanResult(
      rootPath: rootPath,
      folderDepth: folderDepth,
      totalFiles: totalFiles,
      fileTypes: fileTypes,
      namingStyle: namingStyle,
      topFolders: topFolders,
      lastModified: lastModified,
      isEmpty: isEmpty,
      sampledTitles: sampledTitles,
      inferredInterests: inferredInterests,
      phase1Complete: phase1Complete,
      phase2Complete: true,
    );
  }

  /// 轉成可送給雲端推理的摘要文字（隱私安全——只送摘要不送完整內容）
  String toSummaryText() {
    final parts = <String>[];
    parts.add('資料夾路徑: $rootPath');
    parts.add('總檔案數: $totalFiles');
    parts.add('資料夾深度: $folderDepth 層');
    parts.add('命名風格: $namingStyle');
    if (topFolders.isNotEmpty) {
      parts.add('頂層資料夾: ${topFolders.join(", ")}');
    }
    if (fileTypes.isNotEmpty) {
      final sortedTypes = fileTypes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final typeSummary = sortedTypes
          .take(10)
          .map((e) => '${e.key}(${e.value})')
          .join(', ');
      parts.add('檔案類型分布: $typeSummary');
    }
    if (lastModified != null) {
      parts.add('最近修改: ${lastModified!.toIso8601String().substring(0, 10)}');
    }
    if (inferredInterests.isNotEmpty) {
      parts.add('推測興趣: ${inferredInterests.join(", ")}');
    }
    if (sampledTitles.isNotEmpty) {
      parts.add('抽樣標題: ${sampledTitles.take(10).join(" / ")}');
    }
    return parts.join('\n');
  }
}

/// 分層資料夾掃描服務
///
/// Phase 1 秒出元資料，Phase 2 背景採樣內容。
/// 設計上 Phase 2 不阻塞——呼叫端可以先拿 Phase 1 結果，
/// Phase 2 完成後透過回調更新。
class FolderScannerService {
  FolderScannerService._();
  static final FolderScannerService instance = FolderScannerService._();

  /// Phase 1：掃描元資料（秒出）
  ///
  /// 遍歷目錄統計檔案數量、類型、深度、命名風格。
  /// 大量檔案時限制最多遍歷 5000 個以避免卡住。
  Future<FolderScanResult> scanMetadata(String rootPath) async {
    try {
      final rootDir = Directory(rootPath);
      if (!await rootDir.exists()) {
        return FolderScanResult(
          rootPath: rootPath,
          isEmpty: true,
          phase1Complete: true,
        );
      }

      int totalFiles = 0;
      int maxDepth = 0;
      final fileTypes = <String, int>{};
      final topFolders = <String>[];
      DateTime? lastModified;
      final namingSamples = <String>[];

      // 收集頂層資料夾名稱
      try {
        await for (final entity in rootDir.list(followLinks: false)) {
          if (entity is Directory) {
            final name = entity.path.split('/').last;
            if (name.isNotEmpty && !name.startsWith('.')) {
              topFolders.add(name);
            }
          }
        }
      } catch (_) {
        // 權限問題忽略
      }

      // 遞迴掃描——限制最多 5000 個檔案
      await _scanRecursive(
        rootDir,
        rootPath,
        0,
        (file) {
          if (totalFiles >= 5000) return;
          totalFiles++;

          // 檔案類型
          final ext = file.path.lastIndexOf('.') >= 0
              ? file.path.substring(file.path.lastIndexOf('.')).toLowerCase()
              : '(無副檔名)';
          fileTypes[ext] = (fileTypes[ext] ?? 0) + 1;

          // 命名風格樣本
          final fileName = file.path.split('/').last;
          if (namingSamples.length < 20) {
            namingSamples.add(fileName);
          }

          // 最近修改時間
          try {
            final stat = file.statSync();
            final mod = stat.modified;
            if (lastModified == null || mod.isAfter(lastModified!)) {
              lastModified = mod;
            }
          } catch (_) {}

          // 深度
          final relPath = file.path.substring(rootPath.length);
          final depth = relPath.split('/').where((s) => s.isNotEmpty).length;
          if (depth > maxDepth) maxDepth = depth;
        },
      );

      // 推測命名風格
      final namingStyle = _inferNamingStyle(namingSamples);

      return FolderScanResult(
        rootPath: rootPath,
        folderDepth: maxDepth,
        totalFiles: totalFiles,
        fileTypes: fileTypes,
        namingStyle: namingStyle,
        topFolders: topFolders,
        lastModified: lastModified,
        isEmpty: totalFiles == 0,
        phase1Complete: true,
      );
    } catch (e) {
      debugPrint('[FolderScanner] Phase 1 失敗: $e');
      return FolderScanResult(
        rootPath: rootPath,
        isEmpty: true,
        phase1Complete: true,
      );
    }
  }

  /// Phase 2：背景內容採樣
  ///
  /// 讀取前 N 個檔案的標題/前幾行，推測使用者興趣。
  /// 只讀文字檔（.md, .txt, .dart, .py, .json 等），跳過二進位檔案。
  /// 讀取的內容只存在本地，不送雲端——只送推測出的興趣標籤。
  Future<FolderScanResult> scanContent(
    String rootPath, {
    int maxFiles = 50,
    FolderScanResult? phase1Result,
  }) async {
    try {
      // 如果沒帶 Phase 1 結果，先跑一次
      final phase1 = phase1Result ?? await scanMetadata(rootPath);
      if (phase1.isEmpty) {
        return phase1.mergePhase2(
          sampledTitles: [],
          inferredInterests: [],
        );
      }

      final rootDir = Directory(rootPath);
      final sampledTitles = <String>[];
      final sampledContent = <String>[];
      final textExtensions = <String>{
        '.md', '.txt', '.dart', '.py', '.json', '.yaml', '.yml',
        '.js', '.ts', '.html', '.css', '.csv', '.xml', '.swift',
        '.kt', '.go', '.rs', '.sh',
      };

      int filesRead = 0;
      await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
        if (filesRead >= maxFiles) break;
        if (entity is! File) continue;

        final ext = entity.path.lastIndexOf('.') >= 0
            ? entity.path.substring(entity.path.lastIndexOf('.')).toLowerCase()
            : '';
        if (!textExtensions.contains(ext)) continue;

        try {
          // 讀前 5 行
          final lines = await entity
              .openRead(0, 2048)
              .map((bytes) => String.fromCharCodes(bytes))
              .join();
          final lineList = lines.split('\n').take(5).toList();

          // 標題：第一行非空行，去掉 markdown # 前綴
          String? title;
          for (final line in lineList) {
            final trimmed = line.trim();
            if (trimmed.isEmpty) continue;
            title = trimmed.replaceAll(RegExp(r'^#+\s*'), '');
            break;
          }
          if (title == null) continue;

          sampledTitles.add(title);
          sampledContent.add(lineList.join(' '));
          filesRead++;
        } catch (_) {
          // 讀取失敗跳過
        }
      }

      // 推測興趣領域
      final inferredInterests = _inferInterests(
        sampledTitles,
        sampledContent,
        phase1.fileTypes,
      );

      return phase1.mergePhase2(
        sampledTitles: sampledTitles,
        inferredInterests: inferredInterests,
      );
    } catch (e) {
      debugPrint('[FolderScanner] Phase 2 失敗: $e');
      return phase1Result ?? FolderScanResult(
        rootPath: rootPath,
        isEmpty: true,
        phase1Complete: true,
        phase2Complete: true,
      );
    }
  }

  /// 遞迴掃描目錄
  Future<void> _scanRecursive(
    Directory dir,
    String rootPath,
    int depth,
    void Function(File) onFile,
  ) async {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          onFile(entity);
        } else if (entity is Directory) {
          // 跳過隱藏資料夾和常見噪音目錄
          final name = entity.path.split('/').last;
          if (name.startsWith('.') || name == 'node_modules' || name == '.git') {
            continue;
          }
          await _scanRecursive(entity, rootPath, depth + 1, onFile);
        }
      }
    } catch (_) {
      // 權限問題忽略
    }
  }

  /// 根據檔名樣本推測命名風格
  String _inferNamingStyle(List<String> samples) {
    if (samples.isEmpty) return 'unknown';

    bool hasDatePrefix = false;
    bool hasNumberPrefix = false;
    bool hasChinese = false;
    bool hasCamelCase = false;
    bool hasSnakeCase = false;
    bool hasKebabCase = false;

    for (final name in samples) {
      if (RegExp(r'^\d{4}[-/]\d{2}').hasMatch(name)) hasDatePrefix = true;
      if (RegExp(r'^\d{2}[-_]').hasMatch(name)) hasNumberPrefix = true;
      if (RegExp(r'[\u4e00-\u9fff]').hasMatch(name)) hasChinese = true;
      if (RegExp(r'[a-z][A-Z]').hasMatch(name)) hasCamelCase = true;
      if (name.contains('_')) hasSnakeCase = true;
      if (name.contains('-') && !name.startsWith('-')) hasKebabCase = true;
    }

    final styles = <String>[];
    if (hasChinese) styles.add('chinese');
    if (hasDatePrefix) styles.add('date_prefix');
    if (hasNumberPrefix) styles.add('number_prefix');
    if (hasCamelCase) styles.add('camelCase');
    if (hasSnakeCase) styles.add('snake_case');
    if (hasKebabCase) styles.add('kebab-case');

    return styles.isEmpty ? 'mixed' : styles.join('_with_');
  }

  /// 根據採樣內容推測興趣領域
  List<String> _inferInterests(
    List<String> titles,
    List<String> contents,
    Map<String, int> fileTypes,
  ) {
    final interests = <String>{};

    // 從檔案類型推測
    if ((fileTypes['.dart'] ?? 0) > 5) interests.add('程式開發');
    if ((fileTypes['.py'] ?? 0) > 5) interests.add('Python');
    if ((fileTypes['.md'] ?? 0) > 10) interests.add('筆記寫作');
    if ((fileTypes['.png'] ?? 0) > 50 || (fileTypes['.jpg'] ?? 0) > 50) interests.add('視覺創作');
    if ((fileTypes['.json'] ?? 0) > 10) interests.add('資料結構');
    if ((fileTypes['.csv'] ?? 0) > 0) interests.add('數據分析');

    // 從標題關鍵字推測
    final allText = '${titles.join(" ")} ${contents.join(" ")}';
    final keywordMap = <String, String>{
      'flutter': 'Flutter 開發',
      'dart': 'Dart 程式',
      'ai': '人工智慧',
      'agent': 'AI Agent',
      '農場': '農場管理',
      '橋樑': '橋樑計畫',
      '設計': '設計',
      '架構': '系統架構',
      '測試': '測試',
      '知識': '知識管理',
      '記憶': '記憶系統',
      '畫布': '畫布工作流',
      '人格': '人格設計',
      '範本': '範本系統',
      '社群': '社群媒體',
      'IG': 'Instagram',
      '投資': '投資理財',
      '聖經': '信仰',
      '詩': '詩歌文學',
    };

    final lowerText = allText.toLowerCase();
    for (final entry in keywordMap.entries) {
      if (lowerText.contains(entry.key.toLowerCase())) {
        interests.add(entry.value);
      }
    }

    return interests.take(8).toList();
  }
}
