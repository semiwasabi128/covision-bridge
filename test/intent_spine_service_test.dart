import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/models/intent_spine.dart';
import 'package:bridge_app/services/intent_spine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = IntentSpineService();

  test('treats feasibility questions as analysis before opening bridges', () {
    final spine = service.analyze(
      '如果我想要用 AI 來生成影片讓 AI agent 控制角色直播帶貨銷售商品，你覺得這可行嗎？',
    );

    expect(spine.mode, IntentSpineMode.analyze);
    expect(spine.shouldAnalyzeBeforeBridge, isTrue);
    expect(spine.shouldExecuteImmediately, isFalse);
    // [以利沙修正 2026-06-24] analysisFirst 時刻意不填執行型橋（generateVideo 等），
    // 讓使用者先分析再決定是否開通能力。
    expect(spine.suggestedBridgeTypes, isEmpty);
    expect(spine.signals, contains('使用者先要分析/判斷，不應直接開通能力'));
  });

  test('recognizes project start intent after user commits to a goal', () {
    final spine = service.analyze('好，我們就把這個 AI 直播帶貨專案做起來，請一步一步帶我完成。');

    expect(spine.mode, IntentSpineMode.project);
    expect(spine.shouldCreateOrRouteProject, isTrue);
    expect(spine.confidence, greaterThanOrEqualTo(0.8));
  });

  test('recognizes reusable asset invocation intent', () {
    final spine = service.analyze('把 SemiDAO 角色玩法引入目前直播帶貨專案。');

    expect(spine.mode, IntentSpineMode.assetReuse);
    expect(spine.shouldCheckReusableAssets, isTrue);
  });

  test('recognizes desktop file organization as executable intent', () {
    final spine = service.analyze('幫我整理桌面檔案，先列出整理計畫，不要搬移檔案。');

    expect(spine.mode, IntentSpineMode.execute);
    expect(spine.shouldExecuteImmediately, isTrue);
    expect(spine.suggestedBridgeTypes, contains(BridgeActionType.desktopFiles));
  });

  test('selects saved folder rule before opening desktop folder picker', () {
    final spine = service.analyze('整理資料夾，沿用之前保存過的整理規則。');

    expect(spine.mode, IntentSpineMode.assetReuse);
    expect(spine.shouldCheckReusableAssets, isTrue);
    expect(spine.shouldSelectManagedFolderRuleFirst, isTrue);
    expect(spine.shouldExecuteImmediately, isFalse);
    expect(spine.suggestedBridgeTypes, contains(BridgeActionType.desktopFiles));
  });

  test('does not execute when user is discussing a file observation', () {
    final spine = service.analyze('我今天在整理檔案資料時發現一個有趣的現象');

    expect(spine.mode, IntentSpineMode.analyze);
    expect(spine.shouldExecuteImmediately, isFalse);
    expect(spine.shouldAnalyzeBeforeBridge, isTrue);
    expect(spine.shouldAskClarifyingQuestion, isTrue);
    // conversationalFileTopic 過濾掉 desktopFiles，bridges 為空時走預設釐清選項。
    expect(spine.clarificationOptions, contains('先聊天釐清'));
    expect(spine.suggestedBridgeTypes, isEmpty);
  });

  test('does not execute when user asks about organizing principles', () {
    final spine = service.analyze('你平常整理資料的原則是什麼？');

    expect(spine.mode, IntentSpineMode.analyze);
    expect(spine.shouldExecuteImmediately, isFalse);
    expect(spine.shouldAnalyzeBeforeBridge, isTrue);
    expect(spine.shouldAskClarifyingQuestion, isFalse);
    // conversationalFileTopic 過濾掉 desktopFiles，不開資料夾橋。
    expect(spine.suggestedBridgeTypes, isEmpty);
  });

  test('asks a clarifying question when goal is too vague to route', () {
    final spine = service.analyze('我想做一個有趣的計畫');

    expect(spine.mode, IntentSpineMode.clarify);
    expect(spine.shouldExecuteImmediately, isFalse);
    expect(spine.shouldAskClarifyingQuestion, isTrue);
    expect(spine.clarificationOptions, contains('整理成目標'));
  });

  test('recognizes realtime lookup as executable browse intent', () {
    final spine = service.analyze('今天有什麼 AI 新聞？');

    expect(spine.mode, IntentSpineMode.execute);
    expect(spine.shouldExecuteImmediately, isTrue);
    expect(spine.shouldAnalyzeBeforeBridge, isFalse);
    expect(spine.suggestedBridgeTypes, contains(BridgeActionType.browse));
  });

  test('image only upload asks for user purpose instead of auto executing', () {
    final spine = service.analyze('', hasImage: true);

    expect(spine.mode, IntentSpineMode.clarify);
    expect(spine.shouldExecuteImmediately, isFalse);
    expect(spine.suggestedBridgeTypes, contains(BridgeActionType.vision));
  });
}
