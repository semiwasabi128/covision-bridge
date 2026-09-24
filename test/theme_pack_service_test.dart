// test/theme_pack_service_test.dart
//
// [小葵 2026-08-04] ThemePackService MVP 端到端測試

import 'package:archive/archive.dart';
import 'package:bridge_app/models/theme_pack.dart';
import 'package:bridge_app/services/theme_pack_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThemePackService', () {
    test('匯出後再匯入 → 內容一致', () async {
      final service = ThemePackService();
      final builtin = service.builtinDarkPackForTest();

      // 匯出
      final zipBytes = await service.exportToZip(builtin);

      // 匯入
      final reimported = await service.importFromZip(zipBytes);

      expect(reimported.id, builtin.id);
      expect(reimported.name, builtin.name);
      expect(reimported.author, builtin.author);
      expect(reimported.colors.length, builtin.colors.length);
      expect(
        reimported.colors['canvas']!.toARGB32(),
        builtin.colors['canvas']!.toARGB32(),
      );
      expect(
        reimported.colors['accentBlue']!.toARGB32(),
        builtin.colors['accentBlue']!.toARGB32(),
      );
    });

    test('驗證 33 個 token 完整性', () {
      final builtin = ThemePackService().builtinDarkPackForTest();
      expect(builtin.colors.length, 33);
      expect(builtin.validateDesignRules(), isEmpty);
    });

    test('字型檔案缺失時拒絕匯入', () async {
      final service = ThemePackService();
      // 造一個 manifest 宣告字型但 ZIP 內沒字型檔
      final manifestJson = '''
{
  "type": "theme-pack",
  "version": "1.0",
  "id": "test.bad",
  "name": "Bad Theme",
  "author": "Tester",
  "license": "MIT",
  "engine": { "min_bridge_version": "1.0", "target_modes": ["dark"] },
  "colors": {
    "canvas": "#07080A",
    "surface": "#101111",
    "surfaceElevated": "#1B1C1E",
    "surfaceHover": "#252829",
    "textPrimary": "#F9F9F9",
    "textSecondary": "#CECECE",
    "textTertiary": "#9C9C9D",
    "textMuted": "#6A6B6C",
    "textQuaternary": "#434345",
    "accentRed": "#FF6363",
    "accentBlue": "#55B3FF",
    "accentGreen": "#5FC992",
    "accentYellow": "#FFBC33",
    "accentPurple": "#533AFD",
    "accentNavy": "#061B31",
    "accentMagenta": "#F96BEE",
    "accentRuby": "#EA2261",
    "accentMiro": "#5B76FE",
    "borderSubtle": "#0FFFFFFF",
    "borderDefault": "#1AFFFFFF",
    "borderStrong": "#33FFFFFF",
    "surfaceGlass": "#0DFFFFFF",
    "surfaceGlassHover": "#14FFFFFF",
    "tagSuccessBg": "#0E1B12",
    "tagSuccessFg": "#B8E8CC",
    "tagErrorBg": "#1B0E0E",
    "tagErrorFg": "#FFADAD",
    "tagInfoBg": "#0E151B",
    "tagInfoFg": "#B3DCFF",
    "tagBrainBg": "#0E0A1B",
    "tagBrainFg": "#B9B9F9",
    "tagWarnBg": "#1B160E",
    "tagWarnFg": "#FFD580"
  },
  "typography": { "fontFileBase": "fonts/Inter.ttf" }
}
''';

      final archive = Archive();
      archive.addFile(ArchiveFile.bytes('manifest.json', manifestJson.codeUnits));
      final zipBytes = ZipEncoder().encode(archive)!;

      expect(
        () => service.importFromZip(zipBytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('WCAG AA 對比度檢查', () {
      final builtin = ThemePackService().builtinDarkPackForTest();
      final violations = builtin.validateDesignRules();
      expect(violations, isEmpty,
          reason: '內建 dark 主題應該通過 WCAG AA 對比度');
    });
  });
}