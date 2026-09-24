import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import 'bridge_action_adapter.dart';

class DesktopFileSummary {
  final String name;
  final String path;
  final String kind;
  final int sizeBytes;
  final DateTime? modifiedAt;

  const DesktopFileSummary({
    required this.name,
    required this.path,
    required this.kind,
    required this.sizeBytes,
    this.modifiedAt,
  });

  Map<String, Object?> toJson() {
    return {
      'name': name,
      'path': path,
      'kind': kind,
      'sizeBytes': sizeBytes,
      'modifiedAt': modifiedAt?.toIso8601String(),
    };
  }
}

class DesktopFolderScanResult {
  final String rootPath;
  final int fileCount;
  final int folderCount;
  final Map<String, int> categoryCounts;
  final List<DesktopFileSummary> samples;
  final List<String> suggestions;
  // [以利沙 桌面整理橋 2026-06-24] 缺口二：超過 200 個檔案時截斷旗標
  final bool truncated;

  const DesktopFolderScanResult({
    required this.rootPath,
    required this.fileCount,
    required this.folderCount,
    required this.categoryCounts,
    required this.samples,
    required this.suggestions,
    this.truncated = false,
  });
}

class DesktopOrganizeMove {
  final String sourcePath;
  final String targetPath;
  final String fileName;
  final String kind;

  const DesktopOrganizeMove({
    required this.sourcePath,
    required this.targetPath,
    required this.fileName,
    required this.kind,
  });

  Map<String, Object?> toJson() {
    return {
      'sourcePath': sourcePath,
      'targetPath': targetPath,
      'fileName': fileName,
      'kind': kind,
    };
  }
}

class DesktopOrganizePlan {
  final String rootPath;
  final List<String> foldersToCreate;
  final List<DesktopOrganizeMove> moves;
  final List<String> skipped;

  const DesktopOrganizePlan({
    required this.rootPath,
    required this.foldersToCreate,
    required this.moves,
    required this.skipped,
  });

  Map<String, Object?> toJson() {
    return {
      'rootPath': rootPath,
      'foldersToCreate': foldersToCreate,
      'moves': [for (final move in moves) move.toJson()],
      'skipped': skipped,
    };
  }
}

class LocalDesktopFilesAdapter extends BridgeActionAdapter {
  LocalDesktopFilesAdapter({List<String>? allowedRoots})
    : _allowedRoots = allowedRoots;

  static const applyPlanPrefix = 'APPLY_DESKTOP_ORGANIZE_PLAN|';
  static const scanAuthorizedFolderPrefix = 'SCAN_AUTHORIZED_FOLDER|';

  final List<String>? _allowedRoots;

  @override
  String get id => 'local_desktop_files';

