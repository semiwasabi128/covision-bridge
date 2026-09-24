import 'package:bridge_app/services/managed_folder_rule_namer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ManagedFolderRuleNamer', () {
    test('turns category counts into semantic user-facing rule names', () {
      final title = const ManagedFolderRuleNamer().title(
        folderLabel: 'Downloads',
        categorySummary: '其他 9、文件 7、圖片 4、程式碼 1',
      );

      expect(title, 'Downloads：文件、圖片與程式碼整理規則');
      expect(title, isNot(contains('9')));
      expect(title, isNot(contains('1782')));
    });

    test('names imported rules plainly without leaking file names', () {
      final title = const ManagedFolderRuleNamer().title(
        folderLabel: '專案素材',
        categorySummary: '圖片 12、影片 3',
        source: 'imported',
      );

      expect(title, '專案素材：匯入的圖片與影片整理規則');
      expect(title, isNot(contains('.md')));
      expect(title, isNot(contains('rule')));
    });

    test('falls back to general files when no categories are known', () {
      final title = const ManagedFolderRuleNamer().title(
        folderLabel: '收件匣',
        categorySummary: '尚無分類',
      );

      expect(title, '收件匣：一般檔案整理規則');
    });
  });
}
