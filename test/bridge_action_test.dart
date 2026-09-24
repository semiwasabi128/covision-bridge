import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/agent_activity.dart';
import 'package:bridge_app/models/bridge_action.dart';
import 'package:bridge_app/models/conversation.dart';
import 'package:bridge_app/models/transurfing_brain.dart';
import 'package:bridge_app/services/api_service.dart';
import 'package:bridge_app/services/bridge_adapters/bridge_action_adapter.dart';
import 'package:bridge_app/services/bridge_adapters/bridge_adapter_registry.dart';
import 'package:bridge_app/services/bridge_adapters/local_desktop_files_adapter.dart';
import 'package:bridge_app/services/bridge_adapters/openai_browse_adapter.dart';
import 'package:bridge_app/services/bridge_adapters/openai_image_adapter.dart';
import 'package:bridge_app/services/bridge_adapters/openai_vision_adapter.dart';
import 'package:bridge_app/services/bridge_action_execution_decision_service.dart';
import 'package:bridge_app/services/bridge_action_execution_evidence.dart';
import 'package:bridge_app/services/bridge_action_executor.dart';
import 'package:bridge_app/services/capability_health_service.dart';
import 'package:bridge_app/services/capability_router.dart';
import 'package:bridge_app/services/context_compressor.dart';
import 'package:bridge_app/services/local_task_routing_service.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/storage_service.dart';
import 'package:bridge_app/services/task_routing_rule_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // [hang 修復 2026-09-22] macOS token 走 golden_keys.json → saveToken/getToken
  // 會問 path_provider（platform channel）→ FakeAsync 測試環境永不回應，
  // 含 StorageService 呼叫的測試直接卡死。注入臨時目錄繞過。
  // [汙染修復] setUp 而非 setUpAll——每個測試全新目錄＋清 memory cache，
  // 避免前一個測試存過的 token 洩漏到下一個（capability router 系列
  // 對「誰有 token」極度敏感）。
  setUp(() {
    StorageService.useTestTokenDirectory(
      Directory.systemTemp.createTempSync('bridge_action_token_'),
    );
  });
  tearDown(() {
    StorageService.useTestTokenDirectory(null);
  });

  test('parses image bridge tag into typed action', () {
    final text = '我幫你生成圖片。[GENERATE_IMAGE: warm geometric companion avatar]';
    final match = BridgeAction.tagPattern.firstMatch(text);

    expect(match, isNotNull);
    final action = BridgeAction.fromTagMatch(match!);

    expect(action.type, BridgeActionType.generateImage);
    expect(action.prompt, 'warm geometric companion avatar');
    expect(action.displayType, '生成圖片');
  });

  test('parses animation bridge tag into typed action', () {
    final text = '我幫你生成動圖。[GENERATE_ANIMATION: blink and breathe loop]';
    final match = BridgeAction.tagPattern.firstMatch(text);

    expect(match, isNotNull);
    final action = BridgeAction.fromTagMatch(match!);

    expect(action.type, BridgeActionType.generateAnimation);
    expect(action.prompt, 'blink and breathe loop');
    expect(action.displayType, '生成動圖');
  });

  test('parses vision bridge tag into typed action', () {
    final text = '我來看這張圖。[VISION: describe the uploaded screenshot]';
    final match = BridgeAction.tagPattern.firstMatch(text);

    expect(match, isNotNull);
    final action = BridgeAction.fromTagMatch(match!);

    expect(action.type, BridgeActionType.vision);
    expect(action.prompt, 'describe the uploaded screenshot');
    expect(action.displayType, '圖片辨識');
  });

  test('parses search aliases into browse action', () {
    final text = '我來查。[GOOGLE_SEARCH: 宜蘭火車站時刻表 今天]';
    final match = BridgeAction.tagPattern.firstMatch(text);

    expect(match, isNotNull);
    final action = BridgeAction.fromTagMatch(match!);

    expect(action.type, BridgeActionType.browse);
    expect(action.prompt, '宜蘭火車站時刻表 今天');
  });

  test('parses tagged search command as direct bridge action', () {
    final action = BridgeAction.tryParseDirectCommand(
      '[GOOGLE_SEARCH: 宜蘭火車站時刻表 今天]',
    );

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.browse);
    expect(action.prompt, '宜蘭火車站時刻表 今天');
  });

  test('chat response extracts search alias and hides raw tag', () {
    final response = ChatResponse.fromJson({
      'choices': [
        {
          'message': {'content': '我幫你查詢。[GOOGLE_SEARCH: 宜蘭火車站時刻表 今天]'},
        },
      ],
      'usage': {'prompt_tokens': 1, 'completion_tokens': 1},
      'model': 'test',
    });

    expect(response.bridgeActions.single.type, BridgeActionType.browse);
    expect(response.bridgeActions.single.prompt, '宜蘭火車站時刻表 今天');
    expect(response.cleanContent, '我幫你查詢。');
  });

  test('serializes and restores bridge action', () {
    const action = BridgeAction(
      type: BridgeActionType.generateImage,
      prompt: 'a luminous bridge over a quiet city',
      provider: 'openai',
      model: 'gpt-image-1.5',
      imageQuality: 'high',
      referenceImagePaths: ['/tmp/reference.png'],
      runStatus: BridgeActionRunStatus.completed,
      statusMessage: '圖片已生成完成',
    );

    final restored = BridgeAction.fromJson(action.toJson());

    expect(restored.type, BridgeActionType.generateImage);
    expect(restored.prompt, action.prompt);
    expect(restored.provider, 'openai');
    expect(restored.model, 'gpt-image-1.5');
    expect(restored.imageQuality, 'high');
    expect(restored.referenceImagePaths, ['/tmp/reference.png']);
    expect(restored.runStatus, BridgeActionRunStatus.completed);
    expect(restored.statusMessage, '圖片已生成完成');
  });

  test('parses slash image command into direct bridge action', () {
    final action = BridgeAction.tryParseDirectCommand(
      '/image a quiet cyberpunk tea shop',
    );

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.generateImage);
    expect(action.prompt, 'a quiet cyberpunk tea shop');
    expect(action.provider, isNull);
  });

  test('parses Chinese image command into direct bridge action', () {
    final action = BridgeAction.tryParseDirectCommand('畫一張：夜晚城市上空的發光橋樑');

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.generateImage);
    expect(action.prompt, '夜晚城市上空的發光橋樑');
    expect(action.provider, isNull);
  });

  test('parses slash document command into direct bridge action', () {
    final action = BridgeAction.tryParseDirectCommand('/doc PRD|橋樑計畫第三座橋規格');

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.document);
    expect(action.prompt, 'PRD|橋樑計畫第三座橋規格');
  });

  test('parses Chinese document command into direct bridge action', () {
    final action = BridgeAction.tryParseDirectCommand('產出文件：橋樑計畫目前進度摘要');

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.document);
    expect(action.prompt, '橋樑計畫目前進度摘要');
  });

  test('parses Chinese PDF report command into document bridge action', () {
    final action = BridgeAction.tryParseDirectCommand('幫我產出一份PDF：直播帶貨專案摘要');

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.document);
    expect(action.prompt, '直播帶貨專案摘要');
  });

  test('parses Chinese proposal command into document bridge action', () {
    final action = BridgeAction.tryParseDirectCommand('產出報告：SemiDAO 社群包企劃');

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.document);
    expect(action.prompt, 'SemiDAO 社群包企劃');
  });

  test('document evidence includes document type and plugin interfaces', () {
    final result = BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: '文件已產出。',
      metadata: {
        'kind': 'document',
        'documentType': '企劃',
        'provider': 'local_document',
        'generationMode': 'local_template',
        'exportPaths': {
          'Markdown': '/tmp/plan.md',
          'HTML': '/tmp/plan.html',
          'PDF': '/tmp/plan.pdf',
        },
        'plannedFormats': ['DOCX', 'PPTX'],
        'path': '/tmp/plan.md',
      },
    );

    final evidence = const BridgeActionExecutionEvidence().describe(result);

    expect(evidence, contains('文件證據'));
    expect(evidence, contains('類型 企劃'));
    expect(evidence, contains('格式 Markdown、HTML、PDF'));
    expect(evidence, contains('插件接口 DOCX、PPTX'));
  });

  test('parses desktop file commands into desktop bridge action', () {
    final action = BridgeAction.tryParseDirectCommand('整理桌面：找出圖片檔並分類');

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.desktopFiles);
    expect(action.prompt, '找出圖片檔並分類');
    expect(action.displayType, '桌面整理');
  });

  test('parses desktop scan commands into desktop bridge action', () {
    final action = BridgeAction.tryParseDirectCommand('幫我掃描桌面檔案，先列出整理計畫');

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.desktopFiles);
    expect(action.prompt, '先列出整理計畫');
  });

  test('parses tagged desktop file command as bridge action', () {
    final action = BridgeAction.tryParseDirectCommand(
      '[DESKTOP_FILES: 整理下載資料夾]',
    );

    expect(action, isNotNull);
    expect(action!.type, BridgeActionType.desktopFiles);
    expect(action.prompt, '整理下載資料夾');
  });

  test(
    'desktop file bridge scans authorized folder in read-only mode',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'bridge_desktop_scan_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File('${root.path}/photo.png').writeAsString('image');
      await File('${root.path}/plan.md').writeAsString('# plan');
      await Directory('${root.path}/old').create();

      final adapter = LocalDesktopFilesAdapter(allowedRoots: [root.path]);
      final result = await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.desktopFiles,
          prompt: '整理桌面圖片和文件',
        ),
      );

      expect(result.status, BridgeActionStatus.completed);
      expect(result.message, contains('只讀掃描'));
      expect(result.metadata?['kind'], 'desktop_file_plan');
      expect(result.metadata?['readOnly'], isTrue);
      expect(result.metadata?['fileCount'], 2);
      expect(result.metadata?['folderCount'], 1);
      expect(result.metadata?['categoryCounts'], containsPair('圖片', 1));
      expect(result.metadata?['categoryCounts'], containsPair('文件', 1));
      expect(result.metadata?['suggestions'], isA<List<dynamic>>());
      expect(result.metadata?['categorySummary'], contains('圖片 1'));
      expect(result.metadata?['plannedFolderCount'], 2);
      expect(result.metadata?['plannedMoveCount'], 2);
      expect(
        result.metadata?['applyPrompt'],
        '${LocalDesktopFilesAdapter.applyPlanPrefix}${root.path}',
      );
      final evidence = const BridgeActionExecutionEvidence().describe(result);
      expect(evidence, contains('桌面整理證據'));
      expect(evidence, contains('只讀掃描'));
    },
  );

  test('desktop file bridge scans folder selected by desktop app', () async {
    final root = await Directory.systemTemp.createTemp(
      'bridge_desktop_selected_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File('${root.path}/invoice.pdf').writeAsString('pdf');
    await File('${root.path}/clip.mov').writeAsString('video');

    final adapter = LocalDesktopFilesAdapter();
    final result = await adapter.execute(
      BridgeAction(
        type: BridgeActionType.desktopFiles,
        prompt: LocalDesktopFilesAdapter.scanPrompt(
          rootPath: root.path,
          taskPrompt: '先列出整理計畫，不要搬移檔案',
        ),
      ),
    );

    expect(result.status, BridgeActionStatus.completed);
    expect(result.metadata?['rootPath'], root.path);
    expect(result.metadata?['prompt'], '先列出整理計畫，不要搬移檔案');
    expect(result.metadata?['fileCount'], 2);
    expect(result.metadata?['categoryCounts'], containsPair('文件', 1));
    expect(result.metadata?['categoryCounts'], containsPair('影片', 1));
    expect(
      result.metadata?['applyPrompt'],
      '${LocalDesktopFilesAdapter.applyPlanPrefix}${root.path}',
    );
  });

  test('desktop file bridge scans filenames with raw percent signs', () async {
    final root = await Directory.systemTemp.createTemp(
      'bridge_desktop_percent_',
    );
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File('${root.path}/progress 100% raw.md').writeAsString('# percent');

    final adapter = LocalDesktopFilesAdapter();
    final result = await adapter.execute(
      BridgeAction(
        type: BridgeActionType.desktopFiles,
        prompt: LocalDesktopFilesAdapter.scanPrompt(
          rootPath: root.path,
          taskPrompt: '掃描含百分比檔名的資料夾',
        ),
      ),
    );

    expect(result.status, BridgeActionStatus.completed);
    expect(result.metadata?['fileCount'], 1);
    final samples = result.metadata?['samples'] as List<dynamic>;
    expect(samples.single['name'], 'progress 100% raw.md');
  });

  test('desktop file bridge executes confirmed organize plan', () async {
    final root = await Directory.systemTemp.createTemp('bridge_desktop_apply_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File('${root.path}/photo.png').writeAsString('image');
    await File('${root.path}/plan.md').writeAsString('# plan');
    await File('${root.path}/misc.unknownext').writeAsString('misc');

    final adapter = LocalDesktopFilesAdapter(allowedRoots: [root.path]);
    final result = await adapter.execute(
      BridgeAction(
        type: BridgeActionType.desktopFiles,
        prompt: '${LocalDesktopFilesAdapter.applyPlanPrefix}${root.path}',
      ),
    );

    expect(result.status, BridgeActionStatus.completed);
    expect(result.metadata?['executed'], isTrue);
    expect(result.metadata?['movedCount'], 2);
    expect(result.metadata?['createdFolderCount'], 2);
    expect(await File('${root.path}/圖片/photo.png').exists(), isTrue);
    expect(await File('${root.path}/文件/plan.md').exists(), isTrue);
    expect(await File('${root.path}/misc.unknownext').exists(), isTrue);
    final recordPath = result.metadata?['recordPath']?.toString();
    expect(recordPath, isNotNull);
    expect(await File(recordPath!).exists(), isTrue);
    final evidence = const BridgeActionExecutionEvidence().describe(result);
    expect(evidence, contains('已移動 2'));
  });

  test('document generator strips markdown code fences', () {
    final markdown = ApiService.stripMarkdownFencesForTest(
      '```markdown\n# 文件\n\n內容\n```',
    );

    expect(markdown, '# 文件\n\n內容');
  });

  test(
    'context compressor summarizes older messages and keeps recent ones',
    () {
      final messages = List.generate(8, (index) {
        return {
          'role': index.isEven ? 'user' : 'assistant',
          'content': 'message $index',
        };
      });

      final result = ContextCompressor.compressMessagesSync(
        messages,
        enabled: true,
        recentMessageLimit: 3,
      );

      expect(result.didCompress, isTrue);
      expect(result.compressedCount, 5);
      expect(result.strategy, 'local');
      expect(result.systemNote, contains('已壓縮的較早上下文'));
      expect(result.systemNote, contains('message 0'));
      expect(result.messages.map((m) => m['content']), [
        'message 5',
        'message 6',
        'message 7',
      ]);
    },
  );

  test('context compressor wraps semantic summaries for v2 handoff', () {
    final note = ContextCompressor.buildSemanticSystemNote(
      '## 目前目標\n完成橋樑 App 的語意壓縮。',
    );

    expect(note, contains('語意壓縮上下文 v2'));
    expect(note, contains('目前目標'));
    expect(note, contains('優先遵循最近訊息'));
  });

  test('context compressor builds Transurfing Brain notes', () {
    const reflection = BrainReflection(
      userIntent: '想把外部 AI 服務轉成自己的可用能力。',
      attentionState: AttentionState.captured,
      pendulumSignals: [
        PendulumSignal(
          type: PendulumSignalType.platformPull,
          label: '平台拉力',
          evidence: '影片生成',
        ),
      ],
      importanceLevel: ImportanceLevel.elevated,
      heartMindAlignment: HeartMindAlignment.mixed,
      fraileResonance: FraileResonance.obscured,
      doorCandidates: [
        DoorCandidate(
          kind: DoorKind.foreignDoor,
          label: '外部平台的門',
          reason: '訊息焦點被新服務吸引。',
        ),
      ],
      flowState: FlowState.againstFlow,
      recommendedMove: RecommendedMove.convertToOutput,
      companionExpression: CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        statusText: '正在收束注意力',
      ),
      guidance: '把外部資訊轉成自己的輸出。',
    );

    final note = ContextCompressor.buildTransurfingBrainNotes(reflection);

    expect(note, contains('Transurfing Brain Notes'));
    expect(note, contains('注意力：被捕獲'));
    expect(note, contains('鐘擺：平台拉力(影片生成)'));
    expect(note, contains('建議：轉成輸出'));
  });

  test('memory store remembers high value Transurfing insights', () async {
    SharedPreferences.setMockInitialValues({});

    const reflection = BrainReflection(
      userIntent: '想把外部 AI 服務轉成自己的可用能力。',
      attentionState: AttentionState.captured,
      pendulumSignals: [
        PendulumSignal(
          type: PendulumSignalType.platformPull,
          label: '平台拉力',
          evidence: '影片生成',
        ),
      ],
      importanceLevel: ImportanceLevel.elevated,
      heartMindAlignment: HeartMindAlignment.mixed,
      fraileResonance: FraileResonance.obscured,
      doorCandidates: [],
      flowState: FlowState.againstFlow,
      recommendedMove: RecommendedMove.convertToOutput,
      companionExpression: CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        statusText: '正在收束注意力',
      ),
      guidance: '把外部資訊轉成自己的輸出。',
    );

    final insights = await MemoryStore.rememberTransurfingInsights(reflection);
    final memories = await MemoryStore.getAll();

    expect(insights.length, greaterThanOrEqualTo(3));
    expect(memories, containsAll(insights));
    expect(
      memories,
      contains('Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。'),
    );
  });

  test('memory store recalls matching Transurfing insights', () async {
    SharedPreferences.setMockInitialValues({
      'bridge_memories': [
        'Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。',
        '使用者喜歡溫柔但直接的建議。',
      ],
    });

    const reflection = BrainReflection(
      userIntent: '想試試新的 AI 影片工具。',
      attentionState: AttentionState.captured,
      pendulumSignals: [
        PendulumSignal(
          type: PendulumSignalType.platformPull,
          label: '平台拉力',
          evidence: 'AI 影片工具',
        ),
      ],
      importanceLevel: ImportanceLevel.balanced,
      heartMindAlignment: HeartMindAlignment.mixed,
      fraileResonance: FraileResonance.present,
      doorCandidates: [],
      flowState: FlowState.withFlow,
      recommendedMove: RecommendedMove.convertToOutput,
      companionExpression: CompanionExpression(
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
        statusText: '正在回收洞察',
      ),
      guidance: '先定義要輸出的成果。',
    );

    final recalled = await MemoryStore.recallTransurfingInsights(reflection);

    expect(recalled, hasLength(1));
    expect(recalled.single, 'Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。');
  });

  test(
    'memory store feedback suppresses and restores insight recall',
    () async {
      const insight = 'Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。';
      SharedPreferences.setMockInitialValues({
        'bridge_memories': [insight],
      });

      const reflection = BrainReflection(
        userIntent: '想試試新的 AI 影片工具。',
        attentionState: AttentionState.clear,
        pendulumSignals: [],
        importanceLevel: ImportanceLevel.balanced,
        heartMindAlignment: HeartMindAlignment.aligned,
        fraileResonance: FraileResonance.present,
        doorCandidates: [],
        flowState: FlowState.withFlow,
        recommendedMove: RecommendedMove.convertToOutput,
        companionExpression: CompanionExpression(
          mood: AgentCompanionMood.focused,
          action: AgentCompanionAction.reading,
          statusText: '正在回收洞察',
        ),
        guidance: '先定義要輸出的成果。',
      );

      await MemoryStore.markTransurfingInsightFeedback(
        insight,
        TransurfingInsightFeedback.muted,
      );

      expect(await MemoryStore.getTransurfingInsightTrustScore(insight), 50);
      expect(await MemoryStore.recallTransurfingInsights(reflection), isEmpty);
      expect(
        await MemoryStore.getFormattedMemories(),
        isNot(contains(insight)),
      );

      await MemoryStore.markTransurfingInsightFeedback(
        insight,
        TransurfingInsightFeedback.accurate,
      );

      expect(await MemoryStore.getTransurfingInsightTrustScore(insight), 65);
      expect(await MemoryStore.recallTransurfingInsights(reflection), [
        insight,
      ]);
      expect(await MemoryStore.getFormattedMemories(), contains(insight));
    },
  );

  test('memory store lists insight records across feedback states', () async {
    const accurateInsight = 'Transurfing洞察：使用者注意力容易被外部平台或新 AI 服務捕獲，需要先轉成自己的輸出。';
    const inaccurateInsight = 'Transurfing洞察：此類議題出現逆流訊號，需要檢查是否過度控制、焦慮或走進外部目標。';
    SharedPreferences.setMockInitialValues({
      'bridge_memories': [accurateInsight],
      'bridge_insight_accurate': [accurateInsight],
      'bridge_insight_inaccurate': [inaccurateInsight],
      'bridge_insight_trust_scores':
          '{"$accurateInsight":90,"$inaccurateInsight":10}',
    });

    final records = await MemoryStore.getTransurfingInsightRecords();

    expect(records.map((record) => record.insight), contains(accurateInsight));
    expect(
      records.map((record) => record.insight),
      contains(inaccurateInsight),
    );
    expect(
      records
          .firstWhere((record) => record.insight == accurateInsight)
          .feedback,
      TransurfingInsightFeedback.accurate,
    );
    expect(
      records
          .firstWhere((record) => record.insight == inaccurateInsight)
          .feedback,
      TransurfingInsightFeedback.inaccurate,
    );
    expect(
      records
          .firstWhere((record) => record.insight == accurateInsight)
          .trustScore,
      90,
    );
  });

  test(
    'memory store trust score gates and prioritizes insight recall',
    () async {
      const highTrustInsight =
          'Transurfing洞察：遇到新工具或新平台時，最佳策略是把資訊消費轉成具體作品或任務輸出。';
      const lowTrustInsight =
          'Transurfing洞察：使用者注意力容易被外部平台或新 AI 服務捕獲，需要先轉成自己的輸出。';
      SharedPreferences.setMockInitialValues({
        'bridge_memories': [lowTrustInsight, highTrustInsight],
        'bridge_insight_trust_scores':
            '{"$lowTrustInsight":19,"$highTrustInsight":80}',
      });

      const reflection = BrainReflection(
        userIntent: '想試試新的 AI 影片工具。',
        attentionState: AttentionState.captured,
        pendulumSignals: [],
        importanceLevel: ImportanceLevel.balanced,
        heartMindAlignment: HeartMindAlignment.aligned,
        fraileResonance: FraileResonance.present,
        doorCandidates: [],
        flowState: FlowState.withFlow,
        recommendedMove: RecommendedMove.convertToOutput,
        companionExpression: CompanionExpression(
          mood: AgentCompanionMood.focused,
          action: AgentCompanionAction.reading,
          statusText: '正在回收洞察',
        ),
        guidance: '先定義要輸出的成果。',
      );

      final recalled = await MemoryStore.recallTransurfingInsights(reflection);

      expect(recalled, [highTrustInsight]);
      expect(
        await MemoryStore.getFormattedMemories(),
        contains(highTrustInsight),
      );
      expect(
        await MemoryStore.getFormattedMemories(),
        isNot(contains(lowTrustInsight)),
      );
    },
  );

  test('context compressor builds Transurfing insight recall notes', () {
    final note = ContextCompressor.buildTransurfingInsightRecallNotes([
      'Transurfing洞察：使用者注意力容易被外部平台或新 AI 服務捕獲，需要先轉成自己的輸出。',
    ]);

    expect(note, contains('Transurfing Insight Recall'));
    expect(note, contains('長期記憶'));
    expect(note, contains('不要僵硬套用'));
    expect(note, contains('注意力容易被外部平台'));
  });

  test('message serializes document attachment metadata', () {
    final message = Message(
      id: '1',
      role: 'assistant',
      content: '文件已產出',
      timestamp: DateTime.parse('2026-06-02T00:00:00.000'),
      attachmentKind: 'document',
      attachmentPath: '/tmp/bridge.md',
      metadata: {
        'kind': 'web_search',
        'query': 'AI news',
        'searchSources': [
          {'title': 'OpenAI', 'url': 'https://example.com'},
        ],
      },
    );

    final restored = Message.fromJson(message.toJson());

    expect(restored.attachmentKind, 'document');
    expect(restored.attachmentPath, '/tmp/bridge.md');
    expect(restored.metadata?['kind'], 'web_search');
    expect(restored.metadata?['query'], 'AI news');
    expect(restored.metadata?['searchSources'], isA<List<dynamic>>());
  });

  test('image bridge asks for OpenAI token before provider call', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    final executor = BridgeActionExecutor();
    final result = await executor.execute(
      const BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: 'a tiny bridge app mascot',
        provider: 'openai',
      ),
    );

    expect(result.status, BridgeActionStatus.needsProvider);
    expect(result.message, contains('OpenAI API Token'));
  });

  test(
    'OpenAI image edit lowers input fidelity for reference variants',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('test-token', provider: 'openai');

      FormData? capturedForm;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedForm = options.data as FormData;
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {'data': []},
                ),
              );
            },
          ),
        );

      final adapter = OpenAiImageAdapter(dio: dio);
      await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'blink frame only; keep every non-eye pixel protected',
          provider: 'openai',
          model: 'gpt-image-1.5',
          imageQuality: 'high',
          referenceImagePaths: [
            'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=',
          ],
        ),
      );

      final fields = Map<String, String>.fromEntries(capturedForm!.fields);
      // [2026-09-22] gpt-image-2 統一時代：舊模型（含 gpt-image-1.5）已於
      // 2026-12-01 shutdown，所有請求統一走 gpt-image-2——它不支援
      // input_fidelity（也沒有 transparent background）。
      expect(fields['model'], 'gpt-image-2');
      expect(fields['input_fidelity'], isNull);
      expect(fields['background'], isNull);
    },
  );

  test('OpenAI vision adapter sends image input and returns text', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.saveToken('test-token', provider: 'openai');

    Map<String, dynamic>? capturedData;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            capturedData = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: const {'output_text': '這張圖是一個橋樑 APP 的截圖。'},
              ),
            );
          },
        ),
      );

    final adapter = OpenAiVisionAdapter(dio: dio);
    final result = await adapter.execute(
      const BridgeAction(
        type: BridgeActionType.vision,
        prompt: '請描述圖片內容',
        provider: 'openai',
        referenceImagePaths: ['data:image/png;base64,aGVsbG8='],
      ),
    );

    final input = capturedData?['input'] as List<dynamic>;
    final content = (input.first as Map)['content'] as List<dynamic>;

    expect(result.status, BridgeActionStatus.completed);
    expect(result.message, contains('橋樑 APP'));
    expect(result.metadata?['kind'], 'vision');
    expect(result.metadata?['prompt'], '請描述圖片內容');
    expect(result.metadata?['imageCount'], 1);
    expect(result.metadata?['imageSource'], '上傳圖片 1 張');
    expect(
      content.any((part) => (part as Map)['type'] == 'input_image'),
      isTrue,
    );
  });

  test('OpenAI vision adapter formats image analysis for users', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.saveToken('test-token', provider: 'openai');

    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'output_text': '''
## 1. 圖片摘要
這是一張 **橋樑 APP** 的聊天截圖，畫面中有圖片與 AI 回覆。

## 2. 重要細節
- 右上角有一張圖片縮圖。
- 下方有一段黑底白字內容覆蓋畫面。
- 輸入框被覆蓋，使用者可能無法繼續輸入。

## 3. 可用線索
這張圖可以用來判斷 Vision 回覆是否遮住聊天介面。

## 4. 下一步
建議先修正黑底白字覆蓋層，讓使用者可以關閉或收起。
''',
                },
              ),
            );
          },
        ),
      );

    final adapter = OpenAiVisionAdapter(dio: dio);
    final result = await adapter.execute(
      const BridgeAction(
        type: BridgeActionType.vision,
        prompt: '這張截圖哪裡有問題？',
        provider: 'openai',
        referenceImagePaths: ['data:image/png;base64,aGVsbG8='],
      ),
    );

    expect(result.status, BridgeActionStatus.completed);
    expect(result.message, contains('圖片摘要'));
    expect(result.message, contains('重要細節'));
    expect(result.message, contains('可用線索'));
    expect(result.message, contains('下一步'));
    expect(result.message, contains('黑底白字'));
    expect(result.message, isNot(contains('##')));
    expect(result.message, isNot(contains('**')));
    expect(result.metadata?['imageSource'], '上傳圖片 1 張');
  });

  test(
    'OpenAI browse adapter sends web search tool and returns text',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('test-token', provider: 'openai');

      Map<String, dynamic>? capturedData;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              capturedData = Map<String, dynamic>.from(options.data as Map);
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'output_text': '以下是今天 AI 新聞的搜尋整理。',
                    'output': [
                      {
                        'type': 'web_search_call',
                        'action': {'query': '今天有什麼 AI 新聞？'},
                      },
                      {
                        'type': 'message',
                        'content': [
                          {
                            'type': 'output_text',
                            'text': '以下是今天 AI 新聞的搜尋整理。',
                            'annotations': [
                              {
                                'type': 'url_citation',
                                'title': 'AI News Source',
                                'url': 'https://example.com/ai-news',
                              },
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );

      final adapter = OpenAiBrowseAdapter(dio: dio);
      final result = await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.browse,
          prompt: '今天有什麼 AI 新聞？',
          provider: 'openai',
        ),
      );

      final tools = capturedData?['tools'] as List<dynamic>;
      final firstTool = Map<String, dynamic>.from(tools.first as Map);

      expect(result.status, BridgeActionStatus.completed);
      expect(result.message, contains('AI 新聞'));
      expect(result.metadata?['kind'], 'web_search');
      expect(result.metadata?['query'], '今天有什麼 AI 新聞？');
      expect(result.metadata?['searchQueries'], contains('今天有什麼 AI 新聞？'));
      expect(result.metadata?['timeSensitive'], isTrue);
      expect(result.metadata?['sourceCount'], 1);
      expect(result.metadata?['sourceHealth'], 'sources_available');
      expect(
        result.metadata?['searchSources'],
        contains(containsPair('url', 'https://example.com/ai-news')),
      );
      expect(firstTool['type'], 'web_search');
      expect(firstTool['search_context_size'], 'medium');
      expect(capturedData?['tool_choice'], 'required');
    },
  );

  test(
    'OpenAI browse adapter reports missing clickable sources clearly',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('test-token', provider: 'openai');

      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'output_text': '搜尋摘要：查到一些線索，但沒有可點來源。',
                    'output': [
                      {
                        'type': 'web_search_call',
                        'action': {'query': '宜蘭火車站時刻表 今天'},
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );

      final adapter = OpenAiBrowseAdapter(dio: dio);
      final result = await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.browse,
          prompt: '幫我查今天宜蘭火車站的時刻表',
          provider: 'openai',
        ),
      );

      expect(result.status, BridgeActionStatus.completed);
      expect(result.metadata?['sourceCount'], 0);
      expect(result.metadata?['sourceHealth'], 'sources_missing');
      expect(result.metadata?['sourceWarning'], contains('沒有取得可點來源'));
      expect(result.metadata?['searchQueries'], contains('宜蘭火車站時刻表 今天'));
      final evidence = const BridgeActionExecutionEvidence().describe(result);
      expect(evidence, contains('來源不足'));
      expect(evidence, contains('實際搜尋'));
    },
  );

  test('OpenAI browse adapter formats chat output for users', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.saveToken('test-token', provider: 'openai');

    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: const {
                  'output_text':
                      '## 1. 搜尋摘要\n請看 **官方頁** ([railway.gov.tw](https://example.com/timetable))。\n- 已找到今日時刻表。',
                  'output': [
                    {
                      'type': 'message',
                      'content': [
                        {
                          'type': 'output_text',
                          'text':
                              '## 1. 搜尋摘要\n請看 **官方頁** ([railway.gov.tw](https://example.com/timetable))。\n- 已找到今日時刻表。',
                          'annotations': [
                            {
                              'type': 'url_citation',
                              'title': 'railway.gov.tw',
                              'url': 'https://example.com/timetable',
                            },
                          ],
                        },
                      ],
                    },
                  ],
                },
              ),
            );
          },
        ),
      );

    final adapter = OpenAiBrowseAdapter(dio: dio);
    final result = await adapter.execute(
      const BridgeAction(
        type: BridgeActionType.browse,
        prompt: '今天宜蘭火車站時刻表',
        provider: 'openai',
      ),
    );

    expect(result.status, BridgeActionStatus.completed);
    expect(result.message, contains('搜尋摘要'));
    expect(result.message, contains('官方頁'));
    expect(result.message, contains('railway.gov.tw'));
    expect(result.message, contains('• 已找到今日時刻表'));
    expect(result.message, isNot(contains('##')));
    expect(result.message, isNot(contains('**')));
    expect(result.message, isNot(contains('https://')));
  });

  test(
    'OpenAI browse adapter removes noisy source sections from chat answer',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('test-token', provider: 'openai');

      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'output_text': '''
## 1. 搜尋摘要
我查到 **臺鐵官方時刻表** 今日資訊，宜蘭站代碼為 7190。([railway.gov.tw](https://www.railway.gov.tw/tra-tip-web/tip/tip00H/tipH41/viewStaInfo/7190))

## 2. 關鍵重點
- **宜蘭站基本資訊**：官方顯示宜蘭站為 7190 宜蘭。
- **今天完整時刻表要分方向看**：順行與逆行需要分開查。
- **順行首末班概況**：可見 01:40、05:10、23:18 等班次。([railway.gov.tw](https://www.railway.gov.tw/tra-tip-web/tip/tip001/tip112/querybystationblank?station=7190))
- **逆行首末班概況**：可見 04:45、05:11、05:44 等班次。([railway.gov.tw](https://www.railway.gov.tw/tra-tip-web/tip/tip001/tip112/querybystationblank?station=7190))

## 3. 可追查來源
- **臺鐵官方網站** https://www.railway.gov.tw/tra-tip-web/tip/tip00H/tipH41/viewStaInfo/7190
- **官方時刻表查詢** https://www.railway.gov.tw/tra-tip-web/tip/tip001/tip112/querybystationblank?station=7190

## 4. 下一步
請告訴我要查「宜蘭到哪一站」或「順行／逆行」，我就能幫你整理剩餘可搭班次。

## 5. 時間提醒
今日時刻表會變動，出發前請再確認一次。
''',
                    'output': [
                      {
                        'type': 'message',
                        'content': [
                          {
                            'type': 'output_text',
                            'text': '已搜尋臺鐵官方資料。',
                            'annotations': [
                              {
                                'type': 'url_citation',
                                'title': '臺鐵官方網站',
                                'url':
                                    'https://www.railway.gov.tw/tra-tip-web/tip/tip00H/tipH41/viewStaInfo/7190',
                              },
                            ],
                          },
                        ],
                      },
                    ],
                  },
                ),
              );
            },
          ),
        );

      final adapter = OpenAiBrowseAdapter(dio: dio);
      final result = await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.browse,
          prompt: '今天宜蘭火車站時刻表',
          provider: 'openai',
        ),
      );

      expect(result.status, BridgeActionStatus.completed);
      expect(result.message, contains('搜尋摘要'));
      expect(result.message, contains('關鍵重點'));
      expect(result.message, contains('下一步'));
      expect(result.message, contains('時間提醒'));
      expect(result.message, contains('臺鐵官方時刻表'));
      expect(result.message, isNot(contains('##')));
      expect(result.message, isNot(contains('**')));
      expect(result.message, isNot(contains('https://')));
      expect(result.message, isNot(contains('可追查來源')));
      expect(result.message, isNot(contains('官方時刻表查詢')));
      expect(result.metadata?['sourceCount'], 1);
      expect(result.metadata?['sourceHealth'], 'sources_available');
    },
  );

  test('OpenAI browse adapter routes setup errors to capability gap', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.saveToken('test-token', provider: 'openai');

    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response<dynamic>(
                  requestOptions: options,
                  statusCode: 400,
                  data: const {
                    'error': {
                      'message':
                          'The web_search tool is not enabled for this account.',
                    },
                  },
                ),
              ),
            );
          },
        ),
      );

    final adapter = OpenAiBrowseAdapter(dio: dio);
    final result = await adapter.execute(
      const BridgeAction(
        type: BridgeActionType.browse,
        prompt: '今天有什麼 AI 新聞？',
        provider: 'openai',
      ),
    );

    expect(result.status, BridgeActionStatus.needsProvider);
    expect(result.metadata?['kind'], 'capability_gap');
    expect(result.metadata?['setupRoute'], '/golden-keys?returnTo=/chat');
    final evidence = const BridgeActionExecutionEvidence().describe(result);
    expect(evidence, contains('能力缺口證據'));
    expect(evidence, contains('開通入口 /golden-keys?returnTo=/chat'));
  });

  test(
    'OpenAI browse adapter times out with actionable Chinese message',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('test-token', provider: 'openai');

      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              await Future<void>.delayed(const Duration(milliseconds: 60));
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {'output_text': 'too late'},
                ),
              );
            },
          ),
        );

      final adapter = OpenAiBrowseAdapter(
        dio: dio,
        timeout: const Duration(milliseconds: 10),
      );
      final result = await adapter.execute(
        const BridgeAction(
          type: BridgeActionType.browse,
          prompt: '今天有什麼 AI 新聞？',
          provider: 'openai',
        ),
      );

      expect(result.status, BridgeActionStatus.unsupported);
      expect(result.message, contains('網頁搜尋逾時'));
      expect(result.message, contains('更精準的關鍵字'));
      expect(result.metadata?['sourceHealth'], 'timeout');
    },
  );

  test('executor delegates matching action to registered adapter', () async {
    final executor = BridgeActionExecutor(
      registry: BridgeAdapterRegistry(adapters: [_FakeImageAdapter()]),
    );

    final result = await executor.execute(
      const BridgeAction(
        type: BridgeActionType.generateImage,
        prompt: 'a bridge registry test',
        provider: 'fake',
      ),
    );

    expect(result.status, BridgeActionStatus.completed);
    // [2026-09-22] mediaUrl 已拔（觸發資產掃描掛死）——改驗 provider
    expect(result.metadata?['provider'], 'fake');
    expect(result.metadata?['provider'], 'fake');
  });

  test('executor delegates vision action to registered adapter', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.saveToken('fake-token', provider: 'fake_vision');

    final executor = BridgeActionExecutor(
      registry: BridgeAdapterRegistry(adapters: [_FakeVisionAdapter()]),
    );

    final result = await executor.execute(
      const BridgeAction(
        type: BridgeActionType.vision,
        prompt: 'describe this image',
        referenceImagePaths: ['data:image/png;base64,aGVsbG8='],
      ),
    );

    expect(result.status, BridgeActionStatus.completed);
    expect(result.message, contains('fake vision'));
    expect(result.metadata?['provider'], 'fake_vision');
  });

  test(
    'executor asks before running action when routing rule requires it',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('fake-token', provider: 'fake');
      await const TaskRoutingRuleStore().saveRule(
        'creative-image',
        TaskRoutingRuleMode.askEveryTime,
      );

      final registry = BridgeAdapterRegistry(
        adapters: [_FakeProviderImageAdapter('fake')],
      );
      final executor = BridgeActionExecutor(
        registry: registry,
        decisionService: BridgeActionExecutionDecisionService(
          healthService: CapabilityHealthService(registry: registry),
        ),
      );

      final result = await executor.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'a cautious bridge mascot',
        ),
      );

      expect(result.status, BridgeActionStatus.needsConfirmation);
      expect(result.message, contains('需要確認'));
      expect(
        result.metadata?['executionDecision'],
        isA<Map<String, Object?>>(),
      );
    },
  );

  test(
    'executor runs confirmed action even when routing rule asks first',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('fake-token', provider: 'fake');
      await const TaskRoutingRuleStore().saveRule(
        'creative-image',
        TaskRoutingRuleMode.askEveryTime,
      );

      final registry = BridgeAdapterRegistry(
        adapters: [_FakeProviderImageAdapter('fake')],
      );
      final executor = BridgeActionExecutor(
        registry: registry,
        decisionService: BridgeActionExecutionDecisionService(
          healthService: CapabilityHealthService(registry: registry),
        ),
      );

      final result = await executor.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'a confirmed bridge mascot',
        ),
        confirmed: true,
      );

      expect(result.status, BridgeActionStatus.completed);
      // [2026-09-22] mediaUrl 已拔（觸發資產掃描掛死）——改驗 provider
    expect(result.metadata?['provider'], 'fake');
      expect(
        result.metadata?['executionDecision'],
        isA<Map<String, Object?>>(),
      );
    },
  );

  test(
    'executor applies one-shot cloud override from confirmation card',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('fake-token', provider: 'fake');
      await const TaskRoutingRuleStore().saveRule(
        'creative-image',
        TaskRoutingRuleMode.askEveryTime,
      );

      final registry = BridgeAdapterRegistry(
        adapters: [_FakeProviderImageAdapter('fake')],
      );
      final executor = BridgeActionExecutor(
        registry: registry,
        decisionService: BridgeActionExecutionDecisionService(
          healthService: CapabilityHealthService(registry: registry),
        ),
      );

      final result = await executor.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'a cloud-routed bridge mascot',
        ),
        confirmed: true,
        executionOverride: BridgeActionExecutionOverride.cloudFirst,
      );

      final decision =
          result.metadata?['executionDecision'] as Map<String, Object?>?;
      expect(result.status, BridgeActionStatus.completed);
      expect(
        decision?['override'],
        BridgeActionExecutionOverride.cloudFirst.name,
      );
      expect(decision?['mode'], BridgeActionExecutionMode.cloudFirst.name);
      final evidence = const BridgeActionExecutionEvidence().describe(result);
      expect(evidence, contains('本次選擇 雲端'));
      expect(evidence, contains('決策 雲端優先'));
      expect(evidence, contains('服務 fake'));
    },
  );

  test(
    'executor blocks one-shot local image override when local route is unavailable',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('fake-token', provider: 'fake');

      final registry = BridgeAdapterRegistry(
        adapters: [_FakeProviderImageAdapter('fake')],
      );
      final executor = BridgeActionExecutor(
        registry: registry,
        decisionService: BridgeActionExecutionDecisionService(
          healthService: CapabilityHealthService(registry: registry),
        ),
      );

      final result = await executor.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'a local-only bridge mascot',
        ),
        confirmed: true,
        executionOverride: BridgeActionExecutionOverride.localFirst,
      );

      final decision =
          result.metadata?['executionDecision'] as Map<String, Object?>?;
      expect(result.status, BridgeActionStatus.needsProvider);
      expect(
        decision?['override'],
        BridgeActionExecutionOverride.localFirst.name,
      );
      expect(decision?['mode'], BridgeActionExecutionMode.blocked.name);
      expect(result.message, contains('本地模型'));
      expect(result.message, contains('連接桌面'));
    },
  );

  test(
    'executor attaches routing decision metadata when action runs',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveToken('fake-token', provider: 'fake');

      final registry = BridgeAdapterRegistry(
        adapters: [_FakeProviderImageAdapter('fake')],
      );
      final executor = BridgeActionExecutor(
        registry: registry,
        decisionService: BridgeActionExecutionDecisionService(
          healthService: CapabilityHealthService(registry: registry),
        ),
      );

      final result = await executor.execute(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'a routed bridge mascot',
        ),
      );

      final decision =
          result.metadata?['executionDecision'] as Map<String, Object?>?;
      expect(result.status, BridgeActionStatus.completed);
      expect(decision, isNotNull);
      expect(decision!['taskId'], 'creative-image');
      expect(decision['mode'], BridgeActionExecutionMode.cloudFirst.name);
    },
  );

  test(
    'capability router picks configured image provider beyond chat provider',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveProvider('kimi');
      await StorageService.saveToken('replicate-token', provider: 'replicate');

      final router = CapabilityRouter(
        registry: BridgeAdapterRegistry(
          adapters: [
            _FakeProviderImageAdapter('openai'),
            _FakeProviderImageAdapter('replicate'),
          ],
        ),
      );

      final route = await router.route(
        const BridgeAction(
          type: BridgeActionType.generateImage,
          prompt: 'a bridge that routes capabilities',
        ),
      );

      expect(route.provider, 'replicate');
      expect(route.reason, 'capability_provider');
    },
  );

  test('capability health reports routed image provider', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.saveProvider('kimi');
    await StorageService.saveToken('kimi-token', provider: 'kimi');
    await StorageService.saveToken('replicate-token', provider: 'replicate');

    final service = CapabilityHealthService(
      registry: BridgeAdapterRegistry(
        adapters: [
          _FakeProviderImageAdapter('openai'),
          _FakeProviderImageAdapter('replicate'),
        ],
      ),
    );

    final items = await service.inspect();
    final imageItem = items.firstWhere(
      (item) => item.type == BridgeActionType.generateImage,
    );
    final chatItem = items.firstWhere((item) => item.label == '聊天');

    expect(chatItem.status, CapabilityHealthStatus.ready);
    expect(imageItem.status, CapabilityHealthStatus.ready);
    expect(imageItem.providerLabel, 'replicate');
  });

  test(
    'capability health reports OpenAI vision provider when token exists',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveProvider('kimi');
      await StorageService.saveToken('kimi-token', provider: 'kimi');
      await StorageService.saveToken('openai-token', provider: 'openai');

      final items = await CapabilityHealthService().inspect();
      final visionItem = items.firstWhere(
        (item) => item.type == BridgeActionType.vision,
      );

      expect(visionItem.status, CapabilityHealthStatus.ready);
      expect(visionItem.providerLabel, 'OpenAI 圖片辨識');
    },
  );

  test(
    'capability health reports OpenAI browse provider when token exists',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveProvider('kimi');
      await StorageService.saveToken('kimi-token', provider: 'kimi');
      await StorageService.saveToken('openai-token', provider: 'openai');

      final items = await CapabilityHealthService().inspect();
      final browseItem = items.firstWhere(
        (item) => item.type == BridgeActionType.browse,
      );

      expect(browseItem.status, CapabilityHealthStatus.ready);
      expect(browseItem.providerLabel, 'OpenAI 網頁搜尋');
    },
  );

  test('capability health displays MiniMax as cloud brain provider', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.saveProvider('minimax');
    await StorageService.saveToken('minimax-token', provider: 'minimax');

    final items = await CapabilityHealthService().inspect();
    final chatItem = items.firstWhere((item) => item.label == '聊天');
    final compressionItem = items.firstWhere((item) => item.label == '語意壓縮');

    expect(chatItem.status, CapabilityHealthStatus.ready);
    expect(chatItem.providerLabel, 'MiniMax');
    expect(compressionItem.status, CapabilityHealthStatus.ready);
    expect(compressionItem.providerLabel, 'MiniMax');
  });

  test(
    'capability health recommends image provider setup when missing token',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveProvider('kimi');
      await StorageService.saveToken('kimi-token', provider: 'kimi');

      final service = CapabilityHealthService(
        registry: BridgeAdapterRegistry(
          adapters: [
            _FakeProviderImageAdapter('openai'),
            _FakeProviderImageAdapter('replicate'),
          ],
        ),
      );

      final items = await service.inspect();
      final imageItem = items.firstWhere(
        (item) => item.type == BridgeActionType.generateImage,
      );

      expect(imageItem.status, CapabilityHealthStatus.needsSetup);
      expect(imageItem.recommendedProvider, 'replicate');
    },
  );

  test(
    'live health check reports missing setup without network tokens',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      await StorageService.saveProvider('kimi');

      final service = CapabilityHealthService(
        registry: BridgeAdapterRegistry(
          adapters: [_FakeProviderImageAdapter('replicate')],
        ),
      );

      final items = await service.runLiveChecks();
      final chatItem = items.firstWhere((item) => item.label == '聊天實機');
      final imageItem = items.firstWhere((item) => item.label == '圖片實機');

      expect(chatItem.status, CapabilityHealthStatus.needsSetup);
      expect(imageItem.status, CapabilityHealthStatus.needsSetup);
    },
  );

  test('registry exposes document adapter for any selected provider', () {
    final registry = BridgeAdapterRegistry();
    final action = const BridgeAction(
      type: BridgeActionType.document,
      prompt: 'Meeting notes|Discuss bridge adapters',
    );

    expect(registry.findAdapter(action, 'openai'), isNotNull);
    expect(registry.findAdapter(action, 'replicate'), isNotNull);
  });

  test('stores API tokens separately by provider', () async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});

    await StorageService.saveToken('openai-token', provider: 'openai');
    await StorageService.saveToken('replicate-token', provider: 'replicate');

    expect(await StorageService.getToken(provider: 'openai'), 'openai-token');
    expect(
      await StorageService.getToken(provider: 'replicate'),
      'replicate-token',
    );
  });
}

