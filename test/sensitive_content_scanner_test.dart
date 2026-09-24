// sensitive_content_scanner_test.dart
// [A2 2026-09-14] 大搬家敏感掃描器——單元測試
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/hermes_migration_service.dart';

void main() {
  group('SensitiveContentScanner [A2]', () {
    test('乾淨文字 → isClean', () {
      const text = '鹿角蕨今天澆水了，D14 評估正常。';
      final f = SensitiveContentScanner.scanText(text);
      expect(f.isClean, isTrue);
      expect(f.hasRedactedMarkers, isFalse);
    });

    test('偵測 sk- API key', () {
      const text = '我的金鑰是 sk-abc123def456ghi789jkl012 別外流';
      final f = SensitiveContentScanner.scanText(text);
      expect(f.apiKeyHits, isNotEmpty);
      expect(f.isClean, isFalse);
    });

    test('偵測 GitHub token (ghp_)', () {
      const text = 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ1234 貼在對話裡過';
      final f = SensitiveContentScanner.scanText(text);
      expect(f.apiKeyHits.length, 1);
    });

    test('偵測 AWS AKIA', () {
      const text = 'AWS_KEY=AKIAIOSFODNN7EXAMPLE';
      final f = SensitiveContentScanner.scanText(text);
      expect(f.apiKeyHits.length, 1);
    });

    test('偵測疑似身分證字號', () {
      const text = '他的證號是 A123456789 拜託保密';
      final f = SensitiveContentScanner.scanText(text);
      expect(f.idHits.length, 1);
    });

    test('[REDACTED] 標記被辨識（已清除的歷史）', () {
      const text = '之前的 key 已換成 [REDACTED]';
      final f = SensitiveContentScanner.scanText(text);
      expect(f.hasRedactedMarkers, isTrue);
      // redacted 不算 dirty——已清除
      expect(f.isClean, isTrue);
    });

    test('短 sk- 前綴不誤報（<16 chars）', () {
      const text = 'sk-too-short 不是金鑰';
      final f = SensitiveContentScanner.scanText(text);
      expect(f.apiKeyHits, isEmpty);
    });
  });
}
