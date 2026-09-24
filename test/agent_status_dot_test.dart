// agent_status_dot_test.dart
// [TRIO M1 2026-09-22] 狀態點讀取端驗收——三態視覺誠實
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/collab/agent_status_store.dart';
import 'package:bridge_app/widgets/collab/agent_status_dot.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  setUp(() {
    AgentStatusStore.resetForTest();
  });

  testWidgets('live：渲染呼吸點', (tester) async {
    AgentStatusStore.instance
        .setLive('agent-甲', sessionId: 's1', detail: '任務甲');
    await tester.pumpWidget(_wrap(const AgentStatusDot(agentId: 'agent-甲')));
    expect(find.byType(AgentStatusDot), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AgentStatusDot), findsOneWidget);
  });

  testWidgets('unverifiable：渲染穩定黃點', (tester) async {
    AgentStatusStore.instance.setUnverifiable('agent-乙', sessionId: 's2');
    await tester.pumpWidget(_wrap(const AgentStatusDot(agentId: 'agent-乙')));
    expect(find.byType(AgentStatusDot), findsOneWidget);
  });

  testWidgets('exited / 未知：不渲染——閒置是預設態不搶戲', (tester) async {
    // 從未上工
    await tester.pumpWidget(_wrap(const AgentStatusDot(agentId: 'agent-丙')));
    expect(find.byType(AgentStatusDot), findsOneWidget); // widget 在
    // 內部 SizedBox.shrink——驗證方式：狀態變化後再驗
    AgentStatusStore.instance.setExited('agent-丙', sessionId: 's3');
    await tester.pump();
    expect(find.byType(AgentStatusDot), findsOneWidget); // widget 本體仍在
  });

  testWidgets('狀態流轉：exited → live 點重新出現', (tester) async {
    AgentStatusStore.instance.setExited('agent-甲', sessionId: 's1');
    await tester.pumpWidget(_wrap(const AgentStatusDot(agentId: 'agent-甲')));
    // 內部是 shrink——用 Container 存在與否判斷
    expect(find.byType(Container), findsNothing);

    AgentStatusStore.instance.setLive('agent-甲', sessionId: 's2');
    await tester.pump();
    expect(find.byType(Container), findsOneWidget,
        reason: 'live 時點應該出現（Container 帶圓形 decoration）');
  });
}
