// AD-05 主資料夾 — 檔案層服務
//
// 負責：
// - 掃描主資料夾的樹狀結構（使用者增補 #3：樹狀結構管理）
// - 管理專案目錄（建立/列出/讀寫 meta.json）
// - 不掃整台電腦，以主資料夾為邊界（使用者增補 #5）

import 'dart:io';

import '../models/master_folder.dart';
import 'master_folder_store.dart';

class FileLayerService {
  final MasterFolderStore _store;

  const FileLayerService({
    MasterFolderStore? store,
  }) : _store = store ?? const MasterFolderStore();

  // ──────────────────────────────────────────────
  // 掃描
  // ──────────────────────────────────────────────

  /// 掃描單一主資料夾，回傳樹狀結構
  Future<MasterFolderTree> scanFolder(MasterFolder folder) async {
    final roots = <TreeNode>[];

    for (final cat in FolderCategory.values) {
      final catPath = folder.categoryPath(cat);
      final catDir = Directory(catPath);
      if (!await catDir.exists()) continue;

      final children = await _scanDirectory(catDir, category: cat);
      roots.add(TreeNode(
        name: cat.dirName,
        path: catPath,
        isDirectory: true,
        modifiedAt: await _modifiedAt(catDir),
        children: children,
        category: cat,
      ));
    }

    return MasterFolderTree(folder: folder, roots: roots);
  }

  /// 掃描所有啟用的主資料夾
  Future<List<MasterFolderTree>> scanAll() async {
    final folders = await _store.loadEnabled();
    final trees = <MasterFolderTree>[];
    for (final folder in folders) {
      try {
        trees.add(await scanFolder(folder));
        await _store.markScanned(folder.id);
      } catch (_) {
        // 單一資料夾掃描失敗不中斷其他
      }
    }
    return trees;
  }

  /// 遞迴掃描目錄
  Future<List<TreeNode>> _scanDirectory(
    Directory dir, {
    FolderCategory? category,
    int depth = 0,
  }) async {
    if (depth > 5) return const []; // 限制深度避免無限遞迴

    final nodes = <TreeNode>[];
    try {
      final entities = dir.listSync(followLinks: false);
      for (final entity in entities) {
        final name = entity.path.split('/').last;

        // 跳過隱藏檔案
        if (name.startsWith('.') && name != '.bridge_meta') continue;

        if (entity is Directory) {
          final children = await _scanDirectory(
            entity,
            category: category,
            depth: depth + 1,
          );
          nodes.add(TreeNode(
            name: name,
            path: entity.path,
            isDirectory: true,
            modifiedAt: await _modifiedAt(entity),
            children: children,
            category: category,
          ));
        } else if (entity is File) {
          final stat = await entity.stat();
          nodes.add(TreeNode(
            name: name,
            path: entity.path,
            isDirectory: false,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
            category: category,
          ));
        }
      }
    } catch (_) {
      // 權限不足或其他錯誤，回傳空
    }
    return nodes;
  }

  // ──────────────────────────────────────────────
  // 專案管理
  // ──────────────────────────────────────────────

  /// 建立新專案目錄
  Future<ProjectMeta> createProject(
    MasterFolder folder,
    String projectName, {
    String description = '',
    List<String> tags = const [],
    String? projectDoorId,
  }) async {
    final projectPath = folder.projectPath(projectName);
    final dir = Directory(projectPath);

    // 確保目錄存在
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 建立子目錄
    for (final sub in ProjectSubDir.values) {
      final subDir = Directory('$projectPath/${sub.dirName}');
      if (!await subDir.exists()) {
        await subDir.create(recursive: true);
      }
    }

    // 寫入 meta.json
    final now = DateTime.now();
    final meta = ProjectMeta(
      name: projectName,
      tags: tags,
      projectDoorId: projectDoorId,
      status: ProjectStatus.active,
      description: description,
      createdAt: now,
      updatedAt: now,
    );
    await meta.writeToDir(projectPath);

    return meta;
  }