  @override
  String get displayName => 'Bridge Desktop 檔案讀取器';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.desktopFiles};

  @override
  bool canHandle(BridgeAction action, String provider) {
    return supportedTypes.contains(action.type) &&
        (provider == id || provider == 'bridge_desktop');
  }

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    if (kIsWeb) {
      return BridgeActionResult.needsProvider(
        action,
        '目前這裡是開發預覽環境，不能直接讀取你的本機檔案。正式使用時，桌面整理會交給 Bridge Desktop / 桌面 APP 執行；手機 APP 與智慧眼鏡 APP 可以發出整理指令，由桌面端安全掃描與確認。',
        provider: 'Bridge Desktop',
      );
    }

    final applyRoot = _applyRootFromPrompt(action.prompt);
    if (applyRoot != null) {
      return _executePlan(action, applyRoot);
    }

    final root = _chooseRoot(action.prompt);
    if (root == null) {
      return BridgeActionResult.needsProvider(
        action,
        '請先選擇並授權要整理的資料夾；我會先只讀掃描，不會移動、改名或刪除任何檔案',
        provider: 'Bridge Desktop',
      );
    }

    final directory = Directory(root);
    if (!await directory.exists()) {
      return BridgeActionResult.needsProvider(
        action,
        '指定的資料夾不存在或尚未授權：$root',
        provider: 'Bridge Desktop',
      );
    }

    final scanResult = await scan(directory);
    final plan = buildPlan(scanResult);
    final categorySummary = _categorySummary(scanResult.categoryCounts);
    return BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: [
        '桌面整理橋已完成只讀掃描。',
        '',
        '掃描位置：${scanResult.rootPath}',
        '讀到內容：${scanResult.fileCount} 個檔案、${scanResult.folderCount} 個資料夾',
        if (categorySummary.isNotEmpty) '主要分類：$categorySummary',
        // [以利沙 桌面整理橋 2026-06-24] 缺口一：人讀版計畫說明
        '',
        _buildPlanSummaryMessage(scanResult, plan),
        // [以利沙 桌面整理橋 2026-06-24] 缺口二：超過 200 個檔案時告知
        if (scanResult.truncated)
          '⚠️ 此資料夾超過 200 個檔案，本次只掃描前 200 個，整理計畫僅涵蓋這 200 個。',
        '',
        '我沒有移動、改名或刪除任何檔案。',
        '下一步可以請我依圖片、文件、影音、壓縮檔或程式碼產生整理計畫；等你確認後，再進入搬移或改名階段。',
      ].join('\n'),
      metadata: {
        'type': action.type.legacyType,
        'kind': 'desktop_file_plan',
        'provider': id,
        'adapter': displayName,
        'prompt': _taskPromptFromPrompt(action.prompt),
        'rootPath': scanResult.rootPath,
        'fileCount': scanResult.fileCount,
        'folderCount': scanResult.folderCount,
        'categoryCounts': scanResult.categoryCounts,
        'samples': [for (final item in scanResult.samples) item.toJson()],
        'suggestions': scanResult.suggestions,
        'categorySummary': categorySummary,
        'organizePlan': plan.toJson(),
        'plannedFolderCount': plan.foldersToCreate.length,
        'plannedMoveCount': plan.moves.length,
        'skippedCount': plan.skipped.length,
        'applyPrompt': '$applyPlanPrefix${scanResult.rootPath}',
        'readOnly': true,
        // [以利沙 桌面整理橋 2026-06-24] 缺口二：metadata 加 truncated
        'truncated': scanResult.truncated,
      },
    );
  }

  Future<BridgeActionResult> _executePlan(
    BridgeAction action,
    String rootPath,
  ) async {
    final directory = Directory(rootPath);
    if (!await directory.exists()) {
      return BridgeActionResult.needsProvider(
        action,
        '整理計畫的資料夾不存在或尚未授權：$rootPath',
        provider: 'Bridge Desktop',
      );
    }

    final scanResult = await scan(directory);
    final plan = buildPlan(scanResult);
    if (plan.moves.isEmpty && plan.foldersToCreate.isEmpty) {
      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: '桌面整理橋已檢查完成：目前沒有需要搬移的明確分類檔案。',
        metadata: {
          'type': action.type.legacyType,
          'kind': 'desktop_file_plan',
          'provider': id,
          'adapter': displayName,
          'prompt': action.prompt,
          'rootPath': rootPath,
          'fileCount': scanResult.fileCount,
          'folderCount': scanResult.folderCount,
          'categoryCounts': scanResult.categoryCounts,
          'categorySummary': _categorySummary(scanResult.categoryCounts),
          'organizePlan': plan.toJson(),
          'executed': true,
          'movedCount': 0,
          'createdFolderCount': 0,
          'readOnly': false,
        },
      );
    }

    var createdFolderCount = 0;
    for (final folder in plan.foldersToCreate) {
      final target = Directory(folder);
      if (!await target.exists()) {
        await target.create(recursive: true);
        createdFolderCount += 1;
      }
    }

    final moved = <DesktopOrganizeMove>[];
    final failed = <String>[];
    for (final move in plan.moves) {
      final source = File(move.sourcePath);
      if (!await source.exists()) {
        failed.add('${move.fileName}：來源不存在');
        continue;
      }
      final targetPath = await _uniqueTargetPath(move.targetPath);
      try {
        await source.rename(targetPath);
        moved.add(
          DesktopOrganizeMove(
            sourcePath: move.sourcePath,
            targetPath: targetPath,
            fileName: move.fileName,
            kind: move.kind,
          ),
        );
      } catch (error) {
        failed.add('${move.fileName}：$error');
      }
    }

    final recordPath = await _writeOrganizeRecord(
      rootPath: rootPath,
      moved: moved,
      failed: failed,
      skipped: plan.skipped,
      createdFolderCount: createdFolderCount,
    );

    return BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: [
        '桌面整理橋已執行整理計畫。',
        '',
        '建立分類資料夾：$createdFolderCount 個',
        '已移動檔案：${moved.length} 個',
        if (failed.isNotEmpty) '未完成項目：${failed.length} 個',
        '整理紀錄：$recordPath',
        // [以利沙 桌面整理橋 2026-06-24] 缺口二：_executePlan 補超過 200 個檔案告知
        if (scanResult.truncated)
          '⚠️ 此資料夾超過 200 個檔案，本次只掃描前 200 個，整理計畫僅涵蓋這 200 個。',
        '',
        '我只搬移第一層且分類明確的檔案；其他檔案仍留在原處。',
      ].join('\n'),
      metadata: {
        'type': action.type.legacyType,
        'kind': 'desktop_file_plan',
        'provider': id,
        'adapter': displayName,
        'prompt': action.prompt,
        'rootPath': rootPath,
        'fileCount': scanResult.fileCount,
        'folderCount': scanResult.folderCount,
        'categoryCounts': scanResult.categoryCounts,
        'categorySummary': _categorySummary(scanResult.categoryCounts),
        'organizePlan': plan.toJson(),
        'executed': true,
        'movedCount': moved.length,
        'createdFolderCount': createdFolderCount,
        'failed': failed,
        'skipped': plan.skipped,
        'recordPath': recordPath,
        'readOnly': false,
        // [以利沙 桌面整理橋 2026-06-24] 缺口二：metadata 加 truncated
        'truncated': scanResult.truncated,
      },
    );
  }

  String? _applyRootFromPrompt(String prompt) {
    if (!prompt.startsWith(applyPlanPrefix)) return null;
    final root = prompt.substring(applyPlanPrefix.length).trim();
    return root.isEmpty ? null : root;
  }

  String? _chooseRoot(String prompt) {
    final authorizedRoot = _authorizedRootFromPrompt(prompt);
    if (authorizedRoot != null) return authorizedRoot;

    final explicitRoots = _allowedRoots
        ?.where((path) => path.trim().isNotEmpty)
        .toList();
    if (explicitRoots != null && explicitRoots.isNotEmpty) {
      return explicitRoots.first;
    }

    return null;
  }

  static String scanPrompt({
    required String rootPath,
    required String taskPrompt,
  }) {
    return '$scanAuthorizedFolderPrefix$rootPath|$taskPrompt';
  }

  String? _authorizedRootFromPrompt(String prompt) {
    if (!prompt.startsWith(scanAuthorizedFolderPrefix)) return null;
    final payload = prompt.substring(scanAuthorizedFolderPrefix.length);
    final separatorIndex = payload.indexOf('|');
    final root = separatorIndex == -1
        ? payload.trim()
        : payload.substring(0, separatorIndex).trim();
    return root.isEmpty ? null : root;
  }

  String _taskPromptFromPrompt(String prompt) {
    if (!prompt.startsWith(scanAuthorizedFolderPrefix)) return prompt;
    final payload = prompt.substring(scanAuthorizedFolderPrefix.length);
    final separatorIndex = payload.indexOf('|');
    if (separatorIndex == -1) return '整理授權資料夾';
    final task = payload.substring(separatorIndex + 1).trim();
    return task.isEmpty ? '整理授權資料夾' : task;
  }

  Future<DesktopFolderScanResult> scan(Directory root) async {
    var fileCount = 0;
    var folderCount = 0;
    final categoryCounts = <String, int>{};
    final samples = <DesktopFileSummary>[];

    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory) {
        folderCount += 1;
        continue;
      }
      if (entity is! File) continue;
      fileCount += 1;
      final stat = await entity.stat();
      final name = _fileNameFromPath(entity.path);
      if (name.startsWith('Bridge整理紀錄-')) continue;
      final kind = _kindFor(name);
      categoryCounts[kind] = (categoryCounts[kind] ?? 0) + 1;
      if (samples.length < 200) {
        samples.add(
          DesktopFileSummary(
            name: name,
            path: entity.path,
            kind: kind,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      }
      if (fileCount >= 200) break; // [以利沙 桌面整理橋 2026-06-24] 截斷點
    }

    // [以利沙 桌面整理橋 2026-06-24] 缺口二：記錄是否因超過 200 個檔案而截斷
    final wasTruncated = fileCount >= 200;

    return DesktopFolderScanResult(
      rootPath: root.path,
      fileCount: fileCount,
      folderCount: folderCount,
      categoryCounts: categoryCounts,
      samples: samples,
      suggestions: _suggestions(categoryCounts),
      truncated: wasTruncated,
    );
  }

  String _fileNameFromPath(String path) {
    final parts = path.split(Platform.pathSeparator);
    if (parts.isEmpty) return path;
    final name = parts.last.trim();
    return name.isEmpty ? path : name;
  }

  DesktopOrganizePlan buildPlan(DesktopFolderScanResult scan) {
    final folders = <String>{};
    final moves = <DesktopOrganizeMove>[];
    final skipped = <String>[];
    for (final sample in scan.samples) {
      if (sample.kind == '其他') {
        skipped.add('${sample.name}：尚未分類');
        continue;
      }
      final folder = '${scan.rootPath}${Platform.pathSeparator}${sample.kind}';
      folders.add(folder);
      moves.add(
        DesktopOrganizeMove(
          sourcePath: sample.path,
          targetPath: '$folder${Platform.pathSeparator}${sample.name}',
          fileName: sample.name,
          kind: sample.kind,
        ),
      );
    }
    return DesktopOrganizePlan(
      rootPath: scan.rootPath,
      foldersToCreate: folders.toList()..sort(),
      moves: moves,
      skipped: skipped,
    );
  }

  String _kindFor(String name) {
    final lower = name.toLowerCase();
    final extension = lower.contains('.') ? lower.split('.').last : '';
    if ([
      'png',
      'jpg',
      'jpeg',
      'gif',
      'webp',
      'heic',
      'svg',
    ].contains(extension)) {
      return '圖片';
    }
    if ([
      'md',
      'txt',
      'pdf',
      'doc',
      'docx',
      'pages',
      'rtf',
    ].contains(extension)) {
      return '文件';
    }
    if (['mp4', 'mov', 'm4v', 'avi', 'webm'].contains(extension)) {
      return '影片';
    }
    if (['mp3', 'wav', 'm4a', 'flac', 'aac'].contains(extension)) {
      return '音訊';
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(extension)) {
      return '壓縮檔';
    }
    if ([
      'dart',
      'js',
      'ts',
      'py',
      'json',
      'yaml',
      'yml',
      'html',
      'css',
    ].contains(extension)) {
      return '程式碼';
    }
    return '其他';
  }

  List<String> _suggestions(Map<String, int> categoryCounts) {
    if (categoryCounts.isEmpty) {
      return const ['目前資料夾沒有可整理的檔案。'];
    }
    final sorted = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in sorted.take(4))
        '建立「${entry.key}」分類資料夾，先處理 ${entry.value} 個項目。',
      '先只產生整理計畫，確認後再進入下一階段的搬移或改名。',
    ];
  }

  String _categorySummary(Map<String, int> categoryCounts) {
    if (categoryCounts.isEmpty) return '';
    final sorted = categoryCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(5)
        .map((entry) => '${entry.key} ${entry.value}')
        .join('、');
  }

  // [以利沙 桌面整理橋 2026-06-24] 缺口一：人讀版整理計畫說明 helper
  String _buildPlanSummaryMessage(
    DesktopFolderScanResult scan,
    DesktopOrganizePlan plan,
  ) {
    // 統計各 kind 的移動數量
    final kindCounts = <String, int>{};
    for (final move in plan.moves) {
      kindCounts[move.kind] = (kindCounts[move.kind] ?? 0) + 1;
    }
    final folderCount = plan.foldersToCreate.length;
    final skippedCount = plan.skipped.length;
    final totalFiles = scan.fileCount;

    if (kindCounts.isEmpty) {
      return '找到 $totalFiles 個檔案，沒有可以自動分類的項目，所有檔案留在原處。';
    }

    final sorted = kindCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final folderDetail =
        sorted.map((e) => '${e.key}（${e.value}）').join('、');

    final buffer = StringBuffer();
    buffer.write('找到 $totalFiles 個檔案，準備建立 $folderCount 個分類資料夾：$folderDetail');
    if (skippedCount > 0) {
      buffer.write('，另有 $skippedCount 個未分類檔案留在原處。');
    } else {
      buffer.write('。');
    }
    return buffer.toString();
  }

  Future<String> _uniqueTargetPath(String targetPath) async {
    final file = File(targetPath);
    if (!await file.exists()) return targetPath;
    final separator = Platform.pathSeparator;
    final parent = targetPath.contains(separator)
        ? targetPath.substring(0, targetPath.lastIndexOf(separator))
        : '.';
    final name = targetPath.contains(separator)
        ? targetPath.substring(targetPath.lastIndexOf(separator) + 1)
        : targetPath;
    final dotIndex = name.lastIndexOf('.');
    final stem = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final ext = dotIndex > 0 ? name.substring(dotIndex) : '';
    var index = 2;
    while (true) {
      final candidate = '$parent$separator$stem ($index)$ext';
      if (!await File(candidate).exists()) return candidate;
      index += 1;
    }
  }

  Future<String> _writeOrganizeRecord({
    required String rootPath,
    required List<DesktopOrganizeMove> moved,
    required List<String> failed,
    required List<String> skipped,
    required int createdFolderCount,
  }) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path = '$rootPath${Platform.pathSeparator}Bridge整理紀錄-$timestamp.md';
    final lines = [
      '# Bridge 桌面整理紀錄',
      '',
      '- 整理時間：${DateTime.now().toIso8601String()}',
      '- 根資料夾：$rootPath',
      '- 建立資料夾：$createdFolderCount',
      '- 移動檔案：${moved.length}',
      '- 未完成：${failed.length}',
      '',
      '## 已移動',
      '',
      if (moved.isEmpty) '（無）',
      for (final move in moved)
        '- ${move.fileName}｜${move.kind}｜${move.sourcePath} → ${move.targetPath}',
      '',
      '## 未完成',
      '',
      if (failed.isEmpty) '（無）',
      for (final item in failed) '- $item',
      '',
      '## 保留在原處',
      '',
      if (skipped.isEmpty) '（無）',
      for (final item in skipped) '- $item',
      '',
    ];
    await File(path).writeAsString(lines.join('\n'));
    return path;
  }
}
