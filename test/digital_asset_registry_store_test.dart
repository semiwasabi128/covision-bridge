import 'package:bridge_app/models/digital_asset.dart';
import 'package:bridge_app/models/project_door.dart';
import 'package:bridge_app/models/second_brain_file_index.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/second_brain_file_index_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('registers a project door as reusable digital asset', () async {
    const registry = DigitalAssetRegistryStore();
    final door = ProjectDoor.create(
      title: 'SemiDAO',
      sourceIntent: '把創建角色玩法拉出來成為 SemiDAO 專案門。',
      requiredBridges: const ['角色資產橋', 'SemiDAO 社群資產橋'],
    );

    final asset = await registry.registerProjectDoorAsset(
      door,
      sourceConversationId: 'live-commerce',
      sourceLabel: '直播帶貨',
      contextLines: const ['AI 助理角色創建玩法可以被其他專案重用。'],
    );

    expect(asset.title, 'SemiDAO 角色創建玩法資產');
    expect(asset.kind, DigitalAssetKind.projectPlaybook);
    expect(asset.reusableByProjects, isTrue);
    expect(asset.reusableByAgents, isTrue);
    expect(asset.capabilities, contains('角色資產橋'));
    expect(asset.reusableScenes, contains('角色創建與直播角色導入'));
    expect(asset.purposeTags, contains('角色創建'));
    expect(asset.locationTags, contains('來源專案：SemiDAO'));
    expect(asset.propertyTags, contains('可組裝'));
    expect(asset.creativeTags, containsAll(['角色創作', '社群共創']));

    final saved = await registry.getAll();
    expect(saved.single.id, asset.id);

    final hits = await registry.search('直播角色 創建角色 SemiDAO');
    expect(hits, isNotEmpty);
    expect(hits.first.title, asset.title);
  });

  test('writes registered asset into second brain index', () async {
    const registry = DigitalAssetRegistryStore();
    final door = ProjectDoor.create(
      title: 'SemiDAO',
      sourceIntent: '建立角色創建玩法資產。',
      requiredBridges: const ['角色資產橋', 'SemiDAO 社群資產橋'],
    );

    final asset = await registry.registerProjectDoorAsset(door);
    final indexed = await const SecondBrainFileIndexStore().search(
      'SemiDAO 角色創建玩法',
    );

    expect(indexed, isNotEmpty);
    expect(indexed.first.path, asset.registryPath);
    expect(indexed.first.room, SecondBrainRoom.projects);
    expect(indexed.first.tags, contains('數位資產'));
    expect(indexed.first.tags, contains('角色創作'));
    expect(indexed.first.contentDigest, contains('創意標籤'));
  });

  test(
    'creative tags make reusable assets searchable by inspiration',
    () async {
      const registry = DigitalAssetRegistryStore();
      final door = ProjectDoor.create(
        title: '直播帶貨腳本玩法',
        sourceIntent: '把短影音直播帶貨腳本整理成可重用工作流。',
        requiredBridges: const ['文件產出橋', '影片生成橋'],
      );

      final asset = await registry.registerProjectDoorAsset(
        door,
        contextLines: const ['這套流程可以幫 Agent 快速組裝直播企劃與銷售腳本。'],
      );

      expect(asset.kind, DigitalAssetKind.scriptAsset);
      expect(asset.creativeTags, contains('內容商務'));
      expect(asset.creativeTags, contains('流程創意'));

      final hits = await registry.search('內容商務 銷售腳本');
      expect(hits, isNotEmpty);
      expect(hits.first.id, asset.id);
    },
  );

  test('suggests reusable assets from task intent and asset tags', () async {
    const registry = DigitalAssetRegistryStore();
    final asset = await registry.registerAsset(
      title: '直播帶貨腳本工作流',
      kind: DigitalAssetKind.workflowEngine,
      summary: '把直播帶貨目標拆成企劃、腳本、素材、上線檢查的可重用工作流。',
      sourceProjectDoorId: 'source-script-door',
      sourceLabel: '直播腳本專案',
      capabilities: const ['腳本產出橋', '文件產出橋'],
      reusableScenes: const ['直播帶貨企劃', '商品銷售腳本'],
      tags: const ['直播帶貨', '工作流', '腳本'],
      purposeTags: const ['直播企劃', '銷售腳本'],
      propertyTags: const ['任務模板', '可重用工作流'],
      creativeTags: const ['內容商務', '角色直播'],
    );

    final suggestions = await registry.suggestForTask(
      request: '我想做一個 AI 直播賣商品的企劃，先幫我規劃第一步',
      projectTitle: '直播帶貨',
      projectCapabilities: const ['商品資料橋'],
      excludeProjectDoorId: 'current-door',
    );

    expect(suggestions, isNotEmpty);
    expect(suggestions.first.asset.id, asset.id);
    expect(suggestions.first.score, greaterThanOrEqualTo(8));
    expect(
      suggestions.first.reasons.join(' '),
      anyOf(contains('目的標籤'), contains('創意標籤'), contains('可用場景')),
    );
    expect(suggestions.first.reasons.join(' '), contains('驚喜條件'));
    expect(suggestions.first.reasons.join(' '), contains('情理之中、意料之外'));
  });
}
