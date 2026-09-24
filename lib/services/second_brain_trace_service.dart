import '../models/second_brain_file_index.dart';
import '../models/second_brain_trace.dart';
import '../models/transurfing_brain.dart';
import 'memory_store.dart';
import 'second_brain_file_index_store.dart';

class SecondBrainTraceService {
  final SecondBrainFileIndexStore fileIndexStore;

  const SecondBrainTraceService({
    this.fileIndexStore = const SecondBrainFileIndexStore(),
  });

  Future<SecondBrainTrace> build({
    required BrainReflection reflection,
    required List<String> recalledInsights,
    required List<String> newInsights,
    Map<String, TransurfingInsightFeedback> feedbacks = const {},
    String? activeCompanionName,
    String? activeCompanionId, // [以利沙 P0 修復十八輪 2026-06-27] 補傳 agentId 給 fileIndexStore.search
    String? activeBridgeActionLabel,
  }) async {
    final recalled = <SecondBrainMemoryTrace>[];
    final associationFeedbacks =
        await MemoryStore.getAllSecondBrainAssociationFeedbacks();
    final indexedFiles = await fileIndexStore.search(
      '${reflection.userIntent} ${activeBridgeActionLabel ?? ''}',
      limit: 3,
      associationFeedbacks: associationFeedbacks,
      agentId: activeCompanionId,
    );
    await fileIndexStore.markUsed(indexedFiles);

    for (final file in indexedFiles) {
      recalled.add(
        SecondBrainMemoryTrace(
          content: file.summary.isNotEmpty ? file.summary : file.title,
          room: file.room.label,
          sourceLabel: file.title,
          sourcePath: file.path,
          reason: '因為這輪意圖提到「${reflection.userIntent}」，第二大腦檔案索引找到相關來源。',
          retrievalSignals: _retrievalSignalsForFile(
            file,
            reflection,
            activeBridgeActionLabel: activeBridgeActionLabel,
            associationFeedbacks: associationFeedbacks,
          ),
          freshnessLabel: _freshnessForFile(file),
          sourcePreview: _sourcePreviewForFile(file),
          tags: [file.room.zhLabel, ...file.tags].take(4).toList(),
          trustScore: file.trustScore,
        ),
      );
    }

    for (final insight in recalledInsights) {
      recalled.add(
        SecondBrainMemoryTrace(
          content: _cleanInsight(insight),
          room: _roomFor(insight, reflection),
          sourceLabel: 'Transurfing 洞察庫',
          sourcePath: 'local://memory/transurfing-insights',
          reason: _reasonFor(
            insight,
            reflection,
            activeBridgeActionLabel: activeBridgeActionLabel,
          ),
          retrievalSignals: _retrievalSignalsForInsight(
            insight,
            reflection,
            activeBridgeActionLabel: activeBridgeActionLabel,
          ),
          freshnessLabel: '長期洞察',
          sourcePreview: _cleanInsight(insight),
          tags: _tagsFor(insight, reflection),
          trustScore: await MemoryStore.getTransurfingInsightTrustScore(
            insight,
          ),
        ),
      );
    }

    return SecondBrainTrace(
      agentName: activeCompanionName,
      recalledMemories: recalled,
      newInsights: newInsights
          .map(
            (insight) => SecondBrainNewInsightTrace(
              content: _cleanInsight(insight),
              room: _roomFor(insight, reflection),
              tags: _tagsFor(insight, reflection),
            ),
          )
          .toList(),
      associations: _associationsFor(
        reflection,
        recalledInsights,
        newInsights,
        indexedFiles.length,
      ),
    );
  }

  String _cleanInsight(String insight) {
    return insight.replaceFirst(RegExp(r'^Transurfing洞察[：:]'), '').trim();
  }

