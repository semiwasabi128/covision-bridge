// sprint1_equivalency_test.dart
// Sprint 1 驗證測試 — 確認 pipeline.analyzeAsync() 與原 analyze() 行為完全一致
// 建立日期: 2026-07-04 by 小葵 (CEO)
//
// 核心原則：這是「無功能改動的 refactor」——
// 如果任何欄位不一致，就是剪下貼上過程中改了邏輯，必須修。

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/transurfing_brain_service.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/brain_pipeline/pipeline_result.dart';

void main() {
  const service = TransurfingBrainService();

  /// 測試用訊息集合——覆蓋各種判斷路徑。
  final testMessages = <String>[
    // 基本問候
    '你好',
    // 急迫感 + 恐懼
    '我必須趕快完成這個，不然就完了，好焦慮',
    // 比較與跟風
    '大家都說新聞說 GPT-5 很紅，我是不是該用',
    // 證明自己 + 義務
    '我應該證明自己不輸別人，對不起',
    // 平台拉力
    '我看到 discord 上的新平台很好用',
    // 注意力散亂
    '好多東西要看，一堆資訊不知道從哪裡開始',
    // 水流順暢
    '太棒了，繼續下一步',
    // 卡住
    '我不知道怎麼做，卡住了，好複雜',
    // 心腦衝突
    '我很想做音樂，但我爸說應該念資工',
    // 夥伴角色
    '繼續執行',
    // 橋樑路由
    '幫我生成一張圖片',
    // 空門
    '今天天氣不錯',
    // 活躍專案門
    '下一步',
    // 假門
    '快速致富躺著賺',
  ];

  /// 逐欄位比對 BrainReflection。
  void expectReflectionsEqual(BrainReflection a, BrainReflection b, String label) {
    expect(a.userIntent, b.userIntent, reason: '$label: userIntent mismatch');
    expect(a.attentionState, b.attentionState, reason: '$label: attentionState mismatch');
    expect(a.pendulumSignals.length, b.pendulumSignals.length, reason: '$label: pendulum count mismatch');
    for (var i = 0; i < a.pendulumSignals.length; i++) {
      expect(a.pendulumSignals[i].type, b.pendulumSignals[i].type, reason: '$label: pendulum[$i] type mismatch');
      expect(a.pendulumSignals[i].label, b.pendulumSignals[i].label, reason: '$label: pendulum[$i] label mismatch');
      expect(a.pendulumSignals[i].evidence, b.pendulumSignals[i].evidence, reason: '$label: pendulum[$i] evidence mismatch');
    }
    expect(a.importanceLevel, b.importanceLevel, reason: '$label: importanceLevel mismatch');
    expect(a.heartMindAlignment, b.heartMindAlignment, reason: '$label: heartMindAlignment mismatch');
    expect(a.fraileResonance, b.fraileResonance, reason: '$label: fraileResonance mismatch');
    expect(a.doorCandidates.length, b.doorCandidates.length, reason: '$label: doorCandidates count mismatch');
    for (var i = 0; i < a.doorCandidates.length; i++) {
      expect(a.doorCandidates[i].kind, b.doorCandidates[i].kind, reason: '$label: door[$i] kind mismatch');
      expect(a.doorCandidates[i].label, b.doorCandidates[i].label, reason: '$label: door[$i] label mismatch');
      expect(a.doorCandidates[i].reason, b.doorCandidates[i].reason, reason: '$label: door[$i] reason mismatch');
    }
    expect(a.doorDecision?.id, b.doorDecision?.id, reason: '$label: doorDecision.id mismatch');
    expect(a.doorDecision?.title, b.doorDecision?.title, reason: '$label: doorDecision.title mismatch');
    expect(a.flowState, b.flowState, reason: '$label: flowState mismatch');
    expect(a.recommendedMove, b.recommendedMove, reason: '$label: recommendedMove mismatch');
    expect(a.companionExpression.mood, b.companionExpression.mood, reason: '$label: companionMood mismatch');
    expect(a.companionExpression.action, b.companionExpression.action, reason: '$label: companionAction mismatch');
    expect(a.companionExpression.statusText, b.companionExpression.statusText, reason: '$label: companionStatusText mismatch');
    expect(a.guidance, b.guidance, reason: '$label: guidance mismatch');
  }

  group('Sprint 1 equivalency: pipeline vs original', () {
    test('plain messages (no context)', () async {
      for (final msg in testMessages) {
        final original = service.analyze(msg);
        final pipelined = await service.analyzeAsync(msg);
        expectReflectionsEqual(original, pipelined.reflection, msg);
      }
    });

    test('with activeCompanionRole', () async {
      for (final msg in ['你好', '繼續下一步', '卡住了不知道怎麼辦']) {
        final original = service.analyze(msg, activeCompanionRole: '小葵');
        final pipelined = await service.analyzeAsync(msg, activeCompanionRole: '小葵');
        expectReflectionsEqual(original, pipelined.reflection, 'role:$msg');
      }
    });

    test('with active project door context', () async {
      const ctx = DoorDecisionContext(
        activeProjectTitle: '1C Sprint 1',
      );
      for (final msg in ['下一步', '繼續', '你好']) {
        final original = service.analyze(msg, doorContext: ctx);
        final pipelined = await service.analyzeAsync(msg, doorContext: ctx);
        expectReflectionsEqual(original, pipelined.reflection, 'project:$msg');
      }
    });

    test('with pending bridge task context', () async {
      const ctx = DoorDecisionContext(
        pendingBridgeTaskTitle: '音樂生成能力',
        pendingBridgeTaskMissing: '需要設定音樂 API',
        requestedCapabilityLabel: '影片生成',
      );
      for (final msg in ['下一步', '繼續', '開始做']) {
        final original = service.analyze(msg, doorContext: ctx);
        final pipelined = await service.analyzeAsync(msg, doorContext: ctx);
        expectReflectionsEqual(original, pipelined.reflection, 'pending:$msg');
      }
    });

    test('with pending return context', () async {
      const ctx = DoorDecisionContext(
        pendingReturnLabel: '暫存的支線門',
      );
      for (final msg in ['下一步', '繼續', '完成', '回來', '回到']) {
        final original = service.analyze(msg, doorContext: ctx);
        final pipelined = await service.analyzeAsync(msg, doorContext: ctx);
        expectReflectionsEqual(original, pipelined.reflection, 'return:$msg');
      }
    });

    test('pipeline result has all 8 layer results', () async {
      final result = await service.analyzeAsync('你好');
      expect(result.layerResults.length, 8);
      expect(result.layerResults['intent'], isNotNull);
      expect(result.layerResults['attention'], isNotNull);
      expect(result.layerResults['pendulum'], isNotNull);
      expect(result.layerResults['importance'], isNotNull);
      expect(result.layerResults['heartMind'], isNotNull);
      expect(result.layerResults['fraile'], isNotNull);
      expect(result.layerResults['doorFlow'], isNotNull);
      expect(result.layerResults['actionRouter'], isNotNull);
    });

    test('pipeline result source is allRule', () async {
      final result = await service.analyzeAsync('你好');
      expect(result.source, PipelineSource.allRule);
    });

    test('pipeline result totalLatencyMs is non-negative', () async {
      final result = await service.analyzeAsync('你好');
      expect(result.totalLatencyMs, greaterThanOrEqualTo(0));
    });
  });
}
