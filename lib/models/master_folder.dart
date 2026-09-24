// AD-05 主資料夾架構 — 資料模型
//
// 兩層混合：
// - 快取層（App sandbox，使用者看不到）：對話記錄、記憶索引、向量嵌入
// - 檔案層（使用者可見，可管理）：/專案/ /記憶庫/ /圖書館/ + meta.json
//
// 使用者可納入多個資料夾為「主資料夾」（Google Drive 同步概念），
// App 以這些資料夾為邊界掃描，不掃整台電腦。

import 'dart:convert';
import 'dart:io';

// ──────────────────────────────────────────────
// Enums
// ──────────────────────────────────────────────

/// 檔案層三大頂層目錄
enum FolderCategory {
  /// /專案/[name]/ — 使用者的專案產出與參考
  projects,
  /// /記憶庫/ — 長期記憶，跨專案
  memoryVault,
  /// /圖書館/ — 洞察卡片，跨專案
  library;

  String get dirName {
    switch (this) {
      case FolderCategory.projects:
        return '專案';
      case FolderCategory.memoryVault:
        return '記憶庫';
      case FolderCategory.library:
        return '圖書館';
    }
  }

  String get zhLabel {
    switch (this) {
      case FolderCategory.projects:
        return '專案';
      case FolderCategory.memoryVault:
        return '記憶庫';
      case FolderCategory.library:
        return '圖書館';
    }
  }

  static FolderCategory? tryFromDirName(String name) {
    for (final cat in FolderCategory.values) {
      if (cat.dirName == name) return cat;
    }
    return null;
  }
}

/// 專案子目錄類型
enum ProjectSubDir {
  output, // 產出/ — AI 生成的備忘錄、計畫書
  reference; // 參考/ — 使用者匯入的資料

  String get dirName {
    switch (this) {
      case ProjectSubDir.output:
        return '產出';
      case ProjectSubDir.reference:
        return '參考';
    }
  }

  String get zhLabel {
    switch (this) {
      case ProjectSubDir.output:
        return '產出';
      case ProjectSubDir.reference:
        return '參考';
    }
  }
}

// ──────────────────────────────────────────────
// MasterFolder — 使用者納入的主資料夾
// ──────────────────────────────────────────────

/// 一個被使用者納入 App 的資料夾。
///
/// 多資料夾選擇（使用者增補 #2）：使用者安裝時可選多個資料夾，
/// 不限定單一位置。每個資料夾各自有完整的 /專案/ /記憶庫/ /圖書館/ 結構。
class MasterFolder {
  /// 唯一 ID（用 path hash 生成）
  final String id;

  /// 資料夾絕對路徑
  final String path;

  /// 顯示名稱（使用者可自訂，預設取資料夾名）
  final String label;

  /// 是否為預設資料夾（App Documents Directory）
  final bool isDefault;

  /// 納入時間
  final DateTime addedAt;

  /// 最後掃描時間
  final DateTime? lastScannedAt;

  /// 是否啟用（使用者可暫停某資料夾不掃描）
  final bool enabled;

  const MasterFolder({
    required this.id,
    required this.path,
    required this.label,
    this.isDefault = false,
    required this.addedAt,
    this.lastScannedAt,
    this.enabled = true,
  });

  MasterFolder copyWith({
    String? id,
    String? path,
    String? label,
    bool? isDefault,
    DateTime? addedAt,
    DateTime? lastScannedAt,
    bool? enabled,
  }) {
    return MasterFolder(
      id: id ?? this.id,
      path: path ?? this.path,
      label: label ?? this.label,
      isDefault: isDefault ?? this.isDefault,
      addedAt: addedAt ?? this.addedAt,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'label': label,
      'isDefault': isDefault,
      'addedAt': addedAt.toIso8601String(),
      'lastScannedAt': lastScannedAt?.toIso8601String(),
      'enabled': enabled,
    };
  }

