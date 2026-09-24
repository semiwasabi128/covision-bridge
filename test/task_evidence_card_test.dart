import 'dart:convert';
import 'package:bridge_app/models/task_evidence.dart';
import 'package:bridge_app/screens/chat/cards/task_evidence_card.dart';
import 'package:bridge_app/theme/tier_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1x1 transparent PNG，base64 後塞進 data URI。
// 為什麼不用 Image.file + 真實檔案：檔案解碼走 real-async IO，在
// testWidgets 的 FakeAsync 沙箱內永遠不完成，懸空 image stream 會把
// 同檔後續測試的 teardown 卡死（Bad state: Cannot close sink while
// adding stream）——本檔曾經的 hang 根因。data URI 走 Image.memory，
// 無檔案 IO，安全。
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
    'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Future<void> _pumpHost(WidgetTester tester, Widget child) async {
  final tierTheme = await loadDefaultTierTheme();
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark().copyWith(extensions: [tierTheme]),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('已完成的 image card 顯示縮圖與開啟按鈕', (tester) async {
    final evidence = TaskEvidence(
      id: 'img-1',
      kind: TaskEvidenceKind.image,
      outcome: TaskEvidenceOutcome.completed,
      headline: '已生成 1 張圖片',
      summary: 'AI 已建立圖片',
      actions: const [TaskEvidenceAction(label: '開啟', view: 'media')],
      mediaUrl: 'data:image/png;base64,$_tinyPngBase64',
    );
    var tapped = 0;
    await _pumpHost(
      tester,
      TaskEvidenceCard(evidence: evidence, onTapAction: (_) => tapped++),
    );
    expect(find.text('已生成 1 張圖片'), findsOneWidget);
    expect(find.text('AI 已建立圖片'), findsOneWidget);
    expect(find.text('開啟'), findsOneWidget);
    await tester.tap(find.text('開啟'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('失敗的 card 渲染重試動作', (tester) async {
    final evidence = TaskEvidence(
      id: 'doc-1',
      kind: TaskEvidenceKind.document,
      outcome: TaskEvidenceOutcome.failed,
      headline: '文件未建立',
      summary: '請再試一次',
      actions: const [TaskEvidenceAction(label: '預覽', view: 'document')],
    );
    await _pumpHost(
      tester,
      TaskEvidenceCard(evidence: evidence, onTapAction: (_) {}),
    );
    // 設計合約（CHAT_TASK_EVIDENCE_DESIGN.md §3.1）：失敗卡的必要動作
    // 是「重試、調整方向、查看設定」——按鈕該顯示，讓使用者能採取行動。
    expect(find.text('預覽'), findsOneWidget);
  });

  testWidgets('無 actions 也不會留下空狀態條', (tester) async {
    final evidence = TaskEvidence(
      id: 'memo-1',
      kind: TaskEvidenceKind.search,
      outcome: TaskEvidenceOutcome.completed,
      headline: '已查閱內部記憶',
      summary: '已餵回上下文',
    );
    await _pumpHost(
      tester,
      TaskEvidenceCard(evidence: evidence, onTapAction: (_) {}),
    );
    expect(find.text('已查閱內部記憶'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