  String _freshnessForFile(SecondBrainFileEntry file) {
    final now = DateTime.now();
    final touched = file.lastFeedbackAt ?? file.lastUsedAt ?? file.indexedAt;
    final days = now.difference(touched).inDays;
    if (days <= 1) return '剛更新';
    if (days <= 14) return '$days 天內';
    if (days <= 90) return '近期資料';
    return '較舊資料';
  }

  String _sourcePreviewForFile(SecondBrainFileEntry file) {
    final preview = file.contentExcerpt.trim().isNotEmpty
        ? file.contentExcerpt.trim()
        : file.contentDigest.trim().isNotEmpty
        ? file.contentDigest.trim()
        : file.summary.trim();
    return preview;
  }

  String _roomFor(String text, BrainReflection reflection) {
    final value = '$text ${reflection.userIntent}'.toLowerCase();
    if (_containsAny(value, const ['門', 'door', '主線', '支線'])) {
      return 'Doors';
    }
    if (_containsAny(value, const ['新工具', '新平台', 'ai 服務', '橋樑', 'adapter'])) {
      return 'Bridges';
    }
    if (_containsAny(value, const ['鐘擺', '注意力', '平台拉力', '外部平台'])) {
      return 'Pendulums';
    }
    if (_containsAny(value, const ['輸出', '作品', '生成', '文件', '圖像'])) {
      return 'Outputs';
    }
    if (_containsAny(value, const ['夥伴', '角色', 'agent'])) {
      return 'Companions';
    }
    return 'Insights';
  }

  List<String> _tagsFor(String text, BrainReflection reflection) {
    final value = '$text ${reflection.userIntent}'.toLowerCase();
    final tags = <String>{
      if (_containsAny(value, const ['第二大腦', '記憶', '洞察'])) '第二大腦',
      if (_containsAny(value, const ['檔案', '文件', '索引'])) '檔案索引',
      if (_containsAny(value, const ['ai agent', 'agent', '夥伴']))
        'AI Agent 共用記憶',
      if (_containsAny(value, const ['門', '主線', '支線'])) '門',
      if (_containsAny(value, const ['橋樑', 'adapter', '能力'])) '橋樑能力',
      if (_containsAny(value, const ['新工具', '新平台', 'ai 服務'])) '新 AI 服務',
      if (_containsAny(value, const ['注意力', '鐘擺'])) '注意力',
      if (_containsAny(value, const ['輸出', '作品'])) '輸出',
    };
    if (tags.isEmpty) tags.add('思維儀表');
    return tags.take(4).toList();
  }

  String _reasonFor(
    String insight,
    BrainReflection reflection, {
    String? activeBridgeActionLabel,
  }) {
    final bridgeLabel = activeBridgeActionLabel?.trim();
    if (bridgeLabel != null && bridgeLabel.isNotEmpty) {
      return '因為這輪正在處理「$bridgeLabel」，系統需要調用相關洞察來判斷能力缺口與下一步。';
    }
    return '因為這輪意圖被判定為「${reflection.userIntent}」，與這筆洞察的主題相符。';
  }

  List<String> _retrievalSignalsForFile(
    SecondBrainFileEntry file,
    BrainReflection reflection, {
    String? activeBridgeActionLabel,
    Map<String, SecondBrainAssociationFeedback> associationFeedbacks = const {},
  }) {
    final query = '${reflection.userIntent} ${activeBridgeActionLabel ?? ''}';
    final haystack =
        '${file.title} ${file.path} ${file.room.label} ${file.room.zhLabel} '
                '${file.summary} ${file.contentDigest} ${file.contentExcerpt} '
                '${file.tags.join(' ')} ${file.keywords.join(' ')}'
            .toLowerCase();
    final matchedTerms = _tokensFor(
      query,
    ).where((token) => haystack.contains(token)).take(3).toList();
    final signals = <String>[
      if (matchedTerms.isNotEmpty) '關鍵字命中：${matchedTerms.join('、')}',
      '房間命中：${file.room.zhLabel}',
      if (activeBridgeActionLabel?.trim().isNotEmpty == true)
        '任務脈絡：$activeBridgeActionLabel',
      if (file.pinned) '使用者標記：之後常引用',
      if (file.usefulFeedbackCount > 0) '正回饋：${file.usefulFeedbackCount} 次有用',
      if (file.useCount > 0) '使用痕跡：曾調閱 ${file.useCount} 次',
      if (file.trustScore >= 80) '信任分高：${file.trustScore}',
      ..._associationSignalsFor(haystack, associationFeedbacks),
    ];
    if (signals.isEmpty) {
      signals.add('基礎語意命中：與目前問題相近');
    }
    return signals.take(6).toList();
  }

