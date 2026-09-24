// schedule_engine_test.dart
// ScheduleEngine 邏輯測試 — shouldFire / matchCron / calculateNextFire

import 'package:bridge_app/services/semicanvas/schedule_engine.dart';
import 'package:bridge_app/services/semicanvas/workflow_executor.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// 測試用 ScheduleEngine subclass — 不啟動 Timer，只測純邏輯方法
///
/// EntityGraphService 用真實實例但測試不會呼叫到它的方法
/// （只測 shouldFire / matchCron / calculateNextFire 純邏輯）。
class _TestableScheduleEngine extends ScheduleEngine {
  _TestableScheduleEngine()
      : super(
          entityGraph: EntityGraphService(
            memoryStore: MemoryStore(),
            doorStore: ProjectDoorStore(),
            assetStore: DigitalAssetRegistryStore(),
          ),
          nodeExecutor: (_, _, _, _) async =>
              const NodeExecutionResult(nodeId: '', success: true),
        );

  bool testShouldFire(Map<String, dynamic> params, DateTime now) =>
      shouldFire(params, now, 'test-node');

  DateTime? testNextFire(Map<String, dynamic> params, DateTime now) =>
      calculateNextFire(params, now);
}

void main() {
  late _TestableScheduleEngine engine;

  setUp(() {
    engine = _TestableScheduleEngine();
  });

  // ═══════════════════════════════════════════════════════
  //  shouldFire — daily
  // ═══════════════════════════════════════════════════════
  group('shouldFire - daily', () {
    test('時間吻合時應觸發', () {
      final params = {'scheduleType': 'daily', 'time': '09:00'};
      final now = DateTime(2026, 7, 24, 9, 0);
      expect(engine.testShouldFire(params, now), isTrue);
    });

    test('時間不吻合時不觸發', () {
      final params = {'scheduleType': 'daily', 'time': '09:00'};
      final now = DateTime(2026, 7, 24, 9, 1);
      expect(engine.testShouldFire(params, now), isFalse);
    });

    test('小時不同不觸發', () {
      final params = {'scheduleType': 'daily', 'time': '09:00'};
      final now = DateTime(2026, 7, 24, 10, 0);
      expect(engine.testShouldFire(params, now), isFalse);
    });

    test('預設時間為 09:00', () {
      final params = {'scheduleType': 'daily'};
      final now = DateTime(2026, 7, 24, 9, 0);
      expect(engine.testShouldFire(params, now), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  shouldFire — weekly
  // ═══════════════════════════════════════════════════════
  group('shouldFire - weekly', () {
    test('星期 + 時間吻合時觸發（週一=1）', () {
      final params = {'scheduleType': 'weekly', 'time': '08:00', 'weekday': 1};
      // 2026-07-27 是週一
      final now = DateTime(2026, 7, 27, 8, 0);
      expect(engine.testShouldFire(params, now), isTrue);
    });

    test('星期不吻合不觸發', () {
      final params = {'scheduleType': 'weekly', 'time': '08:00', 'weekday': 1};
      // 2026-07-28 是週二
      final now = DateTime(2026, 7, 28, 8, 0);
      expect(engine.testShouldFire(params, now), isFalse);
    });

    test('週日=7', () {
      final params = {'scheduleType': 'weekly', 'time': '22:00', 'weekday': 7};
      // 2026-07-26 是週日
      final now = DateTime(2026, 7, 26, 22, 0);
      expect(engine.testShouldFire(params, now), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  shouldFire — monthly
  // ═══════════════════════════════════════════════════════
  group('shouldFire - monthly', () {
    test('日期 + 時間吻合時觸發', () {
      final params = {
        'scheduleType': 'monthly',
        'time': '09:00',
        'dayOfMonth': 15
      };
      final now = DateTime(2026, 7, 15, 9, 0);
      expect(engine.testShouldFire(params, now), isTrue);
    });

    test('日期不吻合不觸發', () {
      final params = {
        'scheduleType': 'monthly',
        'time': '09:00',
        'dayOfMonth': 15
      };
      final now = DateTime(2026, 7, 14, 9, 0);
      expect(engine.testShouldFire(params, now), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  shouldFire — once
  // ═══════════════════════════════════════════════════════
  group('shouldFire - once', () {
    test('日期 + 時間吻合時觸發', () {
      final params = {
        'scheduleType': 'once',
        'time': '14:30',
        'date': '2026-07-28'
      };
      final now = DateTime(2026, 7, 28, 14, 30);
      expect(engine.testShouldFire(params, now), isTrue);
    });

    test('日期過了不觸發', () {
      final params = {
        'scheduleType': 'once',
        'time': '14:30',
        'date': '2026-07-28'
      };
      final now = DateTime(2026, 7, 29, 14, 30);
      expect(engine.testShouldFire(params, now), isFalse);
    });

    test('空日期不觸發', () {
      final params = {'scheduleType': 'once', 'time': '14:30', 'date': ''};
      final now = DateTime(2026, 7, 28, 14, 30);
      expect(engine.testShouldFire(params, now), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  shouldFire — cron
  // ═══════════════════════════════════════════════════════
  group('shouldFire - cron', () {
    test('每天 09:00 = 0 9 * * *', () {
      final params = {
        'scheduleType': 'cron',
        'cronExpr': '0 9 * * *',
      };
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 9, 0)), isTrue);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 9, 1)), isFalse);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 0)), isFalse);
    });

    test('盤中每分鐘 = * 9-13 * * 1-5', () {
      final params = {
        'scheduleType': 'cron',
        'cronExpr': '* 9-13 * * 1-5',
      };
      // 週一 09:30
      expect(engine.testShouldFire(params, DateTime(2026, 7, 27, 9, 30)), isTrue);
      // 週一 14:00（超出範圍）
      expect(engine.testShouldFire(params, DateTime(2026, 7, 27, 14, 0)), isFalse);
      // 週六 10:00（週末不跑）
      expect(engine.testShouldFire(params, DateTime(2026, 7, 25, 10, 0)), isFalse);
    });

    test('每 15 分鐘 = */15 * * * *', () {
      final params = {
        'scheduleType': 'cron',
        'cronExpr': '*/15 * * * *',
      };
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 0)), isTrue);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 15)), isTrue);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 30)), isTrue);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 7)), isFalse);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 45)), isTrue);
    });

    test('列表語法 = 0,30 * * * *', () {
      final params = {
        'scheduleType': 'cron',
        'cronExpr': '0,30 * * * *',
      };
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 0)), isTrue);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 30)), isTrue);
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 15)), isFalse);
    });

    test('空 cronExpr 不觸發', () {
      final params = {
        'scheduleType': 'cron',
        'cronExpr': '',
      };
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 0)), isFalse);
    });

    test('格式錯誤不觸發', () {
      final params = {
        'scheduleType': 'cron',
        'cronExpr': 'not a cron',
      };
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 10, 0)), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  shouldFire — 邊界
  // ═══════════════════════════════════════════════════════
  group('shouldFire - 邊界情況', () {
    test('無效時間格式不觸發', () {
      final params = {'scheduleType': 'daily', 'time': 'invalid'};
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 9, 0)), isFalse);
    });

    test('未知 scheduleType 不觸發', () {
      final params = {'scheduleType': 'hourly', 'time': '09:00'};
      expect(engine.testShouldFire(params, DateTime(2026, 7, 24, 9, 0)), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  matchCron — 直接測試
  // ═══════════════════════════════════════════════════════
  group('matchCron', () {
    test('萬用字元 * * * * * 永遠匹配', () {
      expect(engine.matchCron('* * * * *', DateTime(2026, 7, 24, 14, 30)), isTrue);
    });

    test('週末 = * * * * 0,6', () {
      // 2026-07-25 週六
      expect(engine.matchCron('* * * * 0,6', DateTime(2026, 7, 25, 12, 0)), isTrue);
      // 2026-07-26 週日
      expect(engine.matchCron('* * * * 0,6', DateTime(2026, 7, 26, 12, 0)), isTrue);
      // 2026-07-27 週一
      expect(engine.matchCron('* * * * 0,6', DateTime(2026, 7, 27, 12, 0)), isFalse);
    });

    test('欄位數不足不匹配', () {
      expect(engine.matchCron('* * *', DateTime(2026, 7, 24, 12, 0)), isFalse);
    });

    test('範圍語法 9-17', () {
      expect(engine.matchCron('0 9-17 * * *', DateTime(2026, 7, 24, 12, 0)), isTrue);
      expect(engine.matchCron('0 9-17 * * *', DateTime(2026, 7, 24, 18, 0)), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  calculateNextFire
  // ═══════════════════════════════════════════════════════
  group('calculateNextFire', () {
    test('daily — 今天還沒到', () {
      final params = {'scheduleType': 'daily', 'time': '15:00'};
      final now = DateTime(2026, 7, 24, 10, 0);
      final next = engine.testNextFire(params, now);
      expect(next, DateTime(2026, 7, 24, 15, 0));
    });

    test('daily — 今天過了，明天', () {
      final params = {'scheduleType': 'daily', 'time': '09:00'};
      final now = DateTime(2026, 7, 24, 15, 0);
      final next = engine.testNextFire(params, now);
      expect(next, DateTime(2026, 7, 25, 9, 0));
    });

    test('weekly — 下一次週三', () {
      final params = {'scheduleType': 'weekly', 'time': '08:00', 'weekday': 3};
      // 2026-07-24 是週五
      final now = DateTime(2026, 7, 24, 10, 0);
      final next = engine.testNextFire(params, now);
      // 下週三是 2026-07-29
      expect(next, DateTime(2026, 7, 29, 8, 0));
    });

    test('monthly — 下個月', () {
      final params = {
        'scheduleType': 'monthly',
        'time': '09:00',
        'dayOfMonth': 1
      };
      final now = DateTime(2026, 7, 15, 10, 0);
      final next = engine.testNextFire(params, now);
      expect(next, DateTime(2026, 8, 1, 9, 0));
    });

    test('once — 固定日期', () {
      final params = {
        'scheduleType': 'once',
        'time': '14:30',
        'date': '2026-08-01'
      };
      final now = DateTime(2026, 7, 24, 10, 0);
      final next = engine.testNextFire(params, now);
      expect(next, DateTime(2026, 8, 1, 14, 30));
    });
  });
}