class _FakeImageAdapter extends BridgeActionAdapter {
  @override
  String get id => 'fake';

  @override
  String get displayName => 'Fake Images';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    return const BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: 'fake image generated',
      // [2026-09-22] 拔掉 fake:// mediaUrl——executor 對 mediaUrl 會觸發
      // 資產索引掃描（_triggerAssetIngestion），fake:// 協議在 File IO
      // 掃描下讓測試環境掛起（did not complete）。這裡驗證的是
      // adapter 委派，不是媒體入庫。
      metadata: {'provider': 'fake'},
    );
  }
}

class _FakeVisionAdapter extends BridgeActionAdapter {
  @override
  String get id => 'fake_vision';

  @override
  String get displayName => 'Fake Vision';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.vision};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    return const BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: 'fake vision described the image',
      metadata: {'type': 'vision', 'provider': 'fake_vision', 'kind': 'vision'},
    );
  }
}

class _FakeProviderImageAdapter extends BridgeActionAdapter {
  final String providerId;

  _FakeProviderImageAdapter(this.providerId);

  @override
  String get id => providerId;

  @override
  String get displayName => providerId;

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.generateImage};

  @override
  bool canHandle(BridgeAction action, String provider) {
    return provider == id && supportedTypes.contains(action.type);
  }

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    return BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: '$id image generated',
      // [2026-09-22] 拔 fake:// mediaUrl——觸發資產掃描會讓測試掛死
      metadata: {'provider': id},
    );
  }
}
