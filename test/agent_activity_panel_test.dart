import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/services/agent_activity_store.dart';
import 'package:bridge_app/widgets/agent_activity_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Finder richTextContaining(String text) {
    return find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText() == text,
      description: 'RichText with "$text"',
    );
  }

  testWidgets('AgentActivityPanel renders active stage and telemetry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AgentActivityPanel(
            stage: AgentActivityStage.routing,
            pulse: true,
            telemetry: AgentActivityTelemetry(
              messages: 7,
              chars: 1234,
              memories: 2,
              bridgeActions: 1,
              attachments: 3,
              tokens: 4567,
            ),
          ),
        ),
      ),
    );

    expect(find.text('正在選擇橋樑能力'), findsOneWidget);
    expect(find.text('判斷是否需要文件、圖片或其他能力服務。'), findsOneWidget);
    expect(find.text('路由'), findsAtLeastNWidgets(1));

    expect(richTextContaining('目前階段=路由'), findsOneWidget);
    expect(richTextContaining('對話輪次=7'), findsOneWidget);
    expect(richTextContaining('文字量=1.2k'), findsOneWidget);
    expect(richTextContaining('記憶線索=2'), findsOneWidget);
    expect(richTextContaining('橋樑行動=1'), findsOneWidget);
    expect(richTextContaining('附件=3'), findsOneWidget);
    expect(richTextContaining('用量=4.6k'), findsOneWidget);
  });

  testWidgets('AgentActivityPanel compact density renders HUD telemetry', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: AgentActivityPanel(
              stage: AgentActivityStage.bridge,
              pulse: true,
              density: AgentActivityPanelDensity.compact,
              telemetry: AgentActivityTelemetry(
                messages: 12,
                chars: 9821,
                memories: 4,
                bridgeActions: 2,
                attachments: 1,
                tokens: 3210,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('正在執行橋樑能力'), findsOneWidget);
    expect(find.text('交給能力路由器，連接合適的服務。'), findsNothing);

    expect(richTextContaining('階段=橋樑'), findsOneWidget);
    expect(richTextContaining('上下文=12'), findsOneWidget);
    expect(richTextContaining('行動=2'), findsOneWidget);
    expect(richTextContaining('用量=3.2k'), findsOneWidget);
  });

  test('AgentActivityStore accepts companion expression overrides', () {
    final store = AgentActivityStore.instance;

    store.update(
      stage: AgentActivityStage.context,
      mood: AgentCompanionMood.focused,
      action: AgentCompanionAction.standing,
    );

    expect(store.current.stage, AgentActivityStage.context);
    expect(store.current.mood, AgentCompanionMood.focused);
    expect(store.current.action, AgentCompanionAction.standing);

    store.idle();
  });
}
