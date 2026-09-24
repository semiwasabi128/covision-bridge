import 'package:bridge_app/services/desktop_organize_report_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DesktopOrganizeReportBuilder', () {
    test('uses real scan samples and does not invent sample file names', () {
      final report = const DesktopOrganizeReportBuilder().build({
        'kind': 'desktop_file_plan',
        'rootPath': '/Users/test/Downloads',
        'executed': false,
        'fileCount': 7,
        'folderCount': 2,
        'plannedFolderCount': 3,
        'plannedMoveCount': 5,
        'skippedCount': 1,
        'categoryCounts': {'圖片': 2, '文件': 1, '程式碼': 1},
        'samples': [
          {
            'kind': '文件',
            'name': 'brave_key.rtf',
            'path': '/Users/test/Downloads/brave_key.rtf',
          },
          {
            'kind': '圖片',
            'name': 'ghost_on_base_v7.png',
            'path': '/Users/test/Downloads/ghost_on_base_v7.png',
          },
        ],
        'suggestions': ['建立圖片分類資料夾。', '建立文件分類資料夾。'],
      });

      expect(report, contains('資料來源：Bridge Desktop 實際掃描資料。'));
      expect(report, contains('產出方式：本地確定性報告產生器'));
      expect(report, contains('brave_key.rtf'));
      expect(report, contains('ghost_on_base_v7.png'));
      expect(report, contains('/Users/test/Downloads/brave_key.rtf'));

      expect(report, isNot(contains('report_2026.pdf')));
      expect(report, isNot(contains('photo_backup.jpg')));
      expect(report, isNot(contains('script_main.py')));
      expect(report, isNot(contains('archive.zip')));
      expect(report, isNot(contains('readme.txt')));
    });

    test(
      'records executed organize evidence without asking a provider to write',
      () {
        final report = const DesktopOrganizeReportBuilder().build({
          'rootPath': '/Users/test/Downloads',
          'executed': true,
          'fileCount': 22,
          'folderCount': 0,
          'createdFolderCount': 4,
          'movedCount': 13,
          'skippedCount': 9,
          'recordPath': '/Users/test/Downloads/Bridge整理紀錄.md',
          'categoryCounts': {'其他': 9, '文件': 7, '圖片': 4, '壓縮檔': 1, '程式碼': 1},
          'samples': [
            {
              'kind': '其他',
              'name': '.DS_Store',
              'path': '/Users/test/Downloads/.DS_Store',
            },
          ],
        });

        expect(report, contains('已依使用者確認執行整理計畫'));
        expect(report, contains('已建立資料夾：4 個'));
        expect(report, contains('已移動檔案：13 個'));
        expect(report, contains('整理紀錄：/Users/test/Downloads/Bridge整理紀錄.md'));
        expect(report, contains('其他：9 個'));
        expect(report, contains('.DS_Store'));
      },
    );
  });
}
