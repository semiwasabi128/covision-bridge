// Sprint 13 主資料夾模型測試
//
// 測試 MasterFolder / ProjectMeta / FileTag / FolderCategory 的
// 序列化、反序列化、目錄結構確保。

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/master_folder.dart';

void main() {
  group('FolderCategory', () {
    test('dirName returns correct Chinese names', () {
      expect(FolderCategory.projects.dirName, '專案');
      expect(FolderCategory.memoryVault.dirName, '記憶庫');
      expect(FolderCategory.library.dirName, '圖書館');
    });

    test('tryFromDirName resolves correctly', () {
      expect(FolderCategory.tryFromDirName('專案'), FolderCategory.projects);
      expect(FolderCategory.tryFromDirName('記憶庫'), FolderCategory.memoryVault);
      expect(FolderCategory.tryFromDirName('圖書館'), FolderCategory.library);
      expect(FolderCategory.tryFromDirName('unknown'), isNull);
    });
  });

  group('ProjectStatus', () {
    test('tryFromName resolves correctly', () {
      expect(ProjectStatus.tryFromName('active'), ProjectStatus.active);
      expect(ProjectStatus.tryFromName('archived'), ProjectStatus.archived);
      expect(ProjectStatus.tryFromName('nonexistent'), isNull);
      expect(ProjectStatus.tryFromName(null), isNull);
    });

    test('zhLabel returns Chinese', () {
      expect(ProjectStatus.active.zhLabel, '進行中');
      expect(ProjectStatus.completed.zhLabel, '已完成');
    });
  });

  group('MasterFolder', () {
    test('idForPath generates stable IDs', () {
      final id1 = MasterFolder.idForPath('/Users/test/Documents/BridgeHome');
      final id2 = MasterFolder.idForPath('/Users/test/Documents/BridgeHome');
      expect(id1, id2);
      expect(id1, isNotEmpty);
    });

    test('idForPath differs for different paths', () {
      final id1 = MasterFolder.idForPath('/path/A');
      final id2 = MasterFolder.idForPath('/path/B');
      expect(id1, isNot(id2));
    });

    test('toJson / fromJson roundtrip', () {
      final now = DateTime(2026, 7, 8, 10, 30);
      final folder = MasterFolder(
        id: 'test-id',
        path: '/test/path',
        label: '測試資料夾',
        isDefault: false,
        addedAt: now,
        enabled: true,
      );
      final json = folder.toJson();
      final restored = MasterFolder.fromJson(json);

      expect(restored.id, folder.id);
      expect(restored.path, folder.path);
      expect(restored.label, folder.label);
      expect(restored.isDefault, folder.isDefault);
      expect(restored.addedAt, folder.addedAt);
      expect(restored.enabled, folder.enabled);
    });

    test('fromJson handles missing fields with defaults', () {
      final restored = MasterFolder.fromJson({});
      expect(restored.id, '');
      expect(restored.path, '');
      expect(restored.label, '');
      expect(restored.isDefault, false);
      expect(restored.enabled, true);
    });

    test('copyWith updates fields correctly', () {
      final folder = MasterFolder(
        id: 'test-id',
        path: '/test/path',
        label: '原標籤',
        isDefault: false,
        addedAt: DateTime.now(),
        enabled: true,
      );
      final updated = folder.copyWith(label: '新標籤', enabled: false);
      expect(updated.label, '新標籤');
      expect(updated.enabled, false);
      expect(updated.id, folder.id);
      expect(updated.path, folder.path);
    });

    test('categoryPath builds correct paths', () {
      final folder = MasterFolder(
        id: 'test-id',
        path: '/test',
        label: 'Test',
        addedAt: DateTime.now(),
      );
      expect(folder.categoryPath(FolderCategory.projects), '/test/專案');
      expect(folder.categoryPath(FolderCategory.memoryVault), '/test/記憶庫');
      expect(folder.categoryPath(FolderCategory.library), '/test/圖書館');
    });

    test('projectPath builds correct path', () {
      final folder = MasterFolder(
        id: 'test-id',
        path: '/test',
        label: 'Test',
        addedAt: DateTime.now(),
      );
      expect(folder.projectPath('遊戲製作'), '/test/專案/遊戲製作');
    });
  });

  group('ProjectMeta', () {
    test('create factory sets defaults', () {
      final meta = ProjectMeta.create('測試專案');
      expect(meta.name, '測試專案');
      expect(meta.tags, isEmpty);
      expect(meta.conversationIds, isEmpty);
      expect(meta.status, ProjectStatus.active);
      expect(meta.description, isEmpty);
    });

    test('toJson / fromJson roundtrip', () {
      final now = DateTime(2026, 7, 8);
      final meta = ProjectMeta(
        name: '遊戲製作',
        tags: ['遊戲', 'Unity'],
        conversationIds: ['conv-1', 'conv-2'],
        projectDoorId: 'door-1',
        status: ProjectStatus.active,
        description: '一個遊戲專案',
        createdAt: now,
        updatedAt: now,
      );
      final json = meta.toJson();
      final restored = ProjectMeta.fromJson(json);

      expect(restored.name, meta.name);
      expect(restored.tags, meta.tags);
      expect(restored.conversationIds, meta.conversationIds);
      expect(restored.projectDoorId, meta.projectDoorId);
      expect(restored.status, meta.status);
      expect(restored.description, meta.description);
    });

    test('fromJson handles missing fields with defaults', () {
      final restored = ProjectMeta.fromJson({});
      expect(restored.name, '');
      expect(restored.tags, isEmpty);
      expect(restored.conversationIds, isEmpty);
      expect(restored.projectDoorId, isNull);
      expect(restored.status, ProjectStatus.active);
    });

    test('fromJson handles corrupt status gracefully', () {
      final restored = ProjectMeta.fromJson({'status': 'bogus_status'});
      expect(restored.status, ProjectStatus.active);
    });

    test('copyWith updates fields', () {
      final meta = ProjectMeta.create('test');
      final updated = meta.copyWith(
        tags: ['new-tag'],
        status: ProjectStatus.paused,
      );
      expect(updated.tags, ['new-tag']);
      expect(updated.status, ProjectStatus.paused);
      expect(updated.name, 'test');
    });
  });

  group('FileTag', () {
    test('normalizeName lowercases and replaces whitespace', () {
      expect(FileTag.normalizeName('My Tag Name'), 'my_tag_name');
      expect(FileTag.normalizeName('  Hello World  '), 'hello_world');
    });

    test('toJson / fromJson roundtrip', () {
      final tag = FileTag(
        name: 'unity',
        label: 'Unity',
        filePaths: ['/path/a.md', '/path/b.md'],
        color: '#FF5733',
        createdAt: DateTime(2026, 7, 8),
      );
      final json = tag.toJson();
      final restored = FileTag.fromJson(json);

      expect(restored.name, tag.name);
      expect(restored.label, tag.label);
      expect(restored.filePaths, tag.filePaths);
      expect(restored.color, tag.color);
    });

    test('fromJson handles missing fields', () {
      final restored = FileTag.fromJson({});
      expect(restored.name, '');
      expect(restored.filePaths, isEmpty);
      expect(restored.color, isNull);
    });
  });

  group('TreeNode', () {
    test('totalSize sums children recursively', () {
      final tree = TreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          TreeNode(name: 'a', path: '/root/a', isDirectory: false, sizeBytes: 100),
          TreeNode(
            name: 'sub',
            path: '/root/sub',
            isDirectory: true,
            children: [
              TreeNode(name: 'b', path: '/root/sub/b', isDirectory: false, sizeBytes: 200),
            ],
          ),
        ],
      );
      expect(tree.totalSize, 300);
    });

    test('fileCount counts files recursively', () {
      final tree = TreeNode(
        name: 'root',
        path: '/root',
        isDirectory: true,
        children: [
          TreeNode(name: 'a', path: '/root/a', isDirectory: false),
          TreeNode(
            name: 'sub',
            path: '/root/sub',
            isDirectory: true,
            children: [
              TreeNode(name: 'b', path: '/root/sub/b', isDirectory: false),
              TreeNode(name: 'c', path: '/root/sub/c', isDirectory: false),
            ],
          ),
        ],
      );
      expect(tree.fileCount, 3);
    });
  });
}
