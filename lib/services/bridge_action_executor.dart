import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/bridge_action.dart';
import 'bridge_adapters/bridge_action_adapter.dart';
import 'bridge_action_progress.dart';
import 'paid_action_gate.dart';
import 'budget_ledger.dart';

import 'bridge_action_execution_decision_service.dart';
import 'bridge_adapters/bridge_adapter_registry.dart';
import 'capability_router.dart';
import 'api_audit_log.dart';
import 'storage_service.dart';
import 'vector_db/asset_sandbox.dart';
import 'vision_probe.dart';
import 'vector_db/asset_index_service.dart';
import 'paid_action_gate.dart';

enum BridgeActionStatus {
  completed,
  needsProvider,
  needsConfirmation,
  unsupported,
}

class BridgeActionResult {
  final BridgeActionStatus status;
  final String message;
  final String? mediaUrl;
  final Map<String, dynamic>? metadata;

  const BridgeActionResult({
    required this.status,
    required this.message,
    this.mediaUrl,
    this.metadata,
  });

  factory BridgeActionResult.needsProvider(
    BridgeAction action,
    String reason, {
    String? provider,
  }) {
    return BridgeActionResult(
      status: BridgeActionStatus.needsProvider,
      message: '$reason：${action.prompt}',
      metadata: {
        'type': action.type.legacyType,
        'kind': 'capability_gap',
        'prompt': action.prompt,
        'provider': ?provider,
        'requestedProvider': ?action.provider,
        'setupRoute': _setupRouteFor(action.type),
        'evidenceKind': 'capability_gap',
      },
    );
  }

  /// [小葵 2026-09-14] fallback 可見性用：附加 metadata 並可覆寫訊息。
  BridgeActionResult copyWithMetadata(
    Map<String, dynamic> extraMetadata, {
    String? messageOverride,
  }) {
    return BridgeActionResult(
      status: status,
      message: messageOverride ?? message,
      mediaUrl: mediaUrl,
      metadata: {...?metadata, ...extraMetadata},
    );
  }
}

String _setupRouteFor(BridgeActionType type) {
  switch (type) {
    case BridgeActionType.browse:
    case BridgeActionType.vision:
    case BridgeActionType.generateImage:
    case BridgeActionType.generateAnimation:
    case BridgeActionType.generateMusic:
    case BridgeActionType.generateVideo:
      return '/golden-keys?returnTo=/chat';
    case BridgeActionType.document:
      return '/settings?returnTo=/chat';
    case BridgeActionType.desktopFiles:
      return '/desktop-shell?returnTo=/chat';
    case BridgeActionType.unknown:
      return '/golden-keys?returnTo=/chat';
  }
}

/// Central execution entrypoint for Bridge Actions.
///
/// Slice 1 starts here: UI no longer owns action execution. Provider-specific
/// adapters can plug into this service without changing chat bubbles.
class BridgeActionExecutor {
  BridgeActionExecutor({
    BridgeAdapterRegistry? registry,
    BridgeActionExecutionDecisionService? decisionService,
  }) : _registry = registry ?? BridgeAdapterRegistry(),
       _decisionService =
           decisionService ?? const BridgeActionExecutionDecisionService() {
    _router = CapabilityRouter(registry: _registry);
  }

  final BridgeAdapterRegistry _registry;
  final BridgeActionExecutionDecisionService _decisionService;
  
  // [教練 Agent 2026-08-09] debug——暴露最後一次 route 給 MCP
  String lastRouteDebug = 'none';
  final _progressController =
      StreamController<BridgeActionProgressEvent>.broadcast();
  Stream<BridgeActionProgressEvent> get progressStream =>
      _progressController.stream;
  late final CapabilityRouter _router;

