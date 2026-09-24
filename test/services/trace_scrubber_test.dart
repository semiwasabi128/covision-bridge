// trace_scrubber_test.dart
// [資料主權 P1 2026-09-14] 除痕服務測試
// 核心語意驗證（Blue 09-14 指正後的不可歧義版）：
// - 年齡門檻制（非時間窗）：>2hr 全刪（含昨天）、<2hr 保留（下一輪清）
// - 除痕 ≠ 刪除：掃描範圍絕不含對話/記憶/DB

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/sovereignty/trace_scrubber.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('scrub_test');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  File plant(String name, {required Duration age}) {
    final f = File('${tmpDir.path}/$name');
    f.writeAsStringSync('x' * 100);
    final t = DateTime.now().subtract(age);
    f.setLastModifiedSync(t);
    return f;
  }

  test('年齡門檻制：存在 >2hr 的暫存全部掃到（含昨天的）', () async {
    // 在 /tmp 種一老一新的截幀（scan 綁真實 /tmp 路徑，glob 定義即生產定義）
    final realOld = File('/tmp/frame_scrubtest_old.jpg');
    realOld.writeAsStringSync('test');
    realOld.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 3)));
    final yesterday = File('/tmp/frame_scrubtest_yesterday.jpg');
    yesterday.writeAsStringSync('test');
    yesterday.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 26)));
    final realNew = File('/tmp/frame_scrubtest_new.jpg');
    realNew.writeAsStringSync('test');

    try {
      final items = await TraceScrubber.instance.scan();
      final paths = items.map((e) => e.path).toList();
      expect(paths, contains(realOld.path));        // 3hr → 清
      expect(paths, contains(yesterday.path));      // 26hr（昨天）→ 一定清
      expect(paths, isNot(contains(realNew.path))); // 剛產生 → 保留
    } finally {
      realOld.deleteSync();
      yesterday.deleteSync();
      realNew.deleteSync();
    }
  });

  test('年齡門檻制：<2hr 的新檔保留（可能使用中），下輪才清', () async {
    final fresh = File('/tmp/frame_scrubtest_fresh.jpg');
    fresh.writeAsStringSync('test'); // mtime = now
    try {
      final items = await TraceScrubber.instance.scan();
      expect(items.map((e) => e.path), isNot(contains(fresh.path)));
    } finally {
      fresh.deleteSync();
    }
  });

  test('purge 真刪掃到的檔案且回傳釋放位元組', () async {
    final old = File('/tmp/vision_prompt_scrubtest.txt');
    old.writeAsStringSync('a' * 500);
    old.setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 3)));
    final items = await TraceScrubber.instance.scan();
    final mine = items.where((e) => e.path == old.path).toList();
    expect(mine, isNotEmpty);
    final freed = await TraceScrubber.instance.purge(mine);
    expect(freed, greaterThanOrEqualTo(500));
    expect(old.existsSync(), isFalse);
  });

  test('一鍵除痕零門檻：ageThreshold=Duration.zero 時剛產生的暫存也掃到（Blue 09-14 拍板）', () async {
    final fresh = File('/tmp/frame_scrubtest_zero.jpg');
    fresh.writeAsStringSync('test'); // mtime = now，零門檻下必須掃到
    try {
      final items = await TraceScrubber.instance.scan(ageThreshold: Duration.zero);
      expect(items.map((e) => e.path), contains(fresh.path));
    } finally {
      fresh.deleteSync();
    }
  });

  test('除痕範圍絕不含使用者資產（glob 白名單外的檔不掃）', () async {
    // 種一個「看起來像使用者檔案」的東西在 /tmp
    final asset = File('/tmp/my_重要筆記_scrubtest.md');
    asset.writeAsStringSync('使用者資產');
    asset.setLastModifiedSync(DateTime.now().subtract(const Duration(days: 30)));
    try {
      final items = await TraceScrubber.instance.scan();
      expect(items.map((e) => e.path), isNot(contains(asset.path)));
    } finally {
      asset.deleteSync();
    }
  });
}
