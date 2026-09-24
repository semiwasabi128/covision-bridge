import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/digital_asset.dart';
import '../models/project_door.dart';
import '../models/second_brain_file_index.dart';
import 'second_brain_file_index_store.dart';

class DigitalAssetSuggestion {
  final DigitalAsset asset;
  final int score;
  final List<String> reasons;

  const DigitalAssetSuggestion({
    required this.asset,
    required this.score,
    required this.reasons,
  });
}

class DigitalAssetRegistryStore {
  static const String _key = 'bridge_digital_asset_registry_v0';

  final SecondBrainFileIndexStore secondBrainStore;

  const DigitalAssetRegistryStore({
    this.secondBrainStore = const SecondBrainFileIndexStore(),
  });

  Future<List<DigitalAsset>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => DigitalAsset.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.isValid)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      return const [];
    }
  }

  Future<DigitalAsset> upsert(
    DigitalAsset asset, {
    bool indexInSecondBrain = true,
  }) async {
    final normalized = _normalize(asset);
    final all = List<DigitalAsset>.of(await getAll());
    final index = all.indexWhere((item) => item.id == normalized.id);
    if (index >= 0) {
      all[index] = normalized;
    } else {
      all.add(normalized);
    }
    await _save(all);
    if (indexInSecondBrain) {
      await _upsertSecondBrainEntry(normalized);
    }
    return normalized;
  }

  Future<DigitalAsset> registerAsset({
    required String title,
    required DigitalAssetKind kind,
    required String summary,
    String id = '',
    String sourceProjectDoorId = '',
    String sourceConversationId = '',
    String sourceLabel = '',
    List<String> capabilities = const [],
    List<String> reusableScenes = const [],
    List<String> tags = const [],
    List<String> purposeTags = const [],
    List<String> locationTags = const [],
    List<String> propertyTags = const [],
    List<String> creativeTags = const [],
    bool reusableByProjects = true,
    bool reusableByAgents = true,
    bool indexInSecondBrain = false,
  }) {
    final now = DateTime.now();
    final resolvedTitle = title.trim().isEmpty ? '未命名數位資產' : title.trim();
    final resolvedId = id.trim().isEmpty
        ? 'digital-asset-${_slugFor('$resolvedTitle-${now.microsecondsSinceEpoch}')}'
        : id.trim();
    return upsert(
      DigitalAsset(
        id: resolvedId,
        title: resolvedTitle,
        kind: kind,
        summary: summary.trim(),
        sourceProjectDoorId: sourceProjectDoorId.trim(),
        sourceConversationId: sourceConversationId.trim(),
        sourceLabel: sourceLabel.trim(),
        capabilities: capabilities,
        reusableScenes: reusableScenes,
        tags: tags,
        purposeTags: purposeTags,
        locationTags: locationTags,
        propertyTags: propertyTags,
        creativeTags: creativeTags,
        createdAt: now,
        updatedAt: now,
        secondBrainEntryId: 'second-brain-$resolvedId',
        reusableByProjects: reusableByProjects,
        reusableByAgents: reusableByAgents,
      ),
      indexInSecondBrain: indexInSecondBrain,
    );
  }

  Future<DigitalAsset> registerProjectDoorAsset(
    ProjectDoor door, {
    String sourceConversationId = '',
    String sourceLabel = '',
    List<String> contextLines = const [],
  }) async {
    final now = DateTime.now();
    final kind = _kindForProjectDoor(door);
    final title = _assetTitleForProjectDoor(door, kind);
    final asset = DigitalAsset(
      id: 'digital-asset-project-door-${door.id}',
      title: title,
      kind: kind,
      summary: _summaryForProjectDoor(door, kind, contextLines),
      sourceProjectDoorId: door.id,
      sourceConversationId: sourceConversationId,
      sourceLabel: sourceLabel.trim().isEmpty ? door.title : sourceLabel.trim(),
      capabilities: door.requiredBridges,
      reusableScenes: _reusableScenesForProjectDoor(door, kind),
      tags: _tagsForProjectDoor(door, kind),
      purposeTags: _purposeTagsForProjectDoor(door, kind),
      locationTags: _locationTagsForProjectDoor(door),
      propertyTags: _propertyTagsForProjectDoor(door, kind),
      creativeTags: _creativeTagsForProjectDoor(door, kind, contextLines),
      createdAt: now,
      updatedAt: now,
      secondBrainEntryId: 'second-brain-digital-asset-${door.id}',
    );
    return upsert(asset);
  }

  Future<List<DigitalAsset>> search(String query, {int limit = 5}) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty || limit <= 0) return const [];
    final tokens = _tokensFor(trimmed);
    final scored = <({DigitalAsset asset, int score})>[];
    for (final asset in await getAll()) {
      final haystack =
          '${asset.title} ${asset.kind.label} ${asset.summary} '
                  '${asset.sourceLabel} ${asset.capabilities.join(' ')} '
                  '${asset.reusableScenes.join(' ')} ${asset.tags.join(' ')} '
                  '${asset.purposeTags.join(' ')} ${asset.locationTags.join(' ')} '
                  '${asset.propertyTags.join(' ')} ${asset.creativeTags.join(' ')}'
              .toLowerCase();
      var score = 0;
      for (final token in tokens) {
        if (haystack.contains(token)) score += token.length >= 4 ? 4 : 2;
      }
      if (asset.reusableByProjects) score += 2;
      if (asset.reusableByAgents) score += 2;
      if (score > 0) scored.add((asset: asset, score: score));
    }
    scored.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return b.asset.updatedAt.compareTo(a.asset.updatedAt);
    });
    return scored.take(limit).map((item) => item.asset).toList();
  }

  Future<List<DigitalAssetSuggestion>> suggestForTask({
    required String request,
    String projectTitle = '',
    List<String> projectCapabilities = const [],
    String excludeProjectDoorId = '',
    int limit = 3,
  }) async {
    final taskText = '$request $projectTitle ${projectCapabilities.join(' ')}'
        .trim();
    if (taskText.isEmpty || limit <= 0) return const [];
    final tokens = _expandedTokensFor(taskText.toLowerCase());
    if (tokens.isEmpty) return const [];

    final suggestions = <DigitalAssetSuggestion>[];
    for (final asset in await getAll()) {
      if (excludeProjectDoorId.trim().isNotEmpty &&
          asset.sourceProjectDoorId == excludeProjectDoorId.trim()) {
        continue;
      }
      if (!asset.reusableByProjects && !asset.reusableByAgents) continue;

      final score = _scoreAssetForTokens(asset, tokens);
      if (score.score < 8) continue;
      suggestions.add(
        DigitalAssetSuggestion(
          asset: asset,
          score: score.score,
          reasons: _prioritizedSuggestionReasons(score.reasons),
        ),
      );
    }

    suggestions.sort((a, b) {
      final scoreOrder = b.score.compareTo(a.score);
      if (scoreOrder != 0) return scoreOrder;
      return b.asset.updatedAt.compareTo(a.asset.updatedAt);
    });
    return suggestions.take(limit).toList(growable: false);
  }

  Future<void> clearForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    // 同時清除所有 workflow JSON
    final keys = prefs.getKeys().where((k) => k.startsWith('$_workflowKeyPrefix'));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }

  // ── Workflow JSON 存取 ──

  static const String _workflowKeyPrefix = 'bridge_workflow_json_';

  /// 儲存工作流 JSON（綁定到 asset ID）
  Future<void> saveWorkflowJson(String assetId, String jsonStr) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_workflowKeyPrefix$assetId', jsonStr);
  }

  /// 讀取工作流 JSON
  Future<String?> getWorkflowJson(String assetId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_workflowKeyPrefix$assetId');
  }

  Future<void> _save(List<DigitalAsset> assets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(assets.map((asset) => asset.toJson()).toList()),
    );
  }

  DigitalAsset _normalize(DigitalAsset asset) {
    final title = asset.title.trim().isEmpty ? '未命名數位資產' : asset.title.trim();
    final secondBrainEntryId = asset.secondBrainEntryId.trim().isEmpty
        ? 'second-brain-${asset.id}'
        : asset.secondBrainEntryId.trim();
    return asset.copyWith(
      title: title,
      summary: asset.summary.trim().isEmpty
          ? '${asset.kind.label}：$title'
          : asset.summary.trim(),
      capabilities: _cleanList(asset.capabilities),
      reusableScenes: _cleanList(asset.reusableScenes),
      tags: _cleanList(asset.tags),
      purposeTags: _cleanList(asset.purposeTags),
      locationTags: _cleanList(asset.locationTags),
      propertyTags: _cleanList(asset.propertyTags),
      creativeTags: _cleanList(asset.creativeTags),
      secondBrainEntryId: secondBrainEntryId,
      updatedAt: asset.updatedAt,
    );
  }

  Future<void> _upsertSecondBrainEntry(DigitalAsset asset) {
    return secondBrainStore.upsert(
      SecondBrainFileEntry(
        id: asset.secondBrainEntryId,
        title: asset.title,
        path: asset.registryPath,
        room: asset.kind.defaultRoom,
        summary: asset.summary,
        contentDigest: [
          asset.kind.label,
          '可跨專案：${asset.reusableByProjects ? '是' : '否'}',
          '可供 Agent 調用：${asset.reusableByAgents ? '是' : '否'}',
          if (asset.purposeTags.isNotEmpty)
            '目的標籤：${asset.purposeTags.take(6).join('、')}',
          if (asset.locationTags.isNotEmpty)
            '位置標籤：${asset.locationTags.take(6).join('、')}',
          if (asset.propertyTags.isNotEmpty)
            '性質標籤：${asset.propertyTags.take(6).join('、')}',
          if (asset.creativeTags.isNotEmpty)
            '創意標籤：${asset.creativeTags.take(6).join('、')}',
        ].join('。'),
        contentExcerpt:
            '能力：${asset.capabilities.take(5).join('、')}。場景：${asset.reusableScenes.take(4).join('、')}。',
        tags: [
          '數位資產',
          asset.kind.label,
          ...asset.tags,
          ...asset.purposeTags,
          ...asset.propertyTags,
          ...asset.creativeTags,
        ].take(16).toList(),
        keywords: [
          asset.title,
          asset.summary,
          asset.kind.label,
          asset.sourceLabel,
          ...asset.capabilities,
          ...asset.reusableScenes,
          ...asset.tags,
          ...asset.purposeTags,
          ...asset.locationTags,
          ...asset.propertyTags,
          ...asset.creativeTags,
        ],
        indexedAt: asset.updatedAt,
        trustScore: _secondBrainTrustScoreFor(asset),
        pinned: _shouldPinSecondBrainAsset(asset),
      ),
    );
  }

  int _secondBrainTrustScoreFor(DigitalAsset asset) {
    switch (asset.kind) {
      case DigitalAssetKind.projectPlaybook:
      case DigitalAssetKind.workflowEngine:
      case DigitalAssetKind.capabilityPlugin:
      case DigitalAssetKind.bridgeAdapter:
        return 78;
      case DigitalAssetKind.companionCharacter:
      case DigitalAssetKind.mediaAsset:
      case DigitalAssetKind.documentAsset:
      case DigitalAssetKind.scriptAsset:
      case DigitalAssetKind.codeTool:
      case DigitalAssetKind.knowledgePack:
        return 68;
    }
  }

  bool _shouldPinSecondBrainAsset(DigitalAsset asset) {
    return asset.kind == DigitalAssetKind.projectPlaybook ||
        asset.kind == DigitalAssetKind.capabilityPlugin ||
        asset.kind == DigitalAssetKind.bridgeAdapter;
  }

  DigitalAssetKind _kindForProjectDoor(ProjectDoor door) {
    final context =
        '${door.title} ${door.sourceIntent} ${door.requiredBridges.join(' ')}'
            .toLowerCase();
    if (_containsAny(context, const ['adapter', 'api', '橋 adapter'])) {
      return DigitalAssetKind.bridgeAdapter;
    }
    if (_containsAny(context, const ['腳本', 'script', '文案', '台詞'])) {
      return DigitalAssetKind.scriptAsset;
    }
    if (_containsAny(context, const ['小程式', '工具', '程式碼', 'code'])) {
      return DigitalAssetKind.codeTool;
    }
    if (_containsAny(context, const ['圖像', '圖片', '影片', '影音', '素材'])) {
      return DigitalAssetKind.mediaAsset;
    }
    if (_containsAny(context, const ['文件', '報告', '規格', '企劃書'])) {
      return DigitalAssetKind.documentAsset;
    }
    if (_containsAny(context, const ['插件', 'plugin', '能力橋', '功能橋'])) {
      return DigitalAssetKind.capabilityPlugin;
    }
    if (_containsAny(context, const ['創建角色', '創造角色', '角色資產', '召喚替身'])) {
      return DigitalAssetKind.projectPlaybook;
    }
    if (_containsAny(context, const ['工作流', '自動化', '流程', '引擎'])) {
      return DigitalAssetKind.workflowEngine;
    }
    return DigitalAssetKind.projectPlaybook;
  }

  String _assetTitleForProjectDoor(ProjectDoor door, DigitalAssetKind kind) {
    if (door.title.toLowerCase().contains('semidao')) {
      return 'SemiDAO 角色創建玩法資產';
    }
    return '${door.title} · ${kind.label}';
  }

  String _summaryForProjectDoor(
    ProjectDoor door,
    DigitalAssetKind kind,
    List<String> contextLines,
  ) {
    final context = contextLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(3)
        .join(' / ');
    final contextSuffix = context.isEmpty ? '' : '帶入上下文：$context。';
    return '${kind.label}，源自「${door.title}」專案門。${door.sourceIntent} $contextSuffix'
        .trim();
  }

  List<String> _reusableScenesForProjectDoor(
    ProjectDoor door,
    DigitalAssetKind kind,
  ) {
    final scenes = <String>{
      '跨專案引用',
      '多 Agent 共用',
      if (kind == DigitalAssetKind.projectPlaybook) '玩法模板複用',
      if (kind == DigitalAssetKind.workflowEngine) '工作流複用',
      if (kind == DigitalAssetKind.capabilityPlugin) '能力開通與插件分享',
      if (door.requiredBridges.any((item) => item.contains('角色')))
        '角色創建與直播角色導入',
      if (door.requiredBridges.any((item) => item.contains('社群')))
        'SemiDAO 社群分享',
    };
    return scenes.toList(growable: false);
  }

  List<String> _tagsForProjectDoor(ProjectDoor door, DigitalAssetKind kind) {
    final tags = <String>{
      '數位資產',
      kind.label,
      door.currentFlow,
      ...door.requiredBridges.take(4),
      if (door.title.toLowerCase().contains('semidao')) 'SemiDAO',
      if (door.sourceIntent.contains('創建角色')) '創建角色',
    };
    return tags.toList(growable: false);
  }

  List<String> _purposeTagsForProjectDoor(
    ProjectDoor door,
    DigitalAssetKind kind,
  ) {
    final tags = <String>{
      '跨專案重用',
      'Agent 可調用',
      if (kind == DigitalAssetKind.projectPlaybook) '玩法複用',
      if (kind == DigitalAssetKind.workflowEngine) '流程組裝',
      if (kind == DigitalAssetKind.bridgeAdapter) '能力橋接',
      if (kind == DigitalAssetKind.capabilityPlugin) '能力擴充',
      if (kind == DigitalAssetKind.scriptAsset) '內容生成',
      if (kind == DigitalAssetKind.codeTool) '自動化工具',
      if (door.sourceIntent.contains('創建角色')) '角色創建',
    };
    return tags.toList(growable: false);
  }

  List<String> _locationTagsForProjectDoor(ProjectDoor door) {
    final tags = <String>{
      if (door.title.trim().isNotEmpty) '來源專案：${door.title.trim()}',
      if (door.currentFlow.trim().isNotEmpty) '來源水流：${door.currentFlow.trim()}',
      'Second Brain',
      '數位資產 Registry',
    };
    return tags.toList(growable: false);
  }

  List<String> _propertyTagsForProjectDoor(
    ProjectDoor door,
    DigitalAssetKind kind,
  ) {
    final tags = <String>{
      kind.label,
      if (door.requiredBridges.isNotEmpty) '需要能力橋',
      if (door.requiredBridges.isEmpty) '不依賴外部橋',
      if (door.sourceIntent.contains('社群')) '可社群化',
      if (door.sourceIntent.contains('插件')) '可插件化',
      '可組裝',
    };
    return tags.toList(growable: false);
  }

  List<String> _creativeTagsForProjectDoor(
    ProjectDoor door,
    DigitalAssetKind kind,
    List<String> contextLines,
  ) {
    final text =
        '${door.title} ${door.sourceIntent} ${door.requiredBridges.join(' ')} ${contextLines.join(' ')}'
            .toLowerCase();
    final tags = <String>{};
    if (_containsAny(text, const ['角色', '人物', 'avatar', 'agent'])) {
      tags.add('角色創作');
    }
    if (_containsAny(text, const ['遊戲', '玩法', '抽卡', 'gamification'])) {
      tags.add('遊戲化玩法');
    }
    if (_containsAny(text, const ['直播', '帶貨', '銷售', '短影音'])) {
      tags.add('內容商務');
    }
    if (_containsAny(text, const ['社群', 'dao', 'semidao', '分享'])) {
      tags.add('社群共創');
    }
    if (_containsAny(text, const ['自動化', '工作流', '流程'])) {
      tags.add('流程創意');
    }
    if (_containsAny(text, const ['圖像', '影片', '音樂', '視覺'])) {
      tags.add('影音創作');
    }
    if (tags.isEmpty) {
      tags.add(switch (kind) {
        DigitalAssetKind.companionCharacter => '角色創作',
        DigitalAssetKind.mediaAsset => '影音創作',
        DigitalAssetKind.documentAsset => '知識整理',
        DigitalAssetKind.scriptAsset => '敘事腳本',
        DigitalAssetKind.codeTool => '工具創作',
        DigitalAssetKind.capabilityPlugin => '能力組裝',
        DigitalAssetKind.projectPlaybook => '玩法模板',
        DigitalAssetKind.workflowEngine => '流程創意',
        DigitalAssetKind.bridgeAdapter => '橋接設計',
        DigitalAssetKind.knowledgePack => '知識整理',
      });
    }
    return tags.toList(growable: false);
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any((needle) => value.contains(needle.toLowerCase()));
  }

  List<String> _tokensFor(String text) {
    return text
        .split(RegExp(r'[\s,，。！？!?:：、/\\_\-\n\r]+'))
        .map((token) => token.trim().toLowerCase())
        .where((token) => token.length >= 2)
        .toList();
  }

  Set<String> _expandedTokensFor(String text) {
    final tokens = <String>{..._tokensFor(text)};
    final expansions = <String, List<String>>{
      '直播': ['帶貨', '銷售', '短影音', '腳本', '商品'],
      '帶貨': ['直播', '銷售', '商品', '腳本'],
      '銷售': ['帶貨', '商品', '文案', '腳本'],
      '角色': ['人物', 'avatar', 'agent', '創建角色', '角色創作'],
      '創建角色': ['角色', '人物', '玩法', '角色創作'],
      '創造角色': ['角色', '人物', '玩法', '角色創作'],
      '報告': ['文件', '摘要', '知識整理'],
      '文件': ['報告', '規則', '歸檔', '知識整理'],
      '整理': ['歸檔', '規則', '資料夾', '工作流'],
      '圖片': ['圖像', '視覺', '素材', '影音創作'],
      '圖像': ['圖片', '視覺', '素材', '影音創作'],
      '影片': ['影音', '短影音', '素材', '影音創作'],
      '音樂': ['聲音', '配樂', '影音創作'],
      '工作流': ['流程', '自動化', '引擎', '流程創意'],
      '流程': ['工作流', '自動化', '引擎', '流程創意'],
      '插件': ['能力', '橋', 'adapter', '能力組裝'],
      '能力': ['插件', '橋', 'adapter', '能力組裝'],
      'semidao': ['semi dao', '社群', 'dao', '角色創作'],
      'semi': ['semidao', '社群', 'dao'],
      'dao': ['semidao', '社群', '共創'],
    };
    for (final token in List<String>.of(tokens)) {
      for (final entry in expansions.entries) {
        if (token.contains(entry.key) || entry.key.contains(token)) {
          tokens.addAll(entry.value.map((item) => item.toLowerCase()));
        }
      }
    }
    return tokens.where((token) => token.trim().length >= 2).toSet();
  }

  ({int score, List<String> reasons}) _scoreAssetForTokens(
    DigitalAsset asset,
    Set<String> tokens,
  ) {
    var score = 0;
    final reasons = <String>{};
    final matchedValues = <String, List<String>>{};

    void scoreField(String label, Iterable<String> values, int weight) {
      for (final raw in values) {
        final value = raw.trim();
        if (value.isEmpty) continue;
        final normalized = value.toLowerCase();
        final matched = tokens.any(
          (token) =>
              normalized.contains(token) ||
              (token.length >= 3 && token.contains(normalized)),
        );
        if (!matched) continue;
        score += weight;
        matchedValues.putIfAbsent(label, () => <String>[]).add(value);
        if (reasons.length < 8) reasons.add('$label：$value');
      }
    }

    scoreField('標題', [asset.title], 9);
    scoreField('目的標籤', asset.purposeTags, 8);
    scoreField('創意標籤', asset.creativeTags, 8);
    scoreField('性質標籤', asset.propertyTags, 6);
    scoreField('可用場景', asset.reusableScenes, 6);
    scoreField('能力', asset.capabilities, 5);
    scoreField('資產標籤', asset.tags, 4);
    scoreField('來源', [asset.sourceLabel], 3);
    scoreField('摘要', [asset.summary], 2);
    final surpriseReason = _surpriseReasonFor(asset, matchedValues);
    if (surpriseReason != null) {
      score += 3;
      reasons.add(surpriseReason);
    }

    if (asset.reusableByProjects) score += 2;
    if (asset.reusableByAgents) score += 2;
    if (asset.kind == DigitalAssetKind.workflowEngine ||
        asset.kind == DigitalAssetKind.projectPlaybook) {
      score += 2;
    }

    return (score: score, reasons: reasons.toList(growable: false));
  }

  List<String> _prioritizedSuggestionReasons(List<String> reasons) {
    final surprise = reasons
        .where((reason) => reason.startsWith('驚喜條件：'))
        .toList(growable: false);
    final normal = reasons
        .where((reason) => !reason.startsWith('驚喜條件：'))
        .take(4)
        .toList(growable: true);
    if (surprise.isNotEmpty) {
      normal.add(surprise.first);
    } else if (normal.length < 5) {
      normal.addAll(reasons.skip(normal.length).take(5 - normal.length));
    }
    return normal.take(5).toList(growable: false);
  }

  String? _surpriseReasonFor(
    DigitalAsset asset,
    Map<String, List<String>> matchedValues,
  ) {
    final practical = [
      ...?matchedValues['目的標籤'],
      ...?matchedValues['可用場景'],
      ...?matchedValues['能力'],
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    final creative = [
      ...?matchedValues['創意標籤'],
      ...?matchedValues['性質標籤'],
      ...?matchedValues['資產標籤'],
    ].where((item) => item.trim().isNotEmpty).toList(growable: false);
    if (practical.isEmpty || creative.isEmpty) return null;
    if (!asset.reusableByProjects && !asset.reusableByAgents) return null;
    return '驚喜條件：${practical.first} × ${creative.first}，情理之中、意料之外的聯想';
  }

  List<String> _cleanList(List<String> items) {
    return items
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  String _slugFor(String value) {
    final slug = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
      '-',
    );
    return slug.replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