  Future<BridgeActionResult> execute(
    BridgeAction action, {
    bool confirmed = false,
    BridgeActionExecutionOverride executionOverride =
        BridgeActionExecutionOverride.none,
  }) async {
    // [教練 Agent 2026-08-21] $33 根治——中央付費閘門（咽喉點）。
    // 不論哪條路進來（agent 工具、canvas 節點、sub-workflow、
    // CapabilityExecutor、explicit provider），付費動作一律過保險絲：
    // 每日上限檢查＋佔位。超過=誠實擋下。確認框是人這關，這是機械那關。
    final gateKind = _paidKindFor(action.type);
    if (gateKind != null) {
      // [教練 Agent 2026-08-21] 自我節流——同一 prompt 連續失敗 ≥2 次，
      // 必須換策略（改 prompt / 換服務），不得盲目第三次。$33 事件的
      // 重試螺旋在此斷開。
      final fails = await BudgetLedger.instance
          .consecutiveFailuresFor(action.prompt ?? '');
      if (fails >= 2) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: '此 prompt 已連續失敗 $fails 次。自律規則：重複同樣的動作'
              '只會得到同樣的結果——請改寫 prompt、換服務、或縮小請求後再試。',
          metadata: {
            'type': action.type.legacyType,
            'kind': 'self_throttle_blocked',
            'prompt': action.prompt,
          },
        );
      }

