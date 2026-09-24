import 'dart:io';

import 'package:bridge_app/models/second_brain_file_index.dart';
import 'package:bridge_app/services/second_brain_file_index_store.dart';
import 'package:bridge_app/services/second_brain_folder_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('bridge_brain_index_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('imports supported files into the second brain file index', () async {
    final docs = Directory('${tempDir.path}/Project Notes');
    await docs.create();
    await File('${docs.path}/第二大腦架構.md').writeAsString('六大房間與檔案索引');
    await File('${docs.path}/skip.exe').writeAsString('ignored');
    await File('${docs.path}/.hidden.md').writeAsString('hidden');

    const store = SecondBrainFileIndexStore();
    const service = SecondBrainFolderImportService(store: store);

    final result = await service.importFolder(
      tempDir.path,
      room: SecondBrainRoom.projects,
    );

    expect(result.scannedCount, 3);
    expect(result.indexedCount, 1);
    expect(result.digestedCount, 1);
    expect(result.entries.single.title, '第二大腦架構.md');
    expect(result.entries.single.room, SecondBrainRoom.projects);
    expect(result.entries.single.tags, contains('計畫房間'));
    expect(result.entries.single.contentDigest, contains('已讀取'));
    expect(result.entries.single.contentExcerpt, contains('六大房間'));

    final indexed = await store.search('第二大腦架構');
    expect(indexed, hasLength(1));
    expect(indexed.single.path, endsWith('第二大腦架構.md'));

    final contentMatch = await store.search('檔案索引');
    expect(contentMatch, hasLength(1));
  });

  test(
    'auto classifies digested files when importing into default room',
    () async {
      final docs = Directory('${tempDir.path}/Bridge Docs');
      await docs.create();
      await File(
        '${docs.path}/gateway-adapter.md',
      ).writeAsString('橋樑 adapter、Gateway、API provider 與能力開通訊號中心。');

      const store = SecondBrainFileIndexStore();
      const service = SecondBrainFolderImportService(store: store);

      final result = await service.importFolder(docs.path);

      expect(result.indexedCount, 1);
      expect(result.entries.single.room, SecondBrainRoom.bridges);
      expect(result.entries.single.tags, contains('橋樑房間'));
      expect(result.entries.single.contentDigest, contains('Gateway'));
    },
  );
}
