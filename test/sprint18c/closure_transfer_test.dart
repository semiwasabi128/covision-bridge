// [Sprint 18c tests] AssetClosureService + ContextTransferService
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/models/digital_asset.dart';
import 'package:bridge_app/models/flow_step.dart';
import 'package:bridge_app/models/project_door.dart';
import 'package:bridge_app/services/asset_closure_service.dart';
import 'package:bridge_app/services/context_transfer_service.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/project_door_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AssetClosureService', () {
    final store = const ProjectDoorStore();
    final assetStore = const DigitalAssetRegistryStore();
    final closureService = const AssetClosureService();

    test('beforeTask returns suggestions for door', () async {
      // 建立門
      final door = await store.saveActive(
          ProjectDoor.create(title: '直播帶貨', sourceIntent: '我要做直播銷售'));

      // 建立資產
      await assetStore.registerAsset(
        title: '直播腳本模板',
        kind: DigitalAssetKind.scriptAsset,
        summary: '直播帶貨用的腳本模板',
        capabilities: ['直播平台橋'],
        tags: ['直播', '腳本'],
      );

      final suggestions = await closureService.beforeTask(door);
      // 應該找到匹配的資產
      expect(suggestions, isNotEmpty);
    });

    test('linkAssetToDoor adds asset to door', () async {
      final door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final asset = await assetStore.registerAsset(
        title: '測試資產',
        kind: DigitalAssetKind.projectPlaybook,
        summary: '測試用',
      );

      final updated = await closureService.linkAssetToDoor(door.id, asset.id);
      expect(updated, isNotNull);
      expect(updated!.linkedAssetIds, contains(asset.id));
    });

    test('linkAssetToStep adds asset to step', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final step = FlowStep.create(doorId: door.id, title: '步驟1');
      door = (await store.addFlowStep(door.id, step))!;

      final asset = await assetStore.registerAsset(
        title: '步驟資產',
        kind: DigitalAssetKind.codeTool,
        summary: '步驟用',
      );

      final updated = await closureService.linkAssetToStep(
          door.id, step.id, asset.id);
      expect(updated, isNotNull);
      expect(updated!.flowSteps.first.linkedAssetIds, contains(asset.id));
      expect(updated.linkedAssetIds, contains(asset.id));
    });

    test('getLinkedAssets returns full asset objects', () async {
      final door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final asset = await assetStore.registerAsset(
        title: '連結資產',
        kind: DigitalAssetKind.mediaAsset,
        summary: '媒體資產',
      );

      await closureService.linkAssetToDoor(door.id, asset.id);

      // 重新載入門
      final all = await store.loadAll();
      final updated = all.firstWhere((d) => d.id == door.id);
      final linked = await closureService.getLinkedAssets(updated);
      expect(linked.length, 1);
      expect(linked.first.title, '連結資產');
    });

    test('unlinkAsset removes from door and steps', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final step = FlowStep.create(doorId: door.id, title: '步驟1');
      door = (await store.addFlowStep(door.id, step))!;
      final asset = await assetStore.registerAsset(
        title: '要解除的資產',
        kind: DigitalAssetKind.knowledgePack,
        summary: '知識包',
      );

      // 連結到門和步驟
      await closureService.linkAssetToStep(door.id, step.id, asset.id);

      // 解除連結
      final unlinked = await closureService.unlinkAsset(door.id, asset.id);

      expect(unlinked, isNotNull);
      expect(unlinked!.linkedAssetIds, isNot(contains(asset.id)));
      expect(unlinked.flowSteps.first.linkedAssetIds, isNot(contains(asset.id)));
    });

    test('archiveStepResult creates new asset and marks step done', () async {
      var door = await store.saveActive(
          ProjectDoor.create(title: '測試門', sourceIntent: '意圖'));
      final step = FlowStep.create(doorId: door.id, title: '要完成的步驟');
      door = (await store.addFlowStep(door.id, step))!;

      final result = await closureService.archiveStepResult(
        doorId: door.id,
        stepId: step.id,
        resultSummary: '完成了某些東西',
        kind: DigitalAssetKind.documentAsset,
      );

      expect(result.newAssetId, isNotNull);
      expect(result.message, contains('已歸檔'));

      // 確認步驟已標記為完成
      final all = await store.loadAll();
      final updated = all.firstWhere((d) => d.id == door.id);
      expect(updated.flowSteps.first.isDone, isTrue);
    });
  });

  group('ContextTransferService', () {
    final store = const ProjectDoorStore();
    final transferService = const ContextTransferService();

    test('extractContext returns empty for empty conversation', () {
      final conv = Conversation.create(title: '空對話');
      final lines = transferService.extractContext(conv);
      expect(lines, isEmpty);
    });

    test('extractContext returns recent messages', () {
      final conv = Conversation.create(title: '測試對話');
      conv.messages.addAll([
        _makeMessage('user', '我要做直播帶貨'),
        _makeMessage('assistant', '好的，我來幫你規劃'),
        _makeMessage('user', '第一步是什麼？'),
      ]);
      final lines = transferService.extractContext(conv);
      expect(lines.length, 3);
      expect(lines.any((l) => l.contains('直播帶貨')), isTrue);
    });

    test('extractIntent returns user messages', () {
      final conv = Conversation.create(title: '測試對話');
      conv.messages.addAll([
        _makeMessage('assistant', '你好'),
        _makeMessage('user', '我要做 AI 角色創建'),
      ]);
      final intent = transferService.extractIntent(conv);
      expect(intent, contains('AI 角色創建'));
    });

    test('transferToDoor adds context as flow step', () async {
      final door = await store.saveActive(
          ProjectDoor.create(title: '目標門', sourceIntent: '意圖'));

      final result = await transferService.transferToDoor(
        sourceConversationId: 'conv-1',
        targetDoorId: door.id,
        contextLines: ['[使用者] 做直播', '[夥伴] 好的'],
        intentSummary: '直播帶貨專案',
      );

      expect(result.contextCount, 2);
      expect(result.message, contains('已移植'));

      // 確認門有新的 flow step
      final all = await store.loadAll();
      final updated = all.firstWhere((d) => d.id == door.id);
      expect(updated.flowSteps.length, 1);
      expect(updated.flowSteps.first.isDone, isTrue);
      expect(updated.flowSteps.first.title, contains('移植上下文'));
    });

    test('transferToNewDoor creates door and transfers', () async {
      final conv = Conversation.create(title: '來源對話');
      conv.messages.addAll([
        _makeMessage('user', '我要做音樂品牌'),
        _makeMessage('assistant', '好的，我來規劃'),
        _makeMessage('user', '需要語音橋'),
      ]);

      final result = await transferService.transferToNewDoor(
        sourceConversation: conv,
        doorTitle: '音樂品牌專案',
      );

      expect(result.contextCount, 3);
      expect(result.targetDoorId, isNotEmpty);

      // 確認門已建立
      final all = await store.loadAll();
      expect(all.any((d) => d.id == result.targetDoorId), isTrue);
    });
  });
}

Message _makeMessage(String role, String content) {
  return Message(
    id: 'msg-${DateTime.now().microsecondsSinceEpoch}',
    role: role,
    content: content,
    timestamp: DateTime.now(),
  );
}