  factory MasterFolder.fromJson(Map<String, dynamic> json) {
    final addedAt = DateTime.tryParse(json['addedAt']?.toString() ?? '');
    final lastScannedAt = DateTime.tryParse(
      json['lastScannedAt']?.toString() ?? '',
    );
    return MasterFolder(
      id: json['id']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      isDefault: json['isDefault'] == true,
      addedAt: addedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      lastScannedAt: lastScannedAt,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  /// 從路徑生成 ID
  static String idForPath(String path) {
    final normalized = path.trim().toLowerCase();
    final bytes = utf8.encode(normalized);
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// 確保此資料夾有完整的檔案層目錄結構
  Future<void> ensureStructure() async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    for (final cat in FolderCategory.values) {
      final catDir = Directory('$path/${cat.dirName}');
      if (!await catDir.exists()) {
        await catDir.create(recursive: true);
      }
    }
  }

  /// 取得某分類的完整路徑
  String categoryPath(FolderCategory category) {
    return '$path/${category.dirName}';
  }

  /// 取得專案路徑
  String projectPath(String projectName) {
    return '$path/${FolderCategory.projects.dirName}/$projectName';
  }
}

// ──────────────────────────────────────────────
// ProjectMeta — 專案的 meta.json
// ──────────────────────────────────────────────

/// 專案目錄底下的 meta.json，記錄標籤、關聯、狀態。
///
/// 存放在：/專案/[name]/meta.json
class ProjectMeta {
  /// 專案名稱（= 目錄名）
  final String name;

  /// 標籤（AI 檢索用，使用者增補 #4）
  final List<String> tags;

  /// 關聯的對話 ID 列表
  final List<String> conversationIds;

  /// 關聯的專案門 ID
  final String? projectDoorId;

  /// 專案狀態
  final ProjectStatus status;

  /// 描述
  final String description;

  /// 建立時間
  final DateTime createdAt;

  /// 最後更新時間
  final DateTime updatedAt;

  const ProjectMeta({
    required this.name,
    this.tags = const [],
    this.conversationIds = const [],
    this.projectDoorId,
    this.status = ProjectStatus.active,
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
  });

  ProjectMeta copyWith({
    String? name,
    List<String>? tags,
    List<String>? conversationIds,
    String? projectDoorId,
    ProjectStatus? status,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProjectMeta(
      name: name ?? this.name,
      tags: tags ?? this.tags,
      conversationIds: conversationIds ?? this.conversationIds,
      projectDoorId: projectDoorId ?? this.projectDoorId,
      status: status ?? this.status,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'tags': tags,
      'conversationIds': conversationIds,
      'projectDoorId': projectDoorId,
      'status': status.name,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ProjectMeta.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    return ProjectMeta(
      name: json['name']?.toString() ?? '',
      tags: (json['tags'] as List?)?.map((t) => t.toString()).toList() ??
          const [],
      conversationIds: (json['conversationIds'] as List?)
              ?.map((t) => t.toString())
              .toList() ??
          const [],
      projectDoorId: json['projectDoorId'] as String?,
      status: ProjectStatus.tryFromName(json['status']?.toString()) ??
          ProjectStatus.active,
      description: json['description']?.toString() ?? '',
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// 從專案目錄讀取 meta.json
  static Future<ProjectMeta?> readFromDir(String projectDirPath) async {
    final metaFile = File('$projectDirPath/meta.json');
    if (!await metaFile.exists()) return null;
    try {
      final raw = await metaFile.readAsString();
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return ProjectMeta.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 寫入 meta.json 到專案目錄
  Future<void> writeToDir(String projectDirPath) async {
    final metaFile = File('$projectDirPath/meta.json');
    final dir = Directory(projectDirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await metaFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(toJson()),
      flush: true,
    );
  }

  /// 建立新專案的預設 meta
  factory ProjectMeta.create(String name) {
    final now = DateTime.now();
    return ProjectMeta(
      name: name,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// 專案狀態
enum ProjectStatus {
  active, // 進行中
  paused, // 暫停
  archived, // 已封存
  completed; // 已完成

  String get zhLabel {
    switch (this) {
      case ProjectStatus.active:
        return '進行中';
      case ProjectStatus.paused:
        return '暫停';
      case ProjectStatus.archived:
        return '已封存';
      case ProjectStatus.completed:
        return '已完成';
    }
  }

  static ProjectStatus? tryFromName(String? name) {
    if (name == null) return null;
    for (final s in ProjectStatus.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

// ──────────────────────────────────────────────
// FileTag — 檔案標籤系統
// ──────────────────────────────────────────────

/// 檔案標籤（使用者增補 #4：每個檔案有標籤，幫助 AI 做大腦檢索、
/// 創意檢索、檔案關聯檢索）
///
/// 標籤索引存在快取層（SharedPreferences），不修改原始檔案。
/// 標籤對應的檔案路徑指向檔案層的真實檔案。
class FileTag {
  /// 標籤名稱（小寫、去空白）
  final String name;

  /// 標籤顯示名稱
  final String label;

  /// 此標籤下的檔案路徑列表
  final List<String> filePaths;

  /// 標籤顏色（可選，UI 用）
  final String? color;

  /// 建立時間
  final DateTime createdAt;

  const FileTag({
    required this.name,
    required this.label,
    this.filePaths = const [],
    this.color,
    required this.createdAt,
  });

  FileTag copyWith({
    String? name,
    String? label,
    List<String>? filePaths,
    String? color,
    DateTime? createdAt,
  }) {
    return FileTag(
      name: name ?? this.name,
      label: label ?? this.label,
      filePaths: filePaths ?? this.filePaths,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'label': label,
      'filePaths': filePaths,
      'color': color,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory FileTag.fromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    return FileTag(
      name: json['name']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      filePaths: (json['filePaths'] as List?)
              ?.map((t) => t.toString())
              .toList() ??
          const [],
      color: json['color'] as String?,
      createdAt: createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// 正規化標籤名稱（小寫、去前後空白）
  static String normalizeName(String input) {
    return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }
}

// ──────────────────────────────────────────────
// MasterFolderTree — 樹狀目錄結構（掃描結果）
// ──────────────────────────────────────────────

/// 掃描主資料夾後得到的樹狀結構（使用者增補 #3：樹狀結構管理）。
///
/// 不持久化——每次掃描時重建。UI 用此結構顯示統一樹狀圖。
class MasterFolderTree {
  final MasterFolder folder;
  final List<TreeNode> roots;

  const MasterFolderTree({
    required this.folder,
    required this.roots,
  });
}

/// 樹狀結構節點
class TreeNode {
  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final List<TreeNode> children;
  final FolderCategory? category;

  const TreeNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.sizeBytes = 0,
    this.modifiedAt,
    this.children = const [],
    this.category,
  });

  /// 遞迴計算總大小
  int get totalSize {
    if (!isDirectory) return sizeBytes;
    return children.fold(0, (sum, child) => sum + child.totalSize);
  }

  /// 遞迴計算檔案數
  int get fileCount {
    if (!isDirectory) return 1;
    return children.fold(0, (sum, child) => sum + child.fileCount);
  }
}
