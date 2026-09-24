// causal_fork_test.dart
// [因果引擎 L4 2026-09-12] 狀態分叉——diff 與報告格式驗證
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/causal/causal_fork_service.dart';

void main() {
  group('L4 狀態分叉', () {
    test('run：快照→干預→diff→還原→記帳（完整鏈）', () async {
      // 模擬世界
      var world = <String, dynamic>{
        'nodes': [
          {'id': 'n1', 'type': 'input'},
        ],
        'connections': <Map<String, dynamic>>[],
      };
      final fork = CausalForkService.instance;
      final fd = await fork.run(
        intervention: 'do: addNode(text, 300, 400)',
        baselineDescription: '如果在這裡加一個節點會怎樣',
        getState: () async => Map<String, dynamic>.from(world),
        intervene: () async {
          // A 線：加節點
          world = <String, dynamic>{
            ...world,
            'nodes': [
              ...world['nodes'] as List,
              {'id': 'n2', 'type': 'text'},
            ],
          };
          return world;
        },
        restore: (before) async {
          // 還原：世界回到快照
          world = Map<String, dynamic>.from(before);
        },
      );

      // diff 應抓到 +1 節點
      expect(fd.diverged, isTrue);
      expect(fd.diffLines.any((l) => l.contains('nodes +1')), isTrue);
      // 世界已還原（不留殭屍）
      expect((world['nodes'] as List).length, 1);
      // 報告帶等級 3 標示
      expect(fd.report, contains('反事實分叉報告'));
      expect(fd.report, contains('等級：3 反事實模擬'));
    });

    test('無差異干預 → diverged=false + 誠實報告「無差異」', () async {
      final fork = CausalForkService.instance;
      final world = {'nodes': [{'id': 'n1'}]};
      final fd = await fork.run(
        intervention: 'do: noop',
        baselineDescription: '不做任何事',
        getState: () async => world,
        intervene: () async => world, // A 線什麼都沒變
        restore: (_) async {},
      );
      expect(fd.diverged, isFalse);
      expect(fd.report, contains('無（干預未產生可觀測變化）'));
    });

    test('內容變更也被 diff 抓到（~N 內容變更）', () async {
      final fork = CausalForkService.instance;
      final fd = await fork.run(
        intervention: 'do: update node content',
        baselineDescription: '改節點內容',
        getState: () async => {
          'nodes': [{'id': 'n1', 'content': '舊'}]
        },
        intervene: () async => {
          'nodes': [{'id': 'n1', 'content': '新'}]
        },
        restore: (_) async {},
      );
      expect(fd.diffLines.any((l) => l.contains('~1')), isTrue);
    });
  });
}
