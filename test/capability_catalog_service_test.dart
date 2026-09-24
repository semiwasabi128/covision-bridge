import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/models/capability_catalog.dart';
import 'package:bridge_app/models/second_brain_file_index.dart';
import 'package:bridge_app/services/capability_catalog_service.dart';
import 'package:bridge_app/services/capability_health_service.dart';
import 'package:bridge_app/services/second_brain_file_index_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CapabilityCatalogService().clearCustomForTest();
    await const SecondBrainFileIndexStore().clear();
  });

  test('catalog exposes built-in formal bridge capabilities', () async {
    final service = CapabilityCatalogService();
    final definitions = await service.definitions();

    expect(definitions.map((item) => item.id), contains('browse-news'));
    expect(definitions.map((item) => item.id), contains('vision'));
    expect(definitions.map((item) => item.id), contains('image-generation'));
    expect(definitions.map((item) => item.id), contains('music-generation'));
    expect(definitions.map((item) => item.id), contains('desktop-files'));
    expect(definitions.map((item) => item.id), contains('custom-bridge'));
  });

  test(
    'brain skill registry recommends matching bridge for user request',
    () async {
      final service = CapabilityCatalogService(
        healthService: _FakeCapabilityHealthService(),
      );
      final registry = await service.buildBrainSkillRegistry('請生成一段讀書用的配樂');

      expect(registry.recommendations, isNotEmpty);
      expect(
        registry.recommendations.first.capability.definition.kind,
        CapabilityKind.music,
      );
      expect(registry.summary, contains('音樂生成橋'));
    },
  );

  test(
    'custom bridge persists and writes to second brain Bridges room',
    () async {
      final service = CapabilityCatalogService();
      final created = await service.registerCustomCapability(
        name: '香氛生成橋',
        description: '依照情緒與場景生成香氛配方。',
        triggerPhrases: const ['香氛', '氣味', '芳療'],
        providers: const ['Aroma API'],
      );

      final definitions = await service.definitions();
      expect(definitions.map((item) => item.id), contains(created.id));

      final indexed = await const SecondBrainFileIndexStore().search('香氛 芳療');
      expect(indexed, isNotEmpty);
      expect(indexed.first.room, SecondBrainRoom.bridges);
      expect(indexed.first.path, 'brain://capabilities/${created.id}');
    },
  );
}

class _FakeCapabilityHealthService extends CapabilityHealthService {
  @override
  Future<List<CapabilityHealthItem>> inspect() async {
    return const [
      CapabilityHealthItem(
        type: BridgeActionType.generateMusic,
        label: '音樂生成',
        status: CapabilityHealthStatus.unsupported,
        providerLabel: 'SemiDAO Plugin',
        detail: '等待插件',
      ),
      CapabilityHealthItem(
        type: BridgeActionType.browse,
        label: '新聞與網頁搜尋',
        status: CapabilityHealthStatus.ready,
        providerLabel: 'OpenAI 網頁搜尋',
        detail: '可用',
      ),
    ];
  }
}
