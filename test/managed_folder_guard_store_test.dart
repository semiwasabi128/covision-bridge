import 'dart:io';

import 'package:bridge_app/services/managed_folder_guard_store.dart';
import 'package:bridge_app/services/managed_folder_rule_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ManagedFolderGuardStore', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await const ManagedFolderGuardStore().clearForTest();
    });

    test('baselines first scan and reports only later new files', () async {
      final root = await Directory.systemTemp.createTemp('bridge_guard_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File('${root.path}/already_there.md').writeAsString('old');

      final rule = ManagedFolderRule(
        id: 'rule-1',
        folderPath: root.path,
        folderLabel: '測試資料夾',
        rulePath: '${root.path}/rule.md',
        ruleTitle: '測試整理規則',
        ruleSource: 'generated',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final store = const ManagedFolderGuardStore();

      final first = await store.checkRules([rule]);
      expect(first.single.initialized, isFalse);
      expect(first.single.newFiles, isEmpty);
      expect(first.single.fileCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await File('${root.path}/fresh_image.png').writeAsString('new');

      final second = await store.checkRules([rule]);
      expect(second.single.initialized, isTrue);
      expect(second.single.newFiles, hasLength(1));
      expect(second.single.newFiles.single.name, 'fresh_image.png');
      expect(second.single.newFiles.single.kind, '圖片');
    });

    test('does not guard built-in Bridge output folders', () async {
      final root = await Directory.systemTemp.createTemp('bridge_builtin_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File('${root.path}/report.md').writeAsString('report');

      final rule = ManagedFolderRule(
        id: 'built-in',
        folderPath: root.path,
        folderLabel: '報告資料夾',
        rulePath: '${root.path}/.bridge_builtin_folder_rule.md',
        ruleTitle: 'Bridge 報告內建整理規則',
        ruleSource: 'built_in',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final checks = await const ManagedFolderGuardStore().checkRules([rule]);
      expect(checks, isEmpty);
    });
  });
}
