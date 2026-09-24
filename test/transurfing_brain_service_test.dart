import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/transurfing_brain_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const brain = TransurfingBrainService();

  test(
    'detects attention capture from new AI services and converts to output',
    () {
      final reflection = brain.analyze(
        '我看到新聞說新的影片生成 AI 服務很強，可是我不知道怎麼用，一直看一堆介紹。',
      );

      expect(reflection.attentionState, AttentionState.captured);
      expect(reflection.recommendedMove, RecommendedMove.convertToOutput);
      expect(reflection.hasPendulumSignals, isTrue);
      expect(
        reflection.doorCandidates.map((door) => door.kind),
        contains(DoorKind.foreignDoor),
      );
      expect(reflection.guidance, contains('自己的輸出'));
    },
  );

  test('reduces importance when urgency and fear are excessive', () {
    final reflection = brain.analyze('我一定要趕快成功，不然一切都完了，我怕這次不能失敗。');

    expect(reflection.importanceLevel, ImportanceLevel.excessive);
    expect(reflection.flowState, FlowState.againstFlow);
    expect(reflection.recommendedMove, RecommendedMove.reduceImportance);
    expect(reflection.companionExpression.statusText, '先降低重要性');
  });

  test(
    'recognizes personal door through user preference and companion language',
    () {
      final reflection = brain.analyze('我很喜歡自己的 Agent 夥伴可以依照我的需求和我的喜好幫我創作。');

      expect(reflection.fraileResonance, FraileResonance.strong);
      expect(
        reflection.doorCandidates.map((door) => door.kind),
        contains(DoorKind.ownDoor),
      );
      expect(reflection.recommendedMove, RecommendedMove.answerDirectly);
    },
  );

  test('continues current transfer chain when user asks for next step', () {
    final reflection = brain.analyze('很好，繼續下一步，開始做目前這一環。');

    expect(reflection.flowState, FlowState.withFlow);
    expect(reflection.recommendedMove, RecommendedMove.takeNextAction);
    expect(
      reflection.doorCandidates.map((door) => door.kind),
      contains(DoorKind.currentLink),
    );
    expect(reflection.companionExpression.statusText, contains('下一環'));
  });

  test('creates a door decision when message presents mainline and branch', () {
    final reflection = brain.analyze(
      '這是另一個比較大的分支。如果先把它完成，你會引導我回到主線嗎？或者先回到主線流程完成後再回來補足？你建議走哪一步？',
    );

    expect(reflection.doorDecision, isNotNull);
    expect(reflection.doorDecision!.title, '偵測到重大分支門');
    expect(
      reflection.doorDecision!.recommendedChoice,
      DoorDecisionChoice.mainline,
    );
    expect(reflection.doorDecision!.returnPrompt, contains('adapter'));
  });

  test('classifies focused v0 polish as a flow instead of a door', () {
    final reflection = brain.analyze(
      '下一個門走：Second Brain Association Dashboard v0，這是目前細節收尾，完成後回到主線。',
      doorContext: const DoorDecisionContext(currentMainlineLabel: '完成第一階段正式橋'),
    );

    expect(reflection.doorDecision, isNotNull);
    expect(
      reflection.doorDecision!.navigationKind,
      NavigationDecisionKind.flow,
    );
    expect(reflection.doorDecision!.title, contains('水流'));
    expect(reflection.doorDecision!.summary, contains('不是需要另開'));
    expect(reflection.doorDecision!.returnPrompt, contains('完成第一階段正式橋'));
  });

  test(
    'creates contextual door decision when new capability interrupts pending task',
    () {
      final reflection = brain.analyze(
        '今天有什麼 AI 新聞，幫我查一下。',
        doorContext: const DoorDecisionContext(
          pendingBridgeTaskTitle: '開通音樂生成能力',
          pendingBridgeTaskMissing: '音樂生成 provider',
          requestedCapabilityLabel: '瀏覽網頁',
        ),
      );

      expect(reflection.doorDecision, isNotNull);
      expect(reflection.doorDecision!.title, '偵測到能力支線門');
      expect(
        reflection.doorDecision!.recommendedChoice,
        DoorDecisionChoice.mainline,
      );
      expect(reflection.doorDecision!.summary, contains('開通音樂生成能力'));
      expect(reflection.doorDecision!.summary, contains('瀏覽網頁'));
    },
  );

  test('reminds pending return door when user asks for next step', () {
    final reflection = brain.analyze(
      '很好，下一步該怎麼做？',
      doorContext: const DoorDecisionContext(
        pendingReturnLabel: '真正 adapter 分支',
      ),
    );

    expect(reflection.doorDecision, isNotNull);
    expect(reflection.doorDecision!.title, '偵測到待回流門');
    expect(reflection.doorDecision!.branchLabel, '回到待回流門');
    expect(reflection.doorDecision!.returnPrompt, contains('真正 adapter 分支'));
  });

  test('anchors judgment to active project door and flow', () {
    final reflection = brain.analyze(
      '好，我們開始動手吧，第一步要做什麼？',
      doorContext: const DoorDecisionContext(
        activeProjectTitle: 'AI 角色直播帶貨專案',
        activeProjectFlow: '目標定義',
      ),
    );

    expect(reflection.importanceLevel, ImportanceLevel.elevated);
    expect(reflection.flowState, FlowState.withFlow);
    expect(
      reflection.doorCandidates.map((door) => door.label),
      contains('AI 角色直播帶貨專案'),
    );
  });
}