      // [教練 Agent 2026-08-21] Phase A——記帳（intent=動作型別+prompt 摘要）
      final verdict = await PaidActionGate.instance.checkAndReserve(
        gateKind,
        intent: action.type.legacyType,
        prompt: action.prompt,
      );
      if (!verdict.allowed) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: verdict.reason,
          metadata: {
            'type': action.type.legacyType,
            'kind': 'paid_gate_blocked',
            'prompt': action.prompt,
          },
        );
      }

      // [教練 Agent 2026-08-21] 執行後結案——成敗誠實寫回 Ledger
      final result = await _executeInner(action,
          confirmed: confirmed, executionOverride: executionOverride);
      await PaidActionGate.settle(verdict.ledgerId,
          ok: result.status == BridgeActionStatus.completed,
          error: result.status == BridgeActionStatus.completed
              ? null
              : result.message);
      return result;
    }

    return await _executeInner(action,
        confirmed: confirmed, executionOverride: executionOverride);
  }

  Future<BridgeActionResult> _executeInner(
    BridgeAction action, {
    bool confirmed = false,
    BridgeActionExecutionOverride executionOverride =
        BridgeActionExecutionOverride.none,
  }) async {
    switch (action.type) {
      case BridgeActionType.generateImage:
        if (_hasExplicitProvider(action)) return _executeWithAdapter(action);
        return _executeWithDecision(
          action,
          confirmed: confirmed,
          executionOverride: executionOverride,
        );
      case BridgeActionType.generateAnimation:
        if (_hasExplicitProvider(action)) return _executeWithAdapter(action);
        return _needsProvider(action, '動圖生成服務尚未設定；角色動態接口目前僅保留給未來插件');
      case BridgeActionType.generateMusic:
        if (_hasExplicitProvider(action)) return _executeWithAdapter(action);
        return _executeWithDecision(
          action,
          confirmed: confirmed,
          executionOverride: executionOverride,
        );
      case BridgeActionType.generateVideo:
        if (_hasExplicitProvider(action)) return _executeWithAdapter(action);
        return _executeWithDecision(
          action,
          confirmed: confirmed,
          executionOverride: executionOverride,
        );
      case BridgeActionType.browse:
        return _executeWithAdapter(action);
      case BridgeActionType.vision:
        return _executeVisionWithProbe(action);
      case BridgeActionType.document:
        if (_hasExplicitProvider(action)) return _executeWithAdapter(action);
        return _executeWithDecision(
          action,
          confirmed: confirmed,
          executionOverride: executionOverride,
        );
      case BridgeActionType.desktopFiles:
        return _executeWithAdapter(action);
      case BridgeActionType.unknown:
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: '尚不支援這個橋樑動作',
          metadata: {'prompt': action.prompt},
        );
    }
  }

  /// [教練 Agent 2026-08-21] 付費動作類型對照（中央閘門用）
  static PaidActionKind? _paidKindFor(BridgeActionType type) {
    switch (type) {
      case BridgeActionType.generateImage:
      case BridgeActionType.generateAnimation:
        return PaidActionKind.image;
      case BridgeActionType.generateVideo:
        return PaidActionKind.video;
      case BridgeActionType.generateMusic:
        return PaidActionKind.music;
      default:
        return null;
    }
  }

  bool _hasExplicitProvider(BridgeAction action) {
    final provider = action.provider;
    return provider != null && provider.trim().isNotEmpty;
  }

  Future<BridgeActionResult> _executeWithDecision(
    BridgeAction action, {
    required bool confirmed,
    required BridgeActionExecutionOverride executionOverride,
  }) async {
    final decision = await _decisionService.decide(
      action,
      override: executionOverride,
    );
    // [教練 Agent 2026-08-19] 未接入任務規則的動作回「尚未支援」誠實狀態——
    // 不冒充 needsProvider（缺 key），避免彈出「前往 尚未支援 平台註冊」的荒謬引導
    if (decision.taskId == 'unsupported') {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '${decision.label}功能尚未接入：這個能力還在開發中，'
            '設定 API Key 無法啟用它。',
        metadata: {
          'type': action.type.legacyType,
          'kind': 'unsupported',
          'prompt': action.prompt,
        },
      );
    }
    if (decision.shouldAskUser && !confirmed) {
      return BridgeActionResult(
        status: BridgeActionStatus.needsConfirmation,
        message:
            '${decision.label}需要確認：${decision.reason} 目前建議 ${decision.primaryKey}。',
        metadata: {
          'type': action.type.legacyType,
          'kind': 'confirmation',
          'prompt': action.prompt,
          'executionDecision': decision.toMetadata(),
        },
      );
    }
    if (!decision.canExecute) {
      return BridgeActionResult(
        status: BridgeActionStatus.needsProvider,
        message: '${decision.label}尚未就緒：${decision.reason}：${action.prompt}',
        metadata: {
          'type': action.type.legacyType,
          'kind': 'capability_gap',
          'prompt': action.prompt,
          'provider': decision.primaryKey,
          'requestedProvider': action.provider,
          'executionDecision': decision.toMetadata(),
          'setupRoute': _setupRouteFor(action.type),
          'evidenceKind': 'capability_gap',
        },
      );
    }

    final result = await _executeWithAdapter(action);
    return BridgeActionResult(
      status: result.status,
      message: result.message,
      mediaUrl: result.mediaUrl,
      metadata: {
        ...?result.metadata,
        'executionDecision': decision.toMetadata(),
      },
    );
  }

  Future<BridgeActionResult> _executeWithAdapter(BridgeAction action) async {
    final route = await _router.route(action);
    // [教練 Agent 2026-08-09] debug——看 router 選了誰
    lastRouteDebug = 'adapter=${route.adapter?.id}, provider=${route.provider}, reason=${route.reason}, actionProvider=${action.provider}';
    final adapter = route.adapter;
    if (adapter == null) {
      // 使用者明確指定的 provider 沒有對應 adapter 時，這是產品能力尚未實作，
      // 不是 token 或設定問題。必須直接說清楚，不能讓 Agent 猜測後轉去 vision。
      if (action.provider != null && action.provider!.trim().isNotEmpty) {
        final supported = _registry
            .adaptersFor(action.type)
            .map((item) => item.id)
            .toList(growable: false);
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message:
              '目前尚未實作「${route.provider}」的${action.displayType} adapter。'
              '你的 API 額度不代表 Bridge 已能呼叫它。'
              '${supported.isEmpty ? '' : '目前此 App 可用：${supported.join('、')}。'}',
          metadata: {
            'type': action.type.legacyType,
            'kind': 'provider_adapter_unavailable',
            'requestedProvider': route.provider,
            'supportedProviders': supported,
            'setupRoute': _setupRouteFor(action.type),
          },
        );
      }
      return _needsProvider(
        action,
        route.candidateProviders.isEmpty
            ? '${action.displayType}執行橋尚未設定'
            : '${action.displayType}目前尚未連接可用服務',
        provider: route.provider,
      );
    }

    if (action.type == BridgeActionType.generateImage) {
      _emitImageProgress(
        action,
        BridgeActionProgressStage.adapterSelected,
        provider: adapter.id,
      );
      // 這表示 Bridge 已選定 adapter、準備呼叫；尚不代表 provider 已受理。
      _emitImageProgress(
        action,
        BridgeActionProgressStage.requestAboutToSend,
        provider: adapter.id,
      );
    }

    // [小葵 2026-09-14] 主權鐵則：使用者明確指定的 provider 不做靜默 fallback。
    // 舊行為：指定 MiniMax → MiniMax 失敗 → 靜默改用 OpenAI（帳單給了別人）。
    // 新行為：指定了 provider 就只用該 provider，失敗誠實回報，換家由使用者決定。
    // 自動選擇（未指定 provider）情境仍保留 fallback，但會在 metadata 標記。
    final bool userPinnedProvider =
        action.provider != null && action.provider!.trim().isNotEmpty;

    // [教練 Agent 2026-08-09] Adapter fallback——第一個失敗自動試下一個
    // 使用者的洞察：工具執行失敗時應該自動嘗試其他 provider
    // [小葵 2026-09-14] userPinnedProvider 時 tryOrder 只含指定 adapter。
    BridgeActionResult? result;

    // 構建嘗試順序：route.adapter 優先，然後其他 ready 的 adapter
    final tried = <String>{};
    final candidates = _registry.adaptersFor(action.type);
    final tryOrder = <BridgeActionAdapter>[];
    tryOrder.add(adapter);
    for (final c in candidates) {
      if (c.id != adapter.id && !tried.contains(c.id)) {
        final token = await StorageService.getToken(provider: c.id);
        if (token != null && token.trim().isNotEmpty) tryOrder.add(c);
      }
      tried.add(c.id);
    }
    if (userPinnedProvider) {
      tryOrder.removeWhere((a) => a.id != route.provider);
    }

    for (int i = 0; i < tryOrder.length; i++) {
      final tryAdapter = tryOrder[i];
      if (action.type == BridgeActionType.generateImage) {
        _emitImageProgress(action, BridgeActionProgressStage.adapterSelected, provider: tryAdapter.id);
        _emitImageProgress(action, BridgeActionProgressStage.requestAboutToSend, provider: tryAdapter.id);
        if (i > 0) lastRouteDebug = 'fallback #${i + 1}: ${tryAdapter.id}';
      }
      
      result = await tryAdapter.execute(action);
      final r = result;
      // [小葵 2026-09-14] 本地記帳：每次 API 調用都留痕
      await ApiAuditLog.record(
        provider: tryAdapter.id,
        actionType: action.type.name,
        model: r.metadata?['model']?.toString(),
        quality: r.metadata?['quality']?.toString() ?? action.imageQuality,
        promptSummary: action.prompt,
        success: r.status == BridgeActionStatus.completed,
        failReason: r.status == BridgeActionStatus.completed
            ? null
            : r.message,
        usage: ApiAuditLog.usageFromMetadata(r.metadata),
      );
      
      if (r.status == BridgeActionStatus.completed) {
        // 成功！
        if (action.type == BridgeActionType.generateImage) {
          final provider = r.metadata?['provider']?.toString() ?? tryAdapter.id;
          final model = r.metadata?['model']?.toString();
          _emitImageProgress(action, BridgeActionProgressStage.responseReceived, provider: provider, model: model);
          if (r.mediaUrl != null && r.mediaUrl!.isNotEmpty) {
            _emitImageProgress(action, BridgeActionProgressStage.mediaPersisted, provider: provider, model: model);
            _triggerAssetIngestion(r.mediaUrl!);
          }
        }
        // [小葵 2026-09-14] fallback 可見性：自動選擇情境下換了家，要在結果裡講清楚
        if (i > 0 && !userPinnedProvider) {
          final requested = route.provider ?? tryAdapter.id;
          final actual = r.metadata?['provider']?.toString() ?? tryAdapter.id;
          return r.copyWithMetadata({
            'fallbackOccurred': true,
            'requestedProvider': requested,
            'actualProvider': actual,
          }, messageOverride:
              '${r.message}\n（${requested == actual ? requested : "$requested 失敗，已自動改用 $actual"}）');
        }
        return r;
      }
      
      // 失敗——還有下一個就繼續試
      if (i < tryOrder.length - 1) {
        debugPrint('[BridgeActionExecutor] ${tryAdapter.id} 失敗，嘗試 fallback...');
      }
    }

    // 所有 adapter 都失敗（或沒有可用的）
    if (tryOrder.isEmpty) {
      return BridgeActionResult(
        status: BridgeActionStatus.needsProvider,
        message: '沒有可用的${action.displayType}服務',
      );
    }
    return result ?? BridgeActionResult(
      status: BridgeActionStatus.needsProvider,
      message: '${action.displayType}執行失敗',
    );
  }

  /// [教練 Agent P2 2026-08-08] Vision 執行加 probe 保護
  ///
  /// P2 合約：
  /// 1. 如果目前 provider 是 local → 先 probe 確認本地模型支援 vision
  /// 2. probe 不支援 → 回明確訊息，不沉默失敗
  /// 3. 不因圖片生成失敗就自動轉 vision
  /// 4. timeout 與顯示文字統一
  Future<BridgeActionResult> _executeVisionWithProbe(
    BridgeAction action,
  ) async {
    // 檢查是否使用本地模型
    final provider = await StorageService.getProvider() ?? 'kimi';
    final isLocal = provider == 'local' ||
        provider.contains('127.0.0.1') ||
        provider.contains('localhost') ||
        provider.contains('18789');

    if (isLocal) {
      // P2 要求：probe llama-server 是否接受 vision multimodal request
      final baseUrl = await StorageService.getGatewayUrl();
      final serverUrl = baseUrl ?? 'http://127.0.0.1:18789';

      final probe = VisionProbe();
      final probeResult = await probe.check(serverUrl);

      if (!probeResult.supported) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: probeResult.reason ?? '本地模型不支援圖片辨識',
          metadata: {
            'type': action.type.legacyType,
            'kind': 'vision_not_supported',
            'modelId': probeResult.modelId,
            'elapsed_ms': probeResult.elapsedMs,
          },
        );
      }
    }

    // probe 通過或不是 local → 正常走 adapter
    return _executeWithAdapter(action);
  }

  /// [教練 Agent P0.6c 2026-08-07] 檔案落盤後立即觸發向量嵌入。
  ///
  /// 非同步執行，不阻塞對話。確保 bridge_media/ 在 sandbox 裡，
  /// 然後增量掃描該檔案所在的根目錄。嵌入失敗只記 log，不影響圖片顯示。
  void _triggerAssetIngestion(String filePath) {
    Future(() async {
      try {
        final sandbox = AssetSandbox();
        // 確保 bridge_media/ 在受管範圍內
        final file = File(filePath);
        final parent = file.parent;
        // 往上找到 bridge_media/ 根目錄
        String? mediaRoot;
        Directory? dir = parent;
        while (dir != null) {
          if (dir.path.endsWith('bridge_media')) {
            mediaRoot = dir.path;
            break;
          }
          dir = dir.parent;
        }
        if (mediaRoot != null && !sandbox.rootPaths.contains(mediaRoot)) {
          sandbox.addFolder(mediaRoot);
        }
        // 增量掃描（只掃新檔案，已索引的會跳過）
        final indexService = AssetIndexService();
        final root = mediaRoot ?? parent.path;
        await indexService.fullScan(root);
        debugPrint('[BridgeActionExecutor] 向量嵌入已觸發: $filePath');
      } catch (e) {
        debugPrint('[BridgeActionExecutor] 向量嵌入失敗（不影響圖片顯示）: $e');
      }
    });
  }

  void _emitImageProgress(
    BridgeAction action,
    BridgeActionProgressStage stage, {
    String? provider,
    String? model,
  }) {
    _progressController.add(
      BridgeActionProgressEvent(
        actionType: action.type,
        stage: stage,
        occurredAt: DateTime.now(),
        provider: provider,
        model: model,
        // 只傳 Agent tool 已送出的使用者可讀圖片描述；不傳 system prompt / token。
        prompt: action.prompt,
      ),
    );
  }

  BridgeActionResult _needsProvider(
    BridgeAction action,
    String reason, {
    String? provider,
  }) {
    return BridgeActionResult.needsProvider(action, reason, provider: provider);
  }
}
