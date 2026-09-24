import 'dart:io';

import 'package:bridge_app/models/second_brain_file_index.dart';
import 'package:bridge_app/services/second_brain_content_digest_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bridge_brain_digest_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'digests readable text files into summary, room, and keywords',
    () async {
      final file = File('${tempDir.path}/Door Decision Card.md');
      await file.writeAsString('''
# Door Decision Card

這份文件記錄主線、支線、待回流門，以及重大分支決策。
當使用者遇到能力缺口時，系統需要保存未選的門，任務完成後提醒回流。
''');

      const service = SecondBrainContentDigestService();
      final digest = await service.digestFile(
        file,
        title: 'Door Decision Card.md',
        extension: 'md',
        fallbackRoom: SecondBrainRoom.files,
      );

      expect(digest, isNotNull);
      expect(digest!.room, SecondBrainRoom.doors);
      expect(digest.summary, contains('已讀取'));
      expect(digest.summary, contains('門房間'));
      expect(digest.excerpt, contains('重大分支決策'));
      expect(digest.keywords, contains('door'));
    },
  );
}