  List<String> _retrievalSignalsForInsight(
    String insight,
    BrainReflection reflection, {
    String? activeBridgeActionLabel,
  }) {
    final cleaned = _cleanInsight(insight);
    final value = '$cleaned ${reflection.userIntent}'.toLowerCase();
    final matchedTerms = _tokensFor(
      reflection.userIntent,
    ).where((token) => value.contains(token)).take(3).toList();
    final tags = _tagsFor(insight, reflection);
    return <String>[
      if (matchedTerms.isNotEmpty) '意圖命中：${matchedTerms.join('、')}',
      if (tags.isNotEmpty) '主題標籤：${tags.take(2).join('、')}',
      if (activeBridgeActionLabel?.trim().isNotEmpty == true)
        '任務脈絡：$activeBridgeActionLabel',
      '來源類型：長期洞察庫',
    ].take(5).toList();
  }

  List<String> _associationSignalsFor(
    String haystack,
    Map<String, SecondBrainAssociationFeedback> associationFeedbacks,
  ) {
    final signals = <String>[];
    for (final entry in associationFeedbacks.entries) {
      final tokens = _tokensFor(
        entry.key,
      ).where((token) => !_associationStopWords.contains(token)).toList();
      if (tokens.isEmpty) continue;
      final hits = tokens.where(haystack.contains).take(2).toList();
      if (hits.isEmpty) continue;
      final label = entry.value == SecondBrainAssociationFeedback.useful
          ? '好關聯加權'
          : '錯關聯降權';
      signals.add('$label：${hits.join('、')}');
    }
    return signals;
  }

  List<String> _associationsFor(
    BrainReflection reflection,
    List<String> recalledInsights,
    List<String> newInsights,
    int indexedFileCount,
  ) {
    final associations = <String>[];
    if (indexedFileCount > 0) {
      associations.add('本輪從第二大腦檔案索引調閱 $indexedFileCount 個真實來源。');
    }
    if (recalledInsights.isNotEmpty && newInsights.isNotEmpty) {
      associations.add('把本輪新洞察連到已召回的 ${recalledInsights.length} 筆舊洞察。');
    }
    if (reflection.doorDecision != null) {
      associations.add('偵測到重大分支門，已把未選路線視為可回流門。');
    }
    if (reflection.recommendedMove == RecommendedMove.routeBridge) {
      associations.add('把目前需求連到橋樑能力缺口，等待能力開通後回到任務。');
    }
    return associations;
  }

  bool _containsAny(String value, List<String> needles) {
    return needles.any((needle) => value.contains(needle.toLowerCase()));
  }

  List<String> _tokensFor(String query) {
    final normalized = query.toLowerCase();
    final tokens = normalized
        .split(RegExp(r'[\s，。！？、,.;:：/\\|()[\]{}<>「」『』]+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 2)
        .toSet()
        .toList();
    if (tokens.isEmpty && normalized.length >= 2) return [normalized];
    return tokens;
  }

  static const Set<String> _associationStopWords = {
    '第二大腦',
    '關聯',
    '本輪',
    '目前',
    '系統',
    '已經',
    '使用者',
    '任務',
    '回到',
    '相關',
    'adapter',
    '完成',
    '訊號',
    '完成訊號',
    '原本',
    '卡點',
  };
}