  /// 列出主資料夾中所有專案
  Future<List<ProjectMeta>> listProjects(MasterFolder folder) async {
    final projectsDir =
        Directory(folder.categoryPath(FolderCategory.projects));
    if (!await projectsDir.exists()) return const [];

    final metas = <ProjectMeta>[];
    try {
      final entities = projectsDir.listSync(followLinks: false);
      for (final entity in entities) {
        if (entity is! Directory) continue;
        final meta = await ProjectMeta.readFromDir(entity.path);
        if (meta != null) {
          metas.add(meta);
        } else {
          // 沒有 meta.json 的目錄，建一個基本的
          metas.add(ProjectMeta.create(entity.path.split('/').last));
        }
      }
    } catch (_) {
      // 忽略錯誤
    }
    return metas;
  }

  /// 更新專案 meta
  Future<ProjectMeta?> updateProject(
    MasterFolder folder,
    String projectName,
    ProjectMeta Function(ProjectMeta) updater,
  ) async {
    final projectPath = folder.projectPath(projectName);
    final dir = Directory(projectPath);
    if (!await dir.exists()) return null;

    final existing =
        await ProjectMeta.readFromDir(projectPath) ??
        ProjectMeta.create(projectName);
    final updated = updater(existing).copyWith(updatedAt: DateTime.now());
    await updated.writeToDir(projectPath);
    return updated;
  }

  /// 為專案添加標籤
  Future<ProjectMeta?> addProjectTag(
    MasterFolder folder,
    String projectName,
    String tag,
  ) async {
    return updateProject(folder, projectName, (meta) {
      final normalized = FileTag.normalizeName(tag);
      final newTags = List<String>.of(meta.tags);
      if (!newTags.contains(normalized)) {
        newTags.add(normalized);
      }
      return meta.copyWith(tags: newTags);
    });
  }

  /// 綁定對話到專案
  Future<ProjectMeta?> bindConversation(
    MasterFolder folder,
    String projectName,
    String conversationId,
  ) async {
    return updateProject(folder, projectName, (meta) {
      final ids = List<String>.of(meta.conversationIds);
      if (!ids.contains(conversationId)) {
        ids.add(conversationId);
      }
      return meta.copyWith(conversationIds: ids);
    });
  }

  /// 綁定專案門
  Future<ProjectMeta?> bindProjectDoor(
    MasterFolder folder,
    String projectName,
    String doorId,
  ) async {
    return updateProject(folder, projectName, (meta) {
      return meta.copyWith(projectDoorId: doorId);
    });
  }

  // ──────────────────────────────────────────────
  // 檔案操作
  // ──────────────────────────────────────────────

  /// 將檔案寫入專案的產出目錄
  Future<String> writeToProjectOutput(
    MasterFolder folder,
    String projectName,
    String fileName,
    List<int> bytes,
  ) async {
    final outputDir =
        Directory('${folder.projectPath(projectName)}/${ProjectSubDir.output.dirName}');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    final file = File('${outputDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 將檔案寫入專案的參考目錄
  Future<String> writeToProjectReference(
    MasterFolder folder,
    String projectName,
    String fileName,
    List<int> bytes,
  ) async {
    final refDir = Directory(
        '${folder.projectPath(projectName)}/${ProjectSubDir.reference.dirName}');
    if (!await refDir.exists()) {
      await refDir.create(recursive: true);
    }
    final file = File('${refDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 寫入記憶庫
  Future<String> writeToMemoryVault(
    MasterFolder folder,
    String fileName,
    List<int> bytes,
  ) async {
    final dir = Directory(folder.categoryPath(FolderCategory.memoryVault));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 寫入圖書館
  Future<String> writeToLibrary(
    MasterFolder folder,
    String fileName,
    List<int> bytes,
  ) async {
    final dir = Directory(folder.categoryPath(FolderCategory.library));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  Future<DateTime?> _modifiedAt(Directory dir) async {
    try {
      final stat = await dir.stat();
      return stat.modified;
    } catch (_) {
      return null;
    }
  }
}
