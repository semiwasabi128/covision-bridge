// trio_m1_collab_test.dart
// [TRIO M1 2026-09-22] 三線不撞車驗收測試
//
// 劇本：
//   T1 三 session 併發跑（各帶工作畫布隔離）——零互踩
//   T2 刻意搶奪：兩線同時 acquire 同一資源——FIFO 排隊不並行
//   T3 狀態真相源：三線同時跑，status snapshot 三態正確流轉
//   T4 兵敗清場：任務失敗，租約自動釋放，下一個排隊者接手
//   T5 冪等：同狀態重複寫不觸發事件（防抖）
//   T6 誤釋保護：A 不能釋放 B 的租約
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/collab/agent_status_store.dart';
import 'package:bridge_app/services/collab/resource_lease.dart';

void main() {
  setUp(() {
    AgentStatusStore.resetForTest();
    ResourceLease.resetForTest();
  });

  group('T2/T4/T6 ResourceLease——不撞車咽喉', () {
    test('兩線同時搶同一資源：序列化，零並行', () async {
      final lease = ResourceLease.instance;
      final order = <String>[];

      // 兩個「agent」同時要 git 鎖
      final f1 = lease.acquire('git', 'agent-甲').then((_) {
        order.add('甲-拿到');
        return Future<void>.delayed(const Duration(milliseconds: 50))
            .then((_) {
          order.add('甲-釋放');
          lease.release('git', 'agent-甲');
        });
      });
      final f2 = lease.acquire('git', 'agent-乙').then((_) {
        order.add('乙-拿到');
        order.add('乙-釋放');
        lease.release('git', 'agent-乙');
      });

      await Future.wait([f1, f2]);

      // 甲先到先得，乙必須排在甲釋放之後
      expect(order.indexOf('乙-拿到'), greaterThan(order.indexOf('甲-釋放')),
          reason: '乙拿到鎖必須晚於甲釋放——否則就是並行互踩');
      expect(lease.holderOf('git'), isNull, reason: '用完歸還，不留鎖');
    });

    test('FIFO：三線排隊順序不跳號', () async {
      final lease = ResourceLease.instance;
      final done = <String>[];

      // 種子持有者
      lease.tryAcquire('build', 'seed');

      final futures = ['甲', '乙', '丙'].map((a) async {
        await lease.acquire('build', 'agent-$a');
        done.add(a);
        lease.release('build', 'agent-$a');
      });
      final all = Future.wait(futures);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      lease.release('build', 'seed');
      await all;

      expect(done, ['甲', '乙', '丙'], reason: '先到先得，不跳號不插隊');
    });

    test('兵敗清場：releaseAllOf 釋放持有的鎖並交接下一位', () async {
      final lease = ResourceLease.instance;
      lease.tryAcquire('flutter-build', 'session-dead');

      var handedOver = false;
      final f = lease.acquire('flutter-build', 'session-next').then((_) {
        handedOver = true;
        lease.release('flutter-build', 'session-next');
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handedOver, isFalse, reason: '被佔中，還拿不到');

      lease.releaseAllOf('session-dead'); // 模擬 dispatcher 兵敗清場
      await f;
      expect(handedOver, isTrue, reason: '清場後鎖自動交接給排隊者');
    });

    test('誤釋保護：A 釋放 B 的鎖被忽略', () {
      final lease = ResourceLease.instance;
      lease.tryAcquire('git', 'agent-B');
      lease.release('git', 'agent-A'); // 越權釋放
      expect(lease.holderOf('git'), 'agent-B',
          reason: 'B 的鎖不因 A 的誤釋而丟失');
    });

    test('逾時誠實失敗：LeaseTimeoutException，不死等', () async {
      final lease = ResourceLease.instance;
      lease.tryAcquire('git', 'holder-forever');
      await expectLater(
        lease.acquire('git', 'waiter',
            timeout: const Duration(milliseconds: 80)),
        throwsA(isA<LeaseTimeoutException>()),
      );
      expect(lease.queueLength('git'), 0, reason: '逾時者已從佇列移除');
    });
  });

  group('T1/T3/T5 AgentStatusStore——狀態真相源', () {
    test('三 agent 併發流轉：snapshot 全程一致', () async {
      final store = AgentStatusStore.instance;

      // 三線同時開工
      store.setLive('agent-甲', sessionId: 's1', detail: '任務甲');
      store.setLive('agent-乙', sessionId: 's2', detail: '任務乙');
      store.setLive('agent-丙', sessionId: 's3', detail: '任務丙');

      expect(store.snapshot.length, 3);
      for (final s in store.snapshot) {
        expect(s.state, AgentRunState.live);
      }

      // 甲交付、乙失敗、丙 unverifiable
      store.setExited('agent-甲', sessionId: 's1', detail: 'delivered');
      store.setExited('agent-乙', sessionId: 's2', detail: 'failed');
      store.setUnverifiable('agent-丙', sessionId: 's3');

      final byId = {
        for (final s in store.snapshot) s.agentId: s,
      };
      expect(byId['agent-甲']!.state, AgentRunState.exited);
      expect(byId['agent-乙']!.state, AgentRunState.exited);
      expect(byId['agent-丙']!.state, AgentRunState.unverifiable,
          reason: '斷線≠死亡——重啟殘留是 unverifiable 不是 exited');
    });

    test('冪等：同狀態重複寫不觸發事件', () async {
      final store = AgentStatusStore.instance;
      var events = 0;
      final sub = store.changes.listen((_) => events++);

      store.setLive('agent-甲', sessionId: 's1', detail: '同');
      store.setLive('agent-甲', sessionId: 's1', detail: '同'); // 冪等重複
      store.setLive('agent-甲', sessionId: 's1', detail: '同'); // 冪等重複
      await Future<void>.delayed(Duration.zero); // broadcast stream 非同步送達

      expect(events, 1, reason: '同狀態重複寫只觸發一次');
      sub.cancel();
    });

    test('廣播流：非 Widget 訂閱者收得到狀態變化', () async {
      final store = AgentStatusStore.instance;
      final received = <AgentStatus>[];
      final sub = store.changes.listen(received.add);

      store.setLive('agent-乙', sessionId: 's9');
      await Future<void>.delayed(Duration.zero); // broadcast stream 微任務

      expect(received.length, 1);
      expect(received.first.agentId, 'agent-乙');
      expect(received.first.state, AgentRunState.live);
      sub.cancel();
    });
  });
}
