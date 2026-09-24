// data_path_gate_test.dart
// [資料主權 P0-a 2026-09-14] DataPathGate 的確定性驗證
// 提案：docs/specs/2026-09-14-data-sovereignty-design.md §4.1
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/sovereignty/data_path_gate.dart';
import 'dart:io';

void main() {
  group('分級判定——確定性（localhost / provider 白名單 / 未知網域）', () {
    late String dbPath;

    setUp(() {
      dbPath =
          '/tmp/sovereignty_ledger_test_${DateTime.now().millisecondsSinceEpoch}.db';
      DataPathGate.instance.resetForTest();
    });

    tearDown(() {
      DataPathGate.instance.resetForTest();
      final f = File(dbPath);
      if (f.existsSync()) f.deleteSync();
    });

    test('1) localhost → green（本地封閉迴路，資料不出這台機器）', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      gate.keyProbeOverride = (_) async => false; // 有沒有金鑰都不影響本地判定

      final grade = await gate.checkAndLog(
        url: 'http://127.0.0.1:18789/v1/chat/completions',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.mainChat,
      );
      expect(grade, DataPathGrade.green);

      final viaName = await gate.checkAndLog(
        url: 'http://localhost:11434/api/chat',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.delegate,
      );
      expect(viaName, DataPathGrade.green);
    });

    test('2) 金鑰匙已註冊金鑰的 provider 網域 → yellow', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      // 金鑰匙有金鑰的 provider（openai 是 ProviderRegistry 註冊網域）
      gate.keyProbeOverride = (id) async => id == 'openai';

      final grade = await gate.checkAndLog(
        url: 'https://api.openai.com/v1/chat/completions',
        dataClass: DataPathClass.image,
        purpose: DataPathPurpose.vision,
      );
      expect(grade, DataPathGrade.yellow);
    });

    test('2b) 註冊網域但金鑰匙無金鑰 → red（無金鑰請求本就發不出，寧攔勿漏）',
        () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      gate.keyProbeOverride = (_) async => false;

      expect(
        () => gate.checkAndLog(
          url: 'https://api.openai.com/v1/embeddings',
          dataClass: DataPathClass.text,
          purpose: DataPathPurpose.memoryExtract,
        ),
        throwsA(isA<DataPathViolationException>()),
      );
    });

    test('3) 未知網域 → throw（攔截，請求不得發出）', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      gate.keyProbeOverride = (_) async => true; // 就算渾身是金鑰，白名單外一律擋

      DataPathViolationException? caught;
      try {
        await gate.checkAndLog(
          url: 'https://evil-hardcoded-endpoint.example.com/v1/leak',
          dataClass: DataPathClass.image,
          purpose: DataPathPurpose.vision,
        );
        fail('B1 型暗管必須被當場攔下');
      } on DataPathViolationException catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      expect(caught.endpointHost,
          'evil-hardcoded-endpoint.example.com'); // 含目的網域
      expect(caught.dataClass, DataPathClass.image); // 含資料分類
      expect(caught.grade, DataPathGrade.red);
    });

    test('3b) 紅燈也記帳——被攔截的請求同樣是主權紀錄', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      gate.keyProbeOverride = (_) async => false;
      expect(gate.entryCount, 0);
      try {
        await gate.checkAndLog(
          url: 'https://sneaky.example.net/upload',
          dataClass: DataPathClass.doc,
          purpose: DataPathPurpose.delegate,
        );
      } on DataPathViolationException {
        // 預期攔截
      }
      expect(gate.entryCount, 1); // 攔了也要留痕
      final recent = await gate.recent();
      expect(recent.first.endpointHost, 'sneaky.example.net');
      expect(recent.first.grade, DataPathGrade.red);
      expect(recent.first.keySource, 'none'); // 紅燈自動標 keySource
    });

    test('解析失敗的 URL（無 host）→ red 攔截', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      expect(
        () => gate.checkAndLog(
          url: '::not a url::',
          dataClass: DataPathClass.text,
          purpose: DataPathPurpose.mainChat,
        ),
        throwsA(isA<DataPathViolationException>()),
      );
    });
  });

  group('ledger 寫入與 90 天環形清理', () {
    late String dbPath;

    setUp(() {
      dbPath =
          '/tmp/sovereignty_ledger_purge_test_${DateTime.now().millisecondsSinceEpoch}.db';
      DataPathGate.instance.resetForTest();
    });

    tearDown(() {
      DataPathGate.instance.resetForTest();
      final f = File(dbPath);
      if (f.existsSync()) f.deleteSync();
    });

    test('4) 寫入欄位完整（host/class/bytes/purpose/keySource/grade/ts）',
        () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      await gate.checkAndLog(
        url: 'http://127.0.0.1:18789/v1/chat/completions',
        dataClass: DataPathClass.audio,
        purpose: DataPathPurpose.mainChat,
        keySource: 'golden_key',
        payloadBytes: 12345,
      );
      final e = (await gate.recent()).first;
      expect(e.endpointHost, '127.0.0.1');
      expect(e.dataClass, DataPathClass.audio);
      expect(e.payloadBytes, 12345);
      expect(e.purpose, DataPathPurpose.mainChat);
      expect(e.keySource, 'golden_key'); // 明示值優先於自動推導
      expect(e.grade, DataPathGrade.green);
      expect(e.ts, isNotNull);
    });

    test('4b) 90 天環形清理——假舊資料被清除，新資料保留', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);

      // 直接塞一筆 100 天前的假舊資料（借 record 的自訂 ts）
      await gate.record(SovereigntyEntry(
        endpointHost: 'old.example.com',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.memoryExtract,
        keySource: 'none',
        grade: DataPathGrade.yellow,
        ts: DateTime.now().subtract(const Duration(days: 100)),
      ));
      await gate.record(SovereigntyEntry(
        endpointHost: 'fresh.example.com',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.mainChat,
        keySource: 'golden_key',
        grade: DataPathGrade.yellow,
        ts: DateTime.now(),
      ));

      // 手動觸發一次以「現在」為基準的清理（record 內 purge 用 entry.ts，
      // 舊資料那筆的 now 也是現在-100天 → cutoff 是 -190 天，清不掉；
      // 所以清理語意以顯式呼叫為準）
      await gate.purgeOlderThanRetention();

      final hosts = (await gate.recent(limit: 100))
          .map((e) => e.endpointHost)
          .toList();
      expect(hosts.contains('old.example.com'), isFalse, reason: '100 天前應被清除');
      expect(hosts.contains('fresh.example.com'), isTrue, reason: '今天的應保留');
    });

    test('4c) 90 天邊界內不清（89 天留、91 天清）', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: dbPath);
      await gate.record(SovereigntyEntry(
        endpointHost: 'edge89.example.com',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.review,
        keySource: 'golden_key',
        grade: DataPathGrade.yellow,
        ts: DateTime.now().subtract(const Duration(days: 89)),
      ));
      await gate.record(SovereigntyEntry(
        endpointHost: 'edge91.example.com',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.review,
        keySource: 'golden_key',
        grade: DataPathGrade.yellow,
        ts: DateTime.now().subtract(const Duration(days: 91)),
      ));
      await gate.purgeOlderThanRetention();
      final hosts = (await gate.recent(limit: 100))
          .map((e) => e.endpointHost)
          .toSet();
      expect(hosts.contains('edge89.example.com'), isTrue);
      expect(hosts.contains('edge91.example.com'), isFalse);
    });

    test('fail-open：壞路徑不 throw，留 lastError', () async {
      final gate = DataPathGate.instance;
      await gate.initialize(dbPath: '/nonexistent_dir/x/y.db');
      expect(gate.lastError, isNotNull);
      // ledger 壞了不影響判定鏈——green 照樣放行
      gate.keyProbeOverride = (_) async => false;
      final grade = await gate.checkAndLog(
        url: 'http://localhost:8080/v1',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.mainChat,
      );
      expect(grade, DataPathGrade.green);
    });
  });

  group('singleton resetForTest 模式', () {
    test('5) resetForTest 後連線與狀態歸零，可重新 initialize 不同 dbPath',
        () async {
      final gate = DataPathGate.instance;
      final p1 =
          '/tmp/sovereignty_reset_a_${DateTime.now().millisecondsSinceEpoch}.db';
      final p2 =
          '/tmp/sovereignty_reset_b_${DateTime.now().millisecondsSinceEpoch}.db';

      await gate.initialize(dbPath: p1);
      gate.keyProbeOverride = (_) async => false;
      await gate.checkAndLog(
        url: 'http://localhost:1/a',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.mainChat,
      );
      expect(gate.entryCount, 1);

      gate.resetForTest();
      expect(gate.entryCount, 0); // 連線已斷，計數歸零
      expect(gate.lastError, isNull);
      expect(gate.keyProbeOverride, isNull); // 測試接縫也清掉

      await gate.initialize(dbPath: p2); // 同一 singleton 可再初始化
      expect(gate.entryCount, 0); // 新 db 是空的
      await gate.checkAndLog(
        url: 'http://localhost:2/b',
        dataClass: DataPathClass.text,
        purpose: DataPathPurpose.review,
      );
      expect(gate.entryCount, 1);

      for (final p in [p1, p2]) {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      }
    });
  });
}
