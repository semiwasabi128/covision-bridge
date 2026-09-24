// ignore_for_file: unused_element, unused_field
import 'dart:async';
// import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:bridge_app/services/routines/move_intent_clarifier.dart'; // [Blue 拍板] 招式釐清通道
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'chat/handlers/chat_tts_handler.dart';
import 'chat/handlers/chat_memory_handler.dart';
import 'chat/helpers/bridge_insight_helper.dart';
import 'chat/helpers/capability_gap_helper.dart';
import 'chat/helpers/card_parsers.dart';
import 'chat/helpers/chat_misc_helpers.dart';
import 'chat/helpers/skill_chip_prefixes.dart';
import 'chat/handlers/digital_asset_invocation_handler.dart';
import 'chat/widgets/empty_chat_state.dart';
import 'chat/widgets/message_extras.dart';
import 'chat/widgets/thinking_panel.dart';
import 'chat/widgets/stream_confluence_overlay.dart';
import 'chat/widgets/brain_reflection_panel_data.dart';
import 'chat/widgets/message_bubble.dart';
import 'chat/widgets/app_bar_widgets.dart';
import 'chat/widgets/chat_app_bar.dart';
import 'chat/widgets/skill_chip_panel.dart';
import 'chat/widgets/agent_loop_progress.dart';
import '../widgets/chat/message_context_menu.dart';
import 'chat/handlers/desktop_organize_handler.dart';
import 'chat/handlers/bridge_result_handler.dart';
import 'chat/handlers/pending_task_handler.dart';
import 'chat/handlers/chat_message_appender.dart';
import 'chat/handlers/bridge_action_status_handler.dart';
import 'chat/handlers/second_brain_import_handler.dart';
import '../models/bridge_action.dart';
import '../models/digital_asset.dart';
import '../models/second_brain_file_index.dart';
import '../models/transurfing_brain.dart';
import '../models/conversation.dart';
import '../services/agent_motivation_engine.dart';
// import '../services/api_service.dart';
import '../services/conversation_store.dart';
import '../services/door_decision_store.dart';
import '../services/bridge_consciousness.dart';
import '../services/bridge_action_execution_decision_service.dart';
import '../services/bridge_action_execution_evidence.dart';
import '../services/bridge_action_executor.dart';
import '../services/bridge_adapters/local_desktop_files_adapter.dart';
import '../services/capability_activation_signal.dart';
import '../services/capability_catalog_service.dart';
import '../services/capability_health_service.dart';
import '../services/digital_asset_registry_store.dart';
import '../services/intent_classifier.dart';
// import '../services/intent_spine_service.dart';
import '../services/js_bridge.dart';
import '../services/managed_folder_guard_store.dart';
import '../services/managed_folder_rule_namer.dart';
import '../services/managed_folder_rule_store.dart';
import '../services/companion_store.dart';
import '../services/pending_bridge_task_store.dart';
import '../services/project_door_store.dart';
import '../services/second_brain_file_index_store.dart';
import '../services/second_brain_folder_import_service.dart';
import '../services/second_brain_trace_service.dart';
import '../services/transurfing_brain_service.dart';
import '../services/bridge_action_progress.dart';
import '../theme/app_theme.dart';
import '../models/chat_card_data.dart'; // [以利沙 Sprint 1 2026-06-24]
import '../widgets/chat/chat_input_bar.dart'; // [以利沙 Sprint 3 2026-06-24]
import '../widgets/chat/task_progress_card.dart'; // [隊友訊息流 C3]
import '../widgets/chat/task_delivery_card.dart'; // [隊友訊息流 C4]
import '../services/tasks/task_dispatcher.dart'; // [隊友訊息流 C3]
import '../services/tasks/task_intent_classifier.dart'; // [隊友訊息流 C6]
import '../widgets/canvas/v2/canvas_mcp_registry.dart'; // [隊友訊息流 C3]
import '../widgets/chat/agent_model_selector.dart'; // Agent 模型選擇器
import '../widgets/chat/chat_sidebar.dart'; // [以利沙 Sprint 4 2026-06-24]
import '../widgets/companion_presence_layer.dart'; // [以利沙 Sprint 7 2026-06-24]
// ignore: unused_import
import '../controllers/chat_controller.dart';
import '../theme/bridge_design_system.dart';
// ── Voice AI 引擎 ──
import '../../services/voice/voice_engine.dart';
import '../services/voice/native_audio_bytes_player.dart';
import '../services/voice/voice_live_controller.dart';
// [教練 Agent 2026-08-03] C4: 夥伴語音設定
import '../../services/voice/companion_voice_settings.dart';
import '../../services/voice/companion_voice_settings_store.dart';
import 'chat/handlers/voice_speech_handler.dart'; // [教練 Agent 2026-07-28] Voice AI 語音辨識
import '../services/voice/voice_state_machine.dart' show VoiceState;
import '../widgets/voice/voice_button.dart';
import '../widgets/voice/voice_status_indicator.dart';
import '../widgets/policy_confirm_dialog.dart'; // [教練 Agent 2026-07-30 Phase 4]
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import 'bridge_desktop_screen.dart';

class ChatScreen extends StatefulWidget {
  final BridgeActionExecutor? bridgeActionExecutor;
  final CapabilityHealthService? capabilityHealthService;
  final bool autoResumePendingTaskOnStartup;

  const ChatScreen({
    super.key,
    this.bridgeActionExecutor,
    this.capabilityHealthService,
    this.autoResumePendingTaskOnStartup = true,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}


class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode(debugLabel: 'chat-message-input');
  final _scrollController = ScrollController();
  final _titleController = TextEditingController();

  /// [TRIO M3.5 2026-09-22] 白話開會偵測——保守規則（寧可漏觸發，
  /// 不可把閒聊誤開會——與 TaskIntentClassifier 同哲學）。
  /// 命中條件 = 含「開會」語幹 AND（團隊/夥伴/Agent/我們）語境詞
  bool _isMeetingIntent(String text) {
    final hasMeetingStem =
        text.contains('開個會') || text.contains('開會') || text.contains('會議');
    if (!hasMeetingStem) return false;
    const ctxWords = ['團隊', '夥伴', 'Agent', 'agent', '我們', '大家'];
    return ctxWords.any(text.contains);
  }

  // [教練 Agent 2026-07-22] Phase H — 回覆指定訊息的目標
  Message? _replyTargetMessage;

  late final ChatTtsHandler _tts;

  late final ChatMemoryHandler _memory;

  late final ChatController _controller;

  // ── Voice AI 引擎（五層回應架構）──
  late VoiceEngine _voiceEngine;
  late final NativeAudioBytesPlayer _audioPlayer;

  // [教練 Agent 2026-07-28] Voice AI 專用語音辨識 — 只驅動 VoiceEngine，不碰輸入框
  late final VoiceSpeechHandler _voiceSpeech;

  // [教練 Agent 2026-08-03] 雙向溝通中央控制器
  VoiceLiveController? _voiceLive;

  /// [教練 Agent 2026-08-03] 麥克風真實音量（0.0~1.0）— 從 voice_speech_handler 訂閱
  /// 用 ValueNotifier — stream.listen 直接寫 value，不 setState（避免整個 panel 重建）
  final ValueNotifier<double> _micVolume = ValueNotifier<double>(0.0);
  StreamSubscription<double>? _micVolumeSub;

  /// [教練 Agent 2026-08-03] 語音開始前輸入框已有的文字（partial 會疊加上去）
  String _draftBeforeVoice = '';
  StreamSubscription<String>? _partialTextSub;

  /// [教練 Agent 2026-08-03] STT 狀態 → VoiceMode
  /// 純 STT 語音輸入：按下開始 → 講話 → 再按停止 → 文字送出
  /// - idle → 沒在錄音
  /// - listening → 正在錄音（按下變紅 + 波形動）
  /// - thinking/speaking → 不會觸發（純 STT 模式）
  VoiceMode get _voiceMode => _voiceSpeech.isListening ? VoiceMode.listening : VoiceMode.idle;

  /// [教練 Agent 2026-07-04] 測試用：直接取得 controller 以 await sendMessage()
  @visibleForTesting
  ChatController get controllerForTesting => _controller;

  /// [教練 Agent 2026-07-04] 測試用：直接注入 pendingBridgeTask，繞過 _init() File I/O
  @visibleForTesting
  set pendingBridgeTaskForTesting(PendingBridgeTask? task) =>
      _controller.pendingBridgeTask = task;

  /// [教練 Agent 2026-07-04] 測試用：直接注入 currentConversation，繞過 _init() File I/O
  @visibleForTesting
  set currentConversationForTesting(Conversation? conv) =>
      _controller.currentConversation = conv;

  /// [教練 Agent 2026-07-04] 測試用：直接呼叫 _tryAutoResumePendingBridgeTask
  @visibleForTesting
  Future<void> tryAutoResumePendingBridgeTaskForTesting(
    PendingBridgeTask task, {
    CapabilityActivationSignal? signal,
  }) =>
      _tryAutoResumePendingBridgeTask(task, signal: signal);

  bool _showSkillPanel = false; // 顯示 Skill 快捷面板
  bool _showCompanionPresence = true;
  Timer? _memoryFlashTimer;
  Timer? _thoughtPulseTimer;

  // [教練 Agent S21d] Agent Loop 進度
  int? _agentLoopTurn;
  int? _agentLoopMaxTurns;
  String? _agentLoopToolName;
  String? _agentLoopToolStatus;

  /// [小葵 2026-09-18] Agent Loop 思路+動作日誌（環形 200 行）
  final List<String> _agentLoopLog = [];
  void _pushLoopLog(String line) {
    _agentLoopLog.add(line);
    if (_agentLoopLog.length > 200) _agentLoopLog.removeAt(0);
  }
  String? _agentLoopStage; // [教練 Agent 2026-08-08] 統一 stage callback
  String? _agentLoopStageDetail;
  BridgeActionExecutor get _bridgeActionExecutor =>
      _controller.bridgeActionExecutor;
  final _bridgeActionEvidence = const BridgeActionExecutionEvidence();
  final _pendingBridgeTaskStore = const PendingBridgeTaskStore();
  final _doorDecisionStore = const DoorDecisionStore();
  final _projectDoorStore = const ProjectDoorStore();
  final _digitalAssetRegistry = const DigitalAssetRegistryStore();
  final _managedFolderRuleStore = const ManagedFolderRuleStore();
  final _managedFolderGuardStore = const ManagedFolderGuardStore();
  final _managedFolderRuleNamer = const ManagedFolderRuleNamer();
  final _transurfingBrain = const TransurfingBrainService();
  final _secondBrainFileIndexStore = const SecondBrainFileIndexStore();
  final _secondBrainTraceService = const SecondBrainTraceService();
  final _secondBrainFolderImportService =
      const SecondBrainFolderImportService();
  final _agentMotivationEngine = const AgentMotivationEngine();
  late final _capabilityCatalog = CapabilityCatalogService();
  late final _capabilityHealth =
      widget.capabilityHealthService ?? CapabilityHealthService();
  bool _autoResumingPendingTask = false;
  String? _selectedMessageId;
  String? _selectedMessageText;
  final Set<String> _completedDocumentWorkflowActions = {};


  @override
  void initState() {
    super.initState();
    _controller = ChatController();
    // [Blue 拍板 2026-09-12] 招式意圖釐清——掛全域對話通道
    // （訓練頁「讓夥伴重播」→ 這裡把釐清訊息送進對話，Agent 接手）
    // 照語音先例（L844）用 onGetMessageText 暫存 getter 模式——不動輸入框
    MoveIntentClarifier.onSendToGlobalChat = (msg) {
      final originalGetter = _controller.onGetMessageText;
      final originalSetter = _controller.onSetMessageText;
      _controller.onGetMessageText = () => msg;
      _controller.onSetMessageText = (_) {};
      _controller.sendMessage().then((_) {
        // 送完還原（非同步安全）
        _controller.onGetMessageText = originalGetter;
        _controller.onSetMessageText = originalSetter;
      });
    };
    _tts = ChatTtsHandler(onError: _showError);
    _tts.init();
    _audioPlayer = NativeAudioBytesPlayer();

    // ── Voice AI 引擎初始化 ──
    // VoiceEngine 接上既有的 ChatTtsHandler 做朗讀，
    // 並透過 AgentLoopTrigger 啟動背景運算（第三/四/五層回應）。
    // 暫時建構（會被 async 載入覆蓋）
    _voiceEngine = VoiceEngine(
      onSpeak: (text) => _tts.speak(text),
      onStopSpeaking: () => _tts.stop(),
      onPlayAudioBytes: (bytes) => _audioPlayer.play(bytes),
      onAgentLoopTrigger: ({
        required userText,
        required onProgress,
        required onComplete,
      }) {
        // 將使用者語音輸入轉發到 ChatController 的 AgentLoop
        // 並將中間/最終結果回傳給 VoiceEngine
        _triggerAgentLoopForVoice(
          userText: userText,
          onProgress: onProgress,
          onComplete: onComplete,
        );
      },
    );
    // VoiceEngine 狀態變化時更新 UI
    _voiceEngine.state.addListener(_onVoiceStateChanged);
    _loadVoiceSettingsAndBuild();

    // [教練 Agent 2026-07-28] Voice AI 專用語音辨識 — 只驅動 VoiceEngine
    // onError 時顯示麥克風權限提示 SnackBar
    _voiceSpeech = VoiceSpeechHandler(
      voiceEngine: _voiceEngine,
      onError: (msg) {
        debugPrint('[ChatScreen] VoiceSpeech: $msg');
        // 麥克風權限相關錯誤 → 顯示權限提示
        if (msg.contains('麥克風') || msg.contains('權限') || msg.contains('permission')) {
          _showError('麥克風權限未開啟，請到系統設定 > 隱私與安全 > 麥克風允許橋樑');
        } else {
          _showError(msg);
        }
      },
    );
    // [教練 Agent 2026-08-03] 訂閱 STT 真實音量
    _micVolumeSub = _voiceSpeech.amplitudeStream.listen((v) {
      // [教練 Agent 2026-08-03] 直接寫 ValueNotifier，不 setState 避免 panel 重建
      _micVolume.value = v;
    });
    // [教練 Agent 2026-08-03] 訂閱 STT 即時 partial 文字 → 直接寫入輸入框
    _partialTextSub = _voiceSpeech.partialTextStream.listen((text) {
      _messageController.text = _draftBeforeVoice.isEmpty
          ? text
          : '$_draftBeforeVoice$text';
      _messageController.selection = TextSelection.collapsed(
        offset: _messageController.text.length,
      );
    });
    _memory = ChatMemoryHandler(
      motivationEngine: _agentMotivationEngine,
      fileIndexStore: _secondBrainFileIndexStore,
      controller: _controller,
      activeCompanionGetter: () => _controller.activeCompanion,
      currentConversationGetter: () => _controller.currentConversation,
      onConversationUpdated: (conv) => setState(() => _controller.currentConversation = conv),
      onFlash: ({flashText, required showFlash, required brainPulse, motivation}) {
        if (!mounted) return;
        setState(() {
          _controller.memoryFlashText = flashText;
          _controller.showMemoryFlash = showFlash;
          _controller.brainPulse = brainPulse;
          if (motivation != null) _controller.agentMotivation = motivation;
        });
        if (mounted && flashText != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(flashText), duration: const Duration(seconds: 2)),
          );
        }
        _memoryFlashTimer?.cancel();
        _memoryFlashTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _controller.showMemoryFlash = false);
        });
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _controller.brainPulse = false);
        });
      },
      onFeedbackStateChanged: () { if (mounted) setState(() {}); },
      onError: _showError,
    );
    if (widget.bridgeActionExecutor != null) {
      _controller.bridgeActionExecutor = widget.bridgeActionExecutor!;
    }
    _controller.onScrollToBottom = _scrollToBottom;
    _controller.addListener(_syncFromController);
    _controller.onAppendLocalSystemMessage = (content) {
      _appendLocalSystemMessage(content);
    };
    _controller.onAppendBridgeResult = (result) async {
      await _appendBridgeResultMessage(result);
    };
    _controller.onShowError = _showError;
    _controller.onShowBridgeResultSnackBar = _showBridgeResultSnackBar;
    _controller.onAgentLoopProgress = (turnIndex, maxTurns, toolName, toolStatus, llmSnippet) {
      if (!mounted) return;
      setState(() {
        _agentLoopTurn = turnIndex + 1;
        _agentLoopMaxTurns = maxTurns;
        _agentLoopToolName = toolName;
        _agentLoopToolStatus = toolStatus;
        // [小葵 2026-09-18] Hermes 式透明化——思路與動作都進日誌
        if (llmSnippet.trim().isNotEmpty) {
          _pushLoopLog('💭 ${llmSnippet.trim().replaceAll('\n', ' ')}');
        }
        if (toolName != null) {
          _pushLoopLog('🔧 $toolName${toolStatus == 'failed' ? ' ✗' : ' ✓'}');
        }
      });
    };
    // [教練 Agent 2026-08-08] 統一 stage callback——三個對話框行為一致
    _controller.onAgentLoopStage = (stage, {toolName, detail}) {
      if (!mounted) return;
      setState(() {
        _agentLoopStage = stage;
        _agentLoopStageDetail = detail;
      });
    };
    _controller.onFocusMessageInput = _focusMessageInput;
    _controller.onClearMessageInput = () => _messageController.clear();
    _controller.onGetMessageText = () => _messageController.text;
    _controller.onSetMessageText = (text) => setState(() => _setMessageInputText(text)); // [以利沙 P1 任務延續 2026-06-26]
    _controller.onShowConsciousnessObservation = (observations) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.psychology, color: BridgeDSColors.of(context).textPrimary, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  observations.first.content,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                ),
              ),
            ],
          ),
          backgroundColor: BridgeDSColors.of(context).surfaceElevated,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: '知道了',
            textColor: BridgeDSColors.of(context).textPrimary,
            onPressed: () {
              BridgeConsciousness.markAsRead(observations.first.id);
            },
          ),
        ),
      );
    };
    // [教練 Agent 2026-07-30 Phase 4] 自訂調用原則確認對話框
    _controller.onShowPolicyConfirmDialog = (draft) async {
      if (!mounted) return null;
      return PolicyConfirmDialog.show(context, draft);
    };
    _loadActiveCompanion();
    if (kIsWeb) {
      debugPrint('[ChatScreen] initState');
    }
    _init();
    _controller.refreshLocalModelState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusMessageInput());
    // 監聽 JsBridge 命令
    JsBridge.instance.chatCommand.addListener(_handleBridgeCommand);
    CapabilityActivationBus.instance.latest.addListener(
      _handleCapabilityActivationSignal,
    );
    DoorDecisionStore.pendingReturn.addListener(_handlePendingDoorReturn);
    if (kIsWeb) {
      debugPrint('[ChatScreen] JsBridge listener registered');
    }
  }

  /// 同步 ChatController 的對話狀態回 _ChatScreenState。
  /// 讓 UI 層（build 方法等）能即時反映 controller 的變更。
  void _syncFromController() {
    if (!mounted) return;
    setState(() {
      // [教練 Agent S21d] loading 結束時清除 Agent Loop 進度
      if (!_controller.isLoading) {
        _agentLoopTurn = null;
        _agentLoopMaxTurns = null;
        _agentLoopToolName = null;
        _agentLoopToolStatus = null;
      }
    });
    _scrollToBottom();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _scrollToBottom(retry: 0);
    });
    if (_controller.pendingCompanionPickerRequest) {
      _controller.clearCompanionPickerRequest();
      _showCompanionPickerSheet();
    }
  }

  void _loadActiveCompanion() {
    _controller.loadActiveCompanion();
  }

  void _showCompanionPickerSheet() {
    showCompanionPickerSheet(
      context,
      companions: CompanionStore().all
          .where((c) => c.id != _controller.activeCompanion?.id)
          .toList(),
      autoTargetId: _controller.pendingAutoSwitchTarget,
      onSelected: (c) {
        _controller.clearPendingAutoSwitchTarget();
        _controller.switchToCompanionByRequest(c.id, '換個夥伴幫我');
      },
      onDismissed: () => _controller.clearPendingAutoSwitchTarget(),
    );
  }

  void _handleBridgeCommand() async {
    final command = JsBridge.instance.chatCommand.value;
    if (command == null) return;

    if (kIsWeb) {
      debugPrint('[ChatScreen] Bridge command: ${command['action']}');
    }

    switch (command['action']) {
      case 'send':
        final msg = command['message'] as String?;
        if (msg != null && msg.isNotEmpty) {
          _setMessageInputText(msg);
          if (kIsWeb) {
            debugPrint('[ChatScreen] Setting message: $msg');
          }
          try {
            await _controller.sendMessage();
          } catch (e, stack) {
            if (kIsWeb) {
              debugPrint('[ChatScreen] sendMessage error: $e');
              debugPrint('[ChatScreen] Stack: $stack');
            }
          }
        }
        break;
      case 'clear':
        _clearCurrentChat();
        break;
      case 'setMode':
        final mode = command['mode'] as String?;
        if (mode != null) {
          setState(() => _controller.currentMode = mode);
        }
        break;
    }
  }

  void _focusMessageInput() {
    if (!mounted || !_messageFocusNode.canRequestFocus) return;
    _messageFocusNode.requestFocus();
  }

  void _setMessageInputText(String text) {
    _messageController.text = text;
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
    _focusMessageInput();
  }

  Future<void> _init() async {
    await _loadConversations();
    _restoreBrainReflectionSnapshot();
    await _loadPendingBridgeTask();
    await _loadPendingDoorReturn();
    await _loadActiveProjectDoor();
    await _loadManagedFolderRules();
    await _controller.loadUnlockedCapabilities();
  }

  void _restoreBrainReflectionSnapshot() {
    _controller.restoreBrainReflectionSnapshot();
  }

  Future<void> _loadPendingDoorReturn() => _controller.loadPendingDoorReturn();

  Future<void> _loadActiveProjectDoor() => _controller.loadActiveProjectDoor();

  Future<void> _loadManagedFolderRules() =>
      _controller.loadManagedFolderRules();

  void _handlePendingDoorReturn() {
    _controller.handlePendingDoorReturn();
  }

  // TODO: needs context — SnackBar 需要 BuildContext，保留在 State 層。
  Future<void> _chooseDoorDecision(
    DoorDecision decision,
    DoorDecisionChoice choice,
  ) async {
    await _controller.chooseDoorDecision(decision, choice);
    if (!mounted) return;
    final pending = _controller.currentPendingDoorReturn;
    if (pending == null) return;
    final chosenLabel = switch (choice) {
      DoorDecisionChoice.mainline => decision.mainlineLabel,
      DoorDecisionChoice.branch => decision.branchLabel,
      DoorDecisionChoice.pause => '暫存這扇門',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已選擇「$chosenLabel」，並記住「${pending.deferredLabel}」。'),
      ),
    );
  }

  // TODO: needs context — SnackBar / TextEditingController 需要 BuildContext，保留在 State 層。
  void _resumePendingDoorReturn() {
    final pending = _controller.currentPendingDoorReturn;
    if (pending == null) return;
    _setMessageInputText(pending.returnPrompt);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已把「${pending.deferredLabel}」放回輸入框。')),
    );
  }

  Future<void> _clearPendingDoorReturn() async {
    await _doorDecisionStore.clearPendingReturn(
      decisionId: _controller.pendingDoorReturn?.decisionId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('待回流門已完成。')));
  }

  PendingTaskHandler _pendingTaskHandler() => PendingTaskHandler(
    PendingTaskHandlerConfig(
      pendingBridgeTaskStore: _pendingBridgeTaskStore,
      bridgeActionExecutor: _bridgeActionExecutor,
      getPendingBridgeTask: () => _controller.pendingBridgeTask,
      setPendingBridgeTask: (v) => _controller.pendingBridgeTask = v,
      getAutoResumingPendingTask: () => _autoResumingPendingTask,
      setAutoResumingPendingTask: (v) => _autoResumingPendingTask = v,
      autoResumePendingTaskOnStartup: widget.autoResumePendingTaskOnStartup,
      mounted: () => mounted,
      setState: setState,
      context: () => context,
      appendLocalSystemMessage: _appendLocalSystemMessage,
      appendBridgeResultMessage: _appendBridgeResultMessage,
      appendBridgeConfirmationMessage: _appendBridgeConfirmationMessage,
      setMessageInputText: _setMessageInputText,
    ),
  );

  Future<void> _loadPendingBridgeTask() =>
      _pendingTaskHandler().loadPendingBridgeTask();

  void _handleCapabilityActivationSignal() {
    _controller.refreshLocalModelState();
    final signal = CapabilityActivationBus.instance.latest.value;
    final task = _controller.pendingBridgeTask;
    final action = task?.bridgeAction;
    if (signal == null || task == null || action == null) {
      // 路徑 B：Advisor 卡路線（local_model 等無 PendingBridgeTask 的能力）
      if (_controller.activeAdvisorCard != null) {
        _controller.advisorReturnToTask();
        return;
      }
      return;
    }
    if (!signal.matches(action)) return;
    _tryAutoResumePendingBridgeTask(task, signal: signal);
  }

  Future<void> _loadConversations() => _controller.loadConversations();

  Future<void> _createNewConversation() => _controller.createNewConversation();

  Future<void> _switchConversation(Conversation conv) => _controller.switchConversation(conv);

  Future<void> _switchConversationById(String id) async {
    final conv = await ConversationStore.getById(id);
    if (conv == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('找不到這個專案畫布對話。')));
      return;
    }
    await _switchConversation(conv);
  }

  Future<void> _deleteConversation(String id) => _controller.deleteConversation(id);

  Future<void> _clearCurrentChat() => _controller.clearCurrentChat();

  // TODO: needs context — showDialog 需要 BuildContext，dialog UI 保留在 State 層。
  Future<void> _renameConversation(Conversation conv) async {
    _titleController.text = conv.title;
    final newTitle = await showRenameDialog(context, _titleController);
    if (newTitle != null && newTitle.isNotEmpty) {
      final updated = conv.copyWith(title: newTitle);
      await ConversationStore.save(updated);
      await _controller.loadConversations();
    }
  }

  bool _isProjectConversation(Conversation conv, Set<String> projectTitles) {
    if (projectTitles.contains(conv.title.trim())) return true;
    return conv.messages.any((message) {
      final content = message.content;
      return content.startsWith(projectDoorCardPrefix) ||
          content.startsWith(projectForkIntroCardPrefix) ||
          content.startsWith(projectForkCompleteCardPrefix) ||
          content.contains('已建立專案門：') ||
          content.contains('專案門：${conv.title}');
    });
  }

  Future<void> _sendMessage({String? imagePath}) =>
      _controller.sendMessage(imagePath: imagePath);

  // [Sprint 17 Step 9] 已移除：_telemetryFromMessages, _buildBrainSkillRegistrySafely,
  // _fallbackAgentMotivationSnapshot — dead code（從未被呼叫）。

  // [Sprint 17 Step 8] 移除 17 個未被呼叫的 thin delegate methods（死碼）。
  // 這些方法只是轉發 _controller.xxx，且在 chat_screen.dart 內從未被呼叫。

  // TODO: needs context — _appendLocalSystemMessage / _createNewConversation 需要 State 層。
  Future<void> _startProjectDoorFromCurrentConversation() =>
      _controller.startProjectDoorFromCurrentConversation(
        draftText: _messageController.text,
        ensureConversation: () async {
          if (_controller.currentConversation == null) await _createNewConversation();
        },
      );

  bool _containsAny(String text, List<String> needles) =>
      _controller.containsAny(text, needles);

  Future<BridgeAction?> _prepareDesktopFilesAction(BridgeAction action) async {
    if (action.type != BridgeActionType.desktopFiles) return action;
    final prompt = action.prompt.trim();
    if (prompt.startsWith(LocalDesktopFilesAdapter.applyPlanPrefix) ||
        prompt.startsWith(
          LocalDesktopFilesAdapter.scanAuthorizedFolderPrefix,
        )) {
      return action;
    }
    if (kIsWeb || widget.bridgeActionExecutor != null) return action;

    final folderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要讓 Bridge 只讀掃描的資料夾',
    );
    final normalizedPath = folderPath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) return null;

    return BridgeAction(
      type: action.type,
      prompt: LocalDesktopFilesAdapter.scanPrompt(
        rootPath: normalizedPath,
        taskPrompt: prompt.isEmpty ? '整理授權資料夾' : prompt,
      ),
      provider: 'local_desktop_files',
      model: action.model,
      imageQuality: action.imageQuality,
      referenceImagePaths: action.referenceImagePaths,
      requiresConfirmation: action.requiresConfirmation,
      runStatus: action.runStatus,
      statusMessage: action.statusMessage,
    );
  }

  // [Sprint 17 Step 9] 已移除：_setThoughtStage, _startThoughtPulse,
  // _updateThoughtTelemetry, _stageForBrainReflection — dead code（從未被呼叫）。

  // 以下 helper 仍被 _bridgeResultHandler / _desktopOrganizeHandler 使用：

  String? _documentAssetPrimaryPath(BridgeActionResult result) =>
      documentAssetPrimaryPath(result);

  String? _basename(String? path) => basename(path);

  SecondBrainRoom _documentAssetRoomForCurrentContext() =>
      _controller.documentAssetRoomForCurrentContext();

  /// [隊友訊息流 C3 2026-09-08] 查看任務工作畫布——直播視圖第 2 層。
  /// 走 CanvasMcpRegistry 正宮路徑：切到畫布 tab + 載入工作畫布。
  /// （與 MCP canvas 工具同一條路，不另開旁門。）
  void _openTaskCanvas(String workCanvasId) {
    final reg = CanvasMcpRegistry.instance;
    reg.onLoadCanvas?.call(workCanvasId);
    reg.onNavigateToCanvas?.call();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: kIsWeb,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (kIsWeb) {
          // Web: 顯示檔案名稱，實際上傳需要額外處理
          _messageController.text =
              '[圖片: ${file.name}] ${_messageController.text}';
        } else {
          // Mobile/Desktop: 使用路徑
          final path = file.path;
          if (path != null) {
            await _controller.sendMessage(imagePath: path);
          }
        }
      }
    } catch (e) {
      _showError('選擇圖片失敗: $e');
    }
  }

  void _showError(String message) =>
      showErrorSnackBar(context, message, onOpenSettings: _openSettingsFromError);

  // ── Voice AI 引擎方法 ──

  /// VoiceEngine 狀態變化 → 更新 UI
  void _onVoiceStateChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Toggle Voice AI 對談（VoiceButton onToggle）
  ///
  /// [教練 Agent 2026-07-28] 如果 start() 失敗（權限問題等），
  /// 回復 VoiceEngine 狀態，onError 會透過 SnackBar 顯示權限提示。
  // [教練 Agent 2026-08-03] C4: 異步載入夥伴語音設定 + 重建 VoiceEngine
  Future<void> _loadVoiceSettingsAndBuild() async {
    final activeId = CompanionStore().activeCompanionId;
    if (activeId == null) return;

    final settings = await CompanionVoiceSettingsStore.load(activeId);
    if (!mounted) return;
    _voiceEngine.state.removeListener(_onVoiceStateChanged);
    unawaited(_voiceEngine.stopConversation());
    _voiceEngine.dispose();
    final engine = VoiceEngine(
      onSpeak: (text) => _tts.speak(text),
      onStopSpeaking: () => _tts.stop(),
      onPlayAudioBytes: (bytes) => _audioPlayer.play(bytes),
      onAgentLoopTrigger: ({
        required userText,
        required onProgress,
        required onComplete,
      }) {
        _triggerAgentLoopForVoice(
          userText: userText,
          onProgress: onProgress,
          onComplete: onComplete,
        );
      },
      settings: settings,  // [教練 Agent 2026-08-03] C4
    );
    _voiceEngine = engine;
    engine.state.addListener(_onVoiceStateChanged);
    if (mounted) setState(() {});
  }

  Future<void> _toggleVoiceConversation() async {
    // [教練 Agent 2026-08-03] 雙向溝通模式
    if (_voiceEngine.isConversationActive || _voiceSpeech.isListening) {
      await _voiceLive?.stop();
      _voiceLive = null;
      await _voiceSpeech.stop();
      await _voiceEngine.stopConversation();
      _draftBeforeVoice = '';
    } else {
      _voiceLive = VoiceLiveController(
        speechHandler: _voiceSpeech,
        voiceEngine: _voiceEngine,
        chatController: _controller,
      );
      try {
        await _voiceLive!.start();
        debugPrint('[ChatScreen] 雙向溝通已啟動');
      } catch (e) {
        debugPrint('[ChatScreen] 雙向溝通啟動失敗: $e');
        _voiceLive = null;
      }
    }
    if (mounted) setState(() {});
  }

  // [教練 Agent 2026-08-03] 長按 = 語音輸入文字（iMessage 風格）
  Future<void> _startVoiceInput() async {
    if (_voiceEngine.isConversationActive || _voiceSpeech.isListening) return;
    debugPrint('[ChatScreen] 長按：語音輸入模式開始');
    await _voiceSpeech.start();
    if (mounted) setState(() {});
  }

  Future<void> _stopVoiceInput() async {
    if (!_voiceSpeech.isListening) return;
    debugPrint('[ChatScreen] 長按放開：語音輸入模式結束');
    await _voiceSpeech.stop();
    if (mounted && _messageController.text.trim().isNotEmpty) {
      await _controller.sendMessage();
    }
    if (mounted) setState(() {});
  }

  /// 將使用者語音輸入轉發到 ChatController 的 AgentLoop
  ///
  /// VoiceEngine 的 onAgentLoopTrigger 回調會呼叫此方法。
  /// 使用 onGetMessageText 暫存模式直接送出語音文字，不寫入輸入框，
  /// 避免與 Open Whisper 的貼上操作衝突導致文字重複。
  void _triggerAgentLoopForVoice({
    required String userText,
    required void Function(String intermediateText) onProgress,
    required void Function(String finalReply) onComplete,
  }) {
    // [教練 Agent 2026-07-28] 不寫入輸入框，改用 onGetMessageText 暫存模式直接送出
    final originalGetter = _controller.onGetMessageText;
    final originalSetter = _controller.onSetMessageText;
    _controller.onGetMessageText = () => userText;
    _controller.onSetMessageText = (_) {}; // 暫時忽略 setter，不寫入輸入框

    // 記錄送出前的訊息數量，用於偵測 Agent 回覆
    final messagesBefore = _controller.currentConversation?.messages.length ?? 0;

    // 監聽 controller 的 Agent Loop 進度
    void onProgressCallback(
      int turnIndex,
      int maxTurns,
      String? toolName,
      String? toolStatus,
      String? llmSnippet,
    ) {
      // 第三層現況回報 — 工具執行進度
      if (toolName != null && toolStatus != null) {
        onProgress('$toolName：$toolStatus');
      }
    }

    // 暫存原本的進度回調，送出後恢復
    final originalProgress = _controller.onAgentLoopProgress;
    _controller.onAgentLoopProgress = onProgressCallback;

    // 送出訊息
    _controller.sendMessage().then((_) {
      // 恢復原本的 getter/setter/進度回調
      _controller.onGetMessageText = originalGetter;
      _controller.onSetMessageText = originalSetter;
      _controller.onAgentLoopProgress = originalProgress;

      // 取得最終回覆（最後一條 assistant 訊息）
      final messages = _controller.currentConversation?.messages ?? [];
      if (messages.length > messagesBefore) {
        // 找最後一條 assistant 訊息
        for (var i = messages.length - 1; i >= messagesBefore; i--) {
          if (messages[i].role == 'assistant') {
            final reply = messages[i].content
                .replaceAll(RegExp(r'<think>[\s\S]*?</think>',
                    caseSensitive: false), '')
                .trim();
            onComplete(reply);
            return;
          }
        }
      }
      // fallback：如果找不到 assistant 訊息
      onComplete('（已完成）');
    }).catchError((error) {
      // 恢復原本的 getter/setter/進度回調
      _controller.onGetMessageText = originalGetter;
      _controller.onSetMessageText = originalSetter;
      _controller.onAgentLoopProgress = originalProgress;
      onComplete('處理時發生錯誤：$error');
    });
  }

  void _showSuccess(String message) =>
      showSuccessSnackBar(context, message);

  Future<void> _clearMessageDraft() async {
    _messageController.clear();
    if (!mounted) return;
    _focusMessageInput();
  }

  void _openSettingsFromError() =>
      openSettingsFromError(context);

  ChatMessageAppender _messageAppender() => ChatMessageAppender(
    ChatMessageAppenderConfig(
      getCurrentConversation: () => _controller.currentConversation,
      onConversationUpdated: (updated, all) {
        _controller.currentConversation = updated;
        _controller.conversations = all;
      },
      mounted: () => mounted,
      setState: setState,
      scrollToBottom: _scrollToBottom,
      pendingBridgeTaskStore: _pendingBridgeTaskStore,
      getPendingBridgeTask: () => _controller.pendingBridgeTask,
      setPendingBridgeTask: (v) => _controller.pendingBridgeTask = v,
      getAutoResumingPendingTask: () => _autoResumingPendingTask,
      context: () => context,
      dismissPendingBridgeTask: (taskId, {silent = false}) =>
          _dismissPendingBridgeTask(taskId, silent: silent),
      resumePendingBridgeTask: _resumePendingBridgeTask,
      loadManagedFolderRules: _loadManagedFolderRules,
      getManagedFolderRules: () => _controller.managedFolderRules,
    ),
  );

  Future<void> _appendLocalSystemMessage(String content) =>
      _messageAppender().appendLocalSystemMessage(content);

  // [Sprint 17 Step 9] 移除未使用的 append delegate methods（死碼）。

  Future<void> _appendManagedFolderRulePickerCard(
    String request, {
    String? targetFolderPath,
    String? targetFolderLabel,
  }) =>
      _messageAppender().appendManagedFolderRulePickerCard(
        request,
        targetFolderPath: targetFolderPath,
        targetFolderLabel: targetFolderLabel,
      );

  Future<void> _createProjectDoorFromCard(ProjectDoorCardData card) =>
      _controller.createProjectDoorFromCard(card);

  Future<void> _transferContextToProject(
    ProjectContextTransferCardData card,
  ) => _controller.transferContextToProject(card);

  // ── [Sprint 17 Step 7] _invokeDigitalAsset 搬到 digital_asset_invocation_handler.dart ──

  Future<void> _invokeDigitalAsset(DigitalAssetInvocationCardData card) async {
    final handler = DigitalAssetInvocationHandler(
      DigitalAssetInvocationHandlerConfig(
        digitalAssetRegistry: _digitalAssetRegistry,
        activeProjectDoor: _controller.activeProjectDoor,
        currentConversation: _controller.currentConversation,
        containsAny: _containsAny,
        secondBrainFileIndexStore: _secondBrainFileIndexStore,
        activeCompanionName: _controller.activeCompanion?.name,
        mounted: () => mounted,
        setState: (fn) => setState(fn),
        scrollToBottom: _scrollToBottom,
        onConversationSaved: (updated) async {
          await ConversationStore.save(updated);
          final all = await ConversationStore.getAll();
          if (mounted) {
            setState(() {
              _controller.currentConversation = updated;
              _controller.conversations = all;
            });
          }
        },
      ),
    );
    await handler.invokeDigitalAsset(card);
  }
  Future<void> _startDigitalAssetReusePlan(
    DigitalAssetReusePlanCardData card, {
    required bool outlineOnly,
  }) async {
    final action = _bridgeActionForReusePlan(card, outlineOnly: outlineOnly);
    final lead = outlineOnly
        ? '我先把「${card.assetTitle}」整理成可檢查的大綱，不直接執行。'
        : '我開始把「${card.assetTitle}」接到目前專案，先產出可檢查的第一步。';
    await _appendLocalSystemMessage(
      [
        lead,
        '下一步任務：${card.suggestedAction}',
        if (action.type == BridgeActionType.desktopFiles)
          '這一步會先請你選擇要整理的資料夾，只讀掃描，不會移動、改名或刪除任何檔案。',
      ].join('\n'),
    );
    if (!mounted) return;

    if (action.type == BridgeActionType.desktopFiles) {
      final prepared = await _prepareDesktopFilesAction(action);
      if (!mounted) return;
      if (prepared == null) {
        await _appendLocalSystemMessage(
          '桌面整理資產已暫停：你還沒有選擇要掃描的資料夾。等你準備好後，再按「照這個開始」。',
        );
        return;
      }
      await _controller.executeBridgeAction(prepared);
      return;
    }

    await _controller.executeBridgeAction(action);
  }

  BridgeAction _bridgeActionForReusePlan(
    DigitalAssetReusePlanCardData card, {
    required bool outlineOnly,
  }) =>
      bridgeActionForReusePlan(
        card,
        outlineOnly: outlineOnly,
        containsAny: _containsAny,
      );

  DigitalAssetResultCardData _digitalAssetResultCardFromAsset(
    DigitalAsset asset, {
    required String sourceProjectTitle,
  }) => _controller.digitalAssetResultCardFromAsset(
    asset,
    sourceProjectTitle: sourceProjectTitle,
  );

  CapabilityGapCardData? _tryParseCapabilityCard(String content) =>
      tryParseCapabilityCard(content);

  // ── [Sprint 17 Step 6] helper: 組裝 BrainReflectionPanelData ──

  bool _shouldShowBridgeEvidence(Map<String, dynamic>? metadata) {
    if (metadata == null || metadata.isEmpty) return false;
    return metadata['kind'] != null ||
        metadata['type'] != null ||
        metadata['searchSources'] != null ||
        metadata['imageCount'] != null ||
        metadata['path'] != null;
  }

  BrainReflectionPanelData _buildBrainReflectionPanelData() {
    final reflection = _controller.brainReflection!;
    final effectiveTelemetry = _controller.isLoading
        ? _controller.thoughtTelemetry
        : _controller.lastBrainActionTelemetry;
    return BrainReflectionPanelData(
      reflection: reflection,
      activeDoorTitle: _controller.activeProjectDoor?.title,
      turnCount: _controller.currentConversation?.messages.length ?? 0,
      contextChars: _currentConversationContextChars(),
      effectiveTelemetry: effectiveTelemetry,
      activeStage: _controller.thoughtStage ?? _controller.lastBrainActionStage,
      activeBridgeActionLabel: _controller.isLoading
          ? _controller.activeBridgeActionLabel
          : _controller.lastBridgeActionLabel,
      imageProgressLabel: _controller.imageProgressLabel,
      isWorking: _controller.isLoading,
      recalledInsights: _controller.recalledBrainInsights,
      secondBrainTrace: _controller.secondBrainTrace,
      brainSkillRegistry: _controller.brainSkillRegistry,
      agentMotivation: _controller.agentMotivation,
      secondBrainMemoryFeedbacks: _controller.secondBrainMemoryFeedbacks,
      secondBrainAssociationFeedbacks: _controller.secondBrainAssociationFeedbacks,
      onSecondBrainMemoryFeedback: _memory.markSecondBrainMemoryFeedback,
      onSecondBrainAssociationFeedback:
          _memory.markSecondBrainAssociationFeedback,
      secondBrainMemoryRoomOverrides: _controller.secondBrainMemoryRoomOverrides,
      onSecondBrainMemoryRoomMove: _memory.moveSecondBrainMemoryRoom,
      onUndoSecondBrainMemoryCorrection:
          _memory.undoSecondBrainMemoryCorrection,
      onOpenSecondBrainMemorySource: (m) =>
          _memory.openSecondBrainMemorySource(m, context: context),
      onCopySecondBrainMemorySource: (m) =>
          _memory.copySecondBrainMemorySource(m, context: context),
      onImportSecondBrainFolder: _importSecondBrainFolder,
      pendingDoorReturn: _controller.pendingDoorReturn,
      onDoorChoice: _chooseDoorDecision,
      onResumePendingDoor: _resumePendingDoorReturn,
      onClearPendingDoor: _clearPendingDoorReturn,
      intentions: _controller.intentionRouter?.intentions ?? const [],
      auditSummary: _controller.auditSummary,
      heartMindDialogue: _controller.heartMindDialogue,
    );
  }

  // ── [Sprint 17 Step 6] helper: 組裝 MessageBubbleConfig ──

  MessageBubbleConfig _buildMessageBubbleConfig() {
    return MessageBubbleConfig(
      tryParseCapabilityCard: _tryParseCapabilityCard,
      tryParseCapabilityAdvisorCard: _controller.tryParseCapabilityAdvisorCard,
      tryParseProjectDoorCard: _controller.tryParseProjectDoorCard,
      tryParseProjectContextTransferCard: _controller.tryParseProjectContextTransferCard,
      tryParseDigitalAssetInvocationCard: tryParseDigitalAssetInvocationCard,
      tryParseDigitalAssetReusePlanCard: tryParseDigitalAssetReusePlanCard,
      tryParseProjectForkCompleteCard: _controller.tryParseProjectForkCompleteCard,
      tryParseProjectForkIntroCard: _controller.tryParseProjectForkIntroCard,
      tryParseDigitalAssetResultCard: tryParseDigitalAssetResultCard,
      tryParseManagedFolderRulePickerCard: tryParseManagedFolderRulePickerCard,
      activeProjectDoor: _controller.activeProjectDoor,
      selectedMessageId: _selectedMessageId,
      selectedMessageText: _selectedMessageText,
      completedDocumentWorkflowActions: _completedDocumentWorkflowActions,
      onCopySelectedMessageText: _copySelectedMessageText,
      onCopyMessage: _copyMessage,
      onShowDocumentPreview: (msg, path) => showDocumentPreviewDialog(context, path),
      onOpenLocalBridgePath: _openLocalBridgePath,
      onMessageSelectionChanged: _handleMessageSelectionChanged,
      shouldShowBridgeEvidence: _shouldShowBridgeEvidence,
      managedFolderRuleForMetadata: _managedFolderRuleForMetadata,
      onStartManagedFolderRuleReuse: (ManagedFolderRulePickerItem rule, {required ManagedFolderRulePickerCardData card}) =>
          _desktopOrganizeHandler().startManagedFolderRuleReuse(rule, card: card),
      onInvokeDigitalAsset: _invokeDigitalAsset,
      onStartDigitalAssetReusePlan: _startDigitalAssetReusePlan,
      onTransferContextToProject: _transferContextToProject,
      onCreateProjectDoorFromCard: _createProjectDoorFromCard,
      onAppendLocalSystemMessage: _appendLocalSystemMessage,
      onSwitchConversationById: _switchConversationById,
      isCapabilityGapResolved: _isCapabilityGapResolved,
      onResumeCapabilityRequest: _resumeCapabilityRequest,
      onExecuteBridgeAction: _controller.executeBridgeAction,
      onCancelBridgeAction: _cancelBridgeAction,
      onMarkAnswerFeedback: _memory.markAnswerFeedback,
      onSetMessageInputText: _setMessageInputText,
      onSendMessage: _controller.sendMessage,
      onAdvisorConfirmIntent: _controller.advisorConfirmIntent,
      onAdvisorStartBrowseSubFlow: _controller.advisorStartBrowseSubFlow,
      onAdvisorCorrectIntent: _controller.advisorCorrectIntent,
      onAdvisorSelectSolution: _controller.advisorSelectSolution,
      onAdvisorVerify: _controller.advisorVerify,
      onAdvisorRetry: _controller.advisorRetry,
      onAdvisorCancel: _controller.advisorCancel,
      onAdvisorReturnToTask: (callback) {
        _controller.advisorReturnToTask().then((executedTask) {
          callback(executedTask);
        });
      },
      onExecuteDocumentWorkflowAction: _executeDocumentWorkflowAction,
      onRequestDesktopOrganizeConfirmation: _desktopOrganizeHandler().requestDesktopOrganizeConfirmation,
      onExecuteDesktopPlanReport: _desktopOrganizeHandler().executeDesktopPlanReport,
      onExecuteDesktopPlanRules: _desktopOrganizeHandler().executeDesktopPlanRules,
      onImportDesktopOrganizeRules: _desktopOrganizeHandler().importDesktopOrganizeRules,
      formatTime: _formatTime,
      agentNameResolver: resolveAgentName,
      onSpeakMessage: (text) => _tts.speak(text),
      // [教練 Agent 2026-07-22] Phase H — 回覆指定訊息
      onReplyMessage: (msg) {
        _controller.setReplyTarget(msg);
        setState(() {
          _replyTargetMessage = msg;
        });
        // 聚焦輸入框
        _messageFocusNode.requestFocus();
      },
      // [教練 Agent 2026-08-02] 刪除訊息
      onDeleteMessage: (msg) {
        _controller.deleteMessage(msg.id);
      },
      // [教練 Agent 2026-08-02] 延伸話題（帶上下文建立新對話）
      // [教練 Agent 2026-08-03] 修復：原本的 createNewConversation().then(...) 流程會
      // 被 switchConversation 開頭的「先保存當前對話」覆蓋，導致 context 沒注入。
      // 改為：直接建立 Conversation → 注入上下文與標題 → 存 → 切換到新對話（繞過 switchConversation）
      onExtendTopic: (msg) async {
        final conv = _controller.currentConversation;
        if (conv == null) return;

        // 取上下文 5 則
        final contextMessages = MessageContextMenu.extractContextMessages(
          allMessages: conv.messages,
          centerMsg: msg,
        );

        // 取標題
        final title = MessageContextMenu.extractTopicTitle(msg.content);

        // 委託 controller 處理（避免畫面 ↔ store 競爭）
        await _controller.extendTopicWithContext(
          sourceConv: conv,
          contextMessages: contextMessages,
          title: title,
        );
      },
    );
  }

  // [Sprint 17 Step 10] tryParse delegates 已 inline 到 _buildMessageBubbleConfig。

  /// [教練 Agent S21d] Agent Loop 進度顯示 — 已抽到 AgentLoopProgress widget
  Widget _buildAgentLoopProgress() => AgentLoopProgress(
        turn: _agentLoopTurn ?? 0,
        maxTurns: _agentLoopMaxTurns ?? 15,
        toolName: _agentLoopToolName,
        toolStatus: _agentLoopToolStatus,
        activityLog: _agentLoopLog,
      );

  /// [教練 Agent P0.5b 2026-08-08] 圖片任務進度時間線
  /// 顯示 adapter_selected → request_about_to_send → response_received → media_persisted
  /// 每個事件一行，帶 ✓ 或 spinner，使用者可以看到真實執行邊界
  Widget _buildImageProgressTimeline() {
    final events = _controller.imageProgressEvents;
    final isLastEvent = (BridgeActionProgressEvent event) =>
        events.indexOf(event) == events.length - 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 標題
          Row(
            children: [
              Icon(Icons.image_outlined,
                  size: 14, color: BridgeDSColors.of(context).textTertiary),
              SizedBox(width: 6),
              Text(
                '圖片任務',
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()
                    .copyWith(
                      color: BridgeDSColors.of(context).textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          SizedBox(height: 6),
          // 事件序列
          ...events.map((event) {
            final isLast = isLastEvent(event);
            final isDone = !isLast;
            return Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                children: [
                  // 狀態 icon
                  if (isDone)
                    Icon(Icons.check_circle,
                        size: 12, color: BridgeDSColors.of(context).accentGreen)
                  else
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: BridgeDSColors.of(context).accentBlue,
                      ),
                    ),
                  SizedBox(width: 8),
                  // 事件文字
                  Expanded(
                    child: Text(
                      event.userLabel,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            color: isLast
                                ? BridgeDSColors.of(context).textSecondary
                                : BridgeDSColors.of(context).textTertiary,
                            fontSize: 12,
                          ),
                    ),
                  ),
                  // provider/model 標籤
                  if (event.provider != null)
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: BridgeDSColors.of(context).surface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.model ?? event.provider!,
                        style: TextStyle(
                          fontSize: 10,
                          color: BridgeDSColors.of(context).textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _scrollToBottom({int retry = 3}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        if (retry > 0) {
          Future.delayed(const Duration(milliseconds: 80), () {
            _scrollToBottom(retry: retry - 1);
          });
        }
        return;
      }

      final scrollCtrl = _scrollController;
      final viewport = scrollCtrl.position.viewportDimension;
      final maxExtent = scrollCtrl.position.maxScrollExtent;
      // 計算「最後一條訊息開頭」的近似位置：
      // maxScrollExtent 含 280px bottom padding，扣掉 padding 後就是最後訊息的底部。
      // 再往上扣一個 viewport 高度，就是最後訊息開頭的大約位置。
      final bottomPadding = _showCompanionPresence ? 280.0 : 16.0;
      final lastMessageBottom = maxExtent - bottomPadding;
      // 目標：讓最後一條訊息出現在 viewport 頂部附近
      final targetOffset = (lastMessageBottom - viewport * 0.3)
          .clamp(0.0, maxExtent);

      scrollCtrl.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _copyMessage(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已複製'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _openLocalBridgePath(String path) =>
      openLocalBridgePath(context, path, onCopyFallback: _copyMessage);

  Future<void> _copySelectedMessageText() async {
    final text = _selectedMessageText?.trim();
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已複製選取文字'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _handleMessageSelectionChanged(
    Message msg,
    TextSelection selection,
    SelectionChangedCause? cause,
  ) {
    final hasValidSelection =
        selection.isValid &&
        !selection.isCollapsed &&
        selection.start >= 0 &&
        selection.end <= msg.content.length;
    if (!hasValidSelection) {
      if (_selectedMessageId == msg.id) {
        setState(() {
          _selectedMessageId = null;
          _selectedMessageText = null;
        });
      }
      return;
    }

    final selectedText = selection.textInside(msg.content).trim();
    if (selectedText.isEmpty) return;
    if (_selectedMessageId == msg.id && _selectedMessageText == selectedText) {
      return;
    }
    setState(() {
      _selectedMessageId = msg.id;
      _selectedMessageText = selectedText;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        width: 280,
        child: ChatSidebar(
          conversations: _controller.conversations,
          projectDoors: _controller.projectDoors,
          currentConversation: _controller.currentConversation,
          onNewConversation: _createNewConversation,
          onSwitchConversation: (conv) {
            _switchConversation(conv);
            Navigator.of(context).pop();
          },
          onRenameConversation: _renameConversation,
          onDeleteConversation: _deleteConversation,
          isProjectConversation: _isProjectConversation,
        ),
      ),
      appBar: ChatAppBar(
        conversationTitle: _controller.currentConversation?.title,
        activeCompanion: _controller.activeCompanion,
        currentMode: _controller.currentMode,
        isUsingLocalModel: _controller.isUsingLocalModel,
        totalTokens: _controller.totalTokens,
        brainReflection: _controller.brainReflection,
        onOpenDrawer: () => Scaffold.of(context).openDrawer(),
        onTapCompanion: _showCompanionSelector,
        onModelSwitchChanged: () => setState(() {}),
        onMemory: () => _memory.showMemoriesDialog(context),
        onNewProjectDoor: _startProjectDoorFromCurrentConversation,
        onSettings: () => BridgeDesktopScreen.navigateTo('system'),
        buildBrainReflectionPanelData: _buildBrainReflectionPanelData,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              // 記憶標籤已移到 Stack 中
              // Skill 快捷面板（可展開/收合）
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: _showSkillPanel ? null : 0,
                child: _showSkillPanel
                    ? SkillChipPanel(onSelect: _selectSkillChip)
                    : const SizedBox.shrink(),
              ),
              // 主要內容區
              Expanded(
                child: Column(
                  children: [
                    // 常駐面板全數移除，改由 AppBar icon + bottom sheet / SnackBar 呈現
                    Expanded(
                      child: _controller.currentConversation == null ||
                              _controller.currentConversation!.messages.isEmpty
                          ? EmptyChatState(
                              onQuickPromptTap: (prompt) =>
                                  _setMessageInputText('$prompt：'),
                              onApplyFirstAction: (prompt) =>
                                  setState(() => _setMessageInputText(prompt)),
                            )
                          : ListView.builder(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              controller: _scrollController,
                              // 狀態圖顯示時多留空間，隱藏時恢復正常
                              padding: EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                _showCompanionPresence ? 280.0 : 16.0,
                              ),
                              itemCount: _controller.currentConversation!.messages.length,
                              itemBuilder: (context, index) {
                                final msg =
                                    _controller.currentConversation!.messages[index];
                                // [隊友訊息流 C4] 交付訊息 → 交付卡（非普通泡泡）
                                if (msg.metadata?['kind'] == 'task-delivery') {
                                  return TaskDeliveryCard(
                                    key: ValueKey('task-delivery-${msg.id}'),
                                    message: msg,
                                    onViewCanvas: _openTaskCanvas,
                                  );
                                }
                                return MessageBubble(
                                  msg: msg,
                                  config: _buildMessageBubbleConfig(),
                                );
                              },
                            ),
                    ),
                    // [隊友訊息流 C3 2026-09-08] 進行中任務卡——
                    // 本對話的活躍 TaskSession 常駐於訊息流末端（sticky）。
                    // AnimatedBuilder 監聽 dispatcher：任務狀態變化即時刷新，
                    // 不依賴 chat controller 的 notifyListeners。
                    AnimatedBuilder(
                      animation: TaskDispatcher.instance,
                      builder: (context, _) {
                        final active =
                            TaskDispatcher.instance.activeSessions
                                .where((s) =>
                                    s.conversationId ==
                                    _controller.currentConversation?.id)
                                .toList();
                        if (active.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final s in active)
                                TaskProgressCard(
                                  key: ValueKey('task-card-${s.id}'),
                                  session: s,
                                  onViewCanvas: _openTaskCanvas,
                                  onCancel: (id) => TaskDispatcher.instance
                                      .cancel(id, reason: '使用者從任務卡取消'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (_controller.isLoading)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ThinkingPanel(),
                      ),
                    // [教練 Agent S21d] Agent Loop 進度條
                    if (_controller.isLoading && _agentLoopTurn != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildAgentLoopProgress(),
                      ),
                    // [教練 Agent P0.5b 2026-08-08] 圖片任務進度時間線
                    if (_controller.isLoading && _controller.imageProgressEvents.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildImageProgressTimeline(),
                      ),
                    if (!_messageFocusNode.hasFocus)
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: () {
                          _messageFocusNode.requestFocus();
                        },
                        child: Container(
                          width: double.infinity,
                          height: 6,
                          margin: const EdgeInsets.only(top: 0, bottom: 0),
                          decoration: BoxDecoration(
                            color: BridgeDSColors.of(context).textMuted.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    // [教練 Agent 2026-07-22] Phase H — 回覆預覽 bar
                    if (_replyTargetMessage != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: BridgeDSColors.of(context).accentGreen.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.reply_rounded, size: 14, color: BridgeDSColors.of(context).accentGreen),
                            const SizedBox(width: 6),
                            Text(
                              _replyTargetMessage!.role == 'user' ? '回覆 你的訊息' : '回覆 AI 訊息',
                              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                                color: BridgeDSColors.of(context).accentGreen,),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _replyTargetMessage!.content.length > 50
                                    ? '${_replyTargetMessage!.content.substring(0, 50)}...'
                                    : _replyTargetMessage!.content,
                                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                                  fontStyle: FontStyle.italic,),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _replyTargetMessage = null;
                                });
                                _controller.setReplyTarget(null);
                              },
                              child: Icon(Icons.close, size: 14, color: BridgeDSColors.of(context).textMuted),
                            ),
                          ],
                        ),
                      ),
                    // ── Voice AI 按鈕 + 狀態指示器（用 Stack 疊合，按鈕位置固定不跳位）──
                    // [教練 Agent 2026-07-28] VoiceButton 永遠在 centerRight 固定位置；
                    // VoiceStatusIndicator 以 Overlay 方式顯示在按鈕上方，不影響按鈕佈局。
                    SizedBox(
                      height: 44,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // VoiceButton 永遠在右側固定位置
                          Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: VoiceButton(
                                mode: _voiceMode,
                                onToggle: _toggleVoiceConversation,  // 短按
                                onLongPressStart: _startVoiceInput,  // 長按開始
                                onLongPressEnd: _stopVoiceInput,    // 長按結束
                                volume: _micVolume,  // [教練 Agent 2026-08-03] 傳 ValueNotifier（不重建 panel）
                              ),
                            ),
                          ),
                          // VoiceStatusIndicator 疊在按鈕上方，獨立顯示不推擠按鈕
                          if (_voiceEngine.isConversationActive)
                            Positioned(
                              right: 12,
                              bottom: 48,
                              child: VoiceStatusIndicator(mode: _voiceMode),
                            ),
                        ],
                      ),
                    ),
                    // ── Agent 模型選擇器（輸入框上方）──
                    // [教練 Agent 2026-08-13] 加 key — 上方 if(_replyTargetMessage) 條件 widget
                    // 會改變 Column children position，導致 AgentModelSelector 被銷毀重建
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: AgentModelSelector(
                        key: const ValueKey('agent_model_selector'),
                        onProviderChanged: () {
                          // 通知 ChatController 重新載入 provider 設定
                          _controller.refreshLocalModelState();
                        },
                      ),
                    ),
                    ChatInputBar(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      isLoading: _controller.isLoading,
                      onSend: () {
                        // [隊友訊息流 C6 2026-09-08] Phase 2 自動派工——
                        // 任務型意圖（指令前綴+任務動詞+非問句）自動 dispatch，
                        // 否則正常對話。誤判時任務卡「取消」即轉回（訊息已在對話裡）。
                        final text = _messageController.text.trim();
                        // [TRIO M3.5 2026-09-22] 白話開會——「開個會」觸發團隊會議
                        final isMeetingTrigger = text.isNotEmpty &&
                            _isMeetingIntent(text);
                        if (isMeetingTrigger) {
                          _controller.holdTrioMeeting(
                              agendaExtra: text.length > 8 ? text : null);
                        } else if (text.isNotEmpty &&
                            TaskIntentClassifier.classify(text) ==
                                TaskIntent.task) {
                          _controller.dispatchTask(text);
                        } else {
                          _controller.sendMessage();
                        }
                        _messageController.clear();
                        // [教練 Agent 2026-07-22] Phase H — 送出後清回覆預覽
                        if (_replyTargetMessage != null) {
                          setState(() {
                            _replyTargetMessage = null;
                          });
                        }
                      },
                      onPickImage: _pickImage,
                      onClearDraft: _clearMessageDraft,
                      onNewConversation: () => _controller.createNewConversation(),
                      // [隊友訊息流 C3] 派工鈕——輸入框有字才派
                      onDispatchTask: () {
                        final text = _messageController.text.trim();
                        if (text.isEmpty) return;
                        _controller.dispatchTask(text);
                        _messageController.clear();
                        if (_replyTargetMessage != null) {
                          setState(() => _replyTargetMessage = null);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          CompanionPresenceLayer(
            showCompanionPresence: _showCompanionPresence,
            onTogglePresence: () => setState(
              () => _showCompanionPresence = !_showCompanionPresence,
            ),
            showSidebar: false,
            activeCompanion: _controller.activeCompanion,
          ),
          // [教練 Agent 2026-08-08] Layer C：Transurfing 沉浸層 overlay
          const StreamConfluenceOverlay(),
        ],
      ),
    );
  }

  Future<bool> _isCapabilityGapResolved(CapabilityGapCardData card) async {
    final type = _capabilityCardActionType(card);
    if (type == null) return false;
    try {
      final items = await _capabilityHealth.inspect();
      return items.any(
        (item) =>
            item.type == type && item.status == CapabilityHealthStatus.ready,
      );
    } catch (_) {
      return false;
    }
  }

  BridgeActionType? _capabilityCardActionType(CapabilityGapCardData card) =>
      capabilityCardActionType(card);

  DesktopOrganizeHandler _desktopOrganizeHandler() => DesktopOrganizeHandler(
    config: DesktopOrganizeHandlerConfig(
      controller: _controller,
      managedFolderRuleStore: _managedFolderRuleStore,
      secondBrainFileIndexStore: _secondBrainFileIndexStore,
      managedFolderRuleNamer: _managedFolderRuleNamer,
      managedFolderRules: _controller.managedFolderRules,
      currentConversation: _controller.currentConversation,
      bridgeActionExecutorOverride: widget.bridgeActionExecutor,
      mounted: () => mounted,
      basename: _basename,
      desktopCategorySummary: _desktopCategorySummary,
      appendLocalSystemMessage: _appendLocalSystemMessage,
      appendBridgeResultMessage: _appendBridgeResultMessage,
      appendBridgeConfirmationMessage: _appendBridgeConfirmationMessage,
      showSuccess: _showSuccess,
      appendManagedFolderRulePickerCard: _appendManagedFolderRulePickerCard,
    ),
  );

  ManagedFolderRule? _managedFolderRuleForMetadata(
    Map<String, dynamic> metadata,
  ) {
    final rootPath = metadata['rootPath']?.toString().trim();
    if (rootPath == null || rootPath.isEmpty) return null;
    String normalizeFolderPath(String path) {
      var value = path.trim();
      while (value.length > 1 && value.endsWith('/')) {
        value = value.substring(0, value.length - 1);
      }
      return value;
    }
    final normalized = normalizeFolderPath(rootPath);
    for (final rule in _controller.managedFolderRules) {
      if (normalizeFolderPath(rule.folderPath) == normalized) return rule;
    }
    return null;
  }

  Future<void> _executeDocumentWorkflowAction(
    Map<String, dynamic> action,
  ) async {
    final prompt = action['prompt']?.toString().trim();
    if (prompt == null || prompt.isEmpty) {
      _copyMessage('這個文件操作缺少可執行內容。');
      return;
    }
    final actionKey = _documentWorkflowActionKey(action);
    await _controller.executeBridgeAction(
      BridgeAction(
        type: BridgeActionType.document,
        prompt: prompt,
        provider: 'local_document',
      ),
      confirmed: true,
    );
    if (!mounted) return;
    setState(() => _completedDocumentWorkflowActions.add(actionKey));
  }

  String _documentWorkflowActionKey(Map<String, dynamic> action) =>
      documentWorkflowActionKey(action);

  String _desktopCategorySummary(Map<String, dynamic> metadata) =>
      desktopCategorySummary(metadata);

  Future<void> _resumeCapabilityRequest(CapabilityGapCardData card) async {
    setState(() => _setMessageInputText(card.request));
    if (card.pendingTaskId != null) {
      await _dismissPendingBridgeTask(card.pendingTaskId!, silent: true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已把原任務帶回輸入框；完成設定後可以直接送出。'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _resumePendingBridgeTask(PendingBridgeTask task) =>
      _pendingTaskHandler().resumePendingBridgeTask(task);

  Future<void> _tryAutoResumePendingBridgeTask(
    PendingBridgeTask task, {
    CapabilityActivationSignal? signal,
  }) =>
      _pendingTaskHandler()
          .tryAutoResumePendingBridgeTask(task, signal: signal);

  Future<void> _dismissPendingBridgeTask(
    String taskId, {
    bool silent = false,
  }) =>
      _pendingTaskHandler()
          .dismissPendingBridgeTask(taskId, silent: silent);

  SecondBrainImportHandler _secondBrainImportHandler() =>
      SecondBrainImportHandler(
        SecondBrainImportConfig(
          importService: _secondBrainFolderImportService,
          traceService: _secondBrainTraceService,
          mounted: () => mounted,
          context: () => context,
          setState: setState,
          getBrainReflection: () => _controller.brainReflection,
          getRecalledInsights: () => _controller.recalledBrainInsights,
          getActiveCompanionName: () => _controller.activeCompanion?.name,
          getLastBridgeActionLabel: () => _controller.lastBridgeActionLabel,
          onTraceUpdated: (trace, feedbacks) {
            _controller.secondBrainTrace = trace;
            _controller.secondBrainAssociationFeedbacks = feedbacks;
          },
        ),
      );

  Future<void> _importSecondBrainFolder() =>
      _secondBrainImportHandler().importFolder();

  // 搬移項目：_buildStatusPreviewImage, _statusSpecForRuntime, _statusSpecById,
  //          _stateImagePathFor, _normalizeStateKey, _legacyCustomStateImagePathFor,
  //          _buildStoredStatusImage

  int _currentConversationContextChars() {
    return _controller.currentConversation?.messages.fold<int>(
          0,
          (total, message) => total + message.content.length,
        ) ??
        0;
  }

  // ── [Sprint 17 Step 7] mood/action labels 搬到 chat_misc_helpers.dart ──

  // [Sprint 17 Step 9] 已移除：_moodActionLabel, _moodLabel, _actionLabel — dead code。
  /// [教練 Agent 2026-06-29] 對話中切換模型 — 顯示有 token 的 provider 列表

  /// 選擇夥伴
  void _showCompanionSelector() {
    showCompanionSelectorSheet(
      context,
      activeCompanionId: _controller.activeCompanion?.id,
      onSelected: (c) => setState(() => _controller.activeCompanion = c),
    );
  }

  /// [以利沙 Sprint 8 Step 6 2026-06-24]
  /// executeBridgeAction 邏輯已搬移至 ChatController，此處僅為委派。
  Future<void> _executeBridgeAction(
    BridgeAction action, {
    String? messageId,
    int? actionIndex,
    bool confirmed = false,
    BridgeActionExecutionOverride executionOverride =
        BridgeActionExecutionOverride.none,
    Future<void> Function(BridgeActionResult result)? onCompleted,
  }) =>
      _controller.executeBridgeAction(
        action,
        messageId: messageId,
        actionIndex: actionIndex,
        confirmed: confirmed,
        executionOverride: executionOverride,
        onCompleted: onCompleted,
      );

  BridgeActionStatusHandler _bridgeActionStatusHandler() =>
      BridgeActionStatusHandler(
        BridgeActionStatusHandlerConfig(
          getCurrentConversation: () => _controller.currentConversation,
          onConversationUpdated: (updated, all) {
            _controller.currentConversation = updated;
            _controller.conversations = all;
          },
          mounted: () => mounted,
          setState: setState,
          context: () => context,
          executeBridgeAction: (action, {messageId, actionIndex, confirmed = false}) =>
              _controller.executeBridgeAction(
            action,
            messageId: messageId,
            actionIndex: actionIndex,
            confirmed: confirmed,
          ),
          bridgeResultStatusMessage: _bridgeResultStatusMessage,
          syncBridgeEvidenceToCompanion: _syncBridgeEvidenceToCompanion,
          bridgeActionEvidence: _bridgeActionEvidence,
        ),
      );

  String _bridgeResultStatusMessage(BridgeActionResult result) {
    final evidence = _bridgeActionEvidence.describe(result);
    if (evidence == null) return result.message;
    return '${result.message}\n$evidence';
  }

  void _syncBridgeEvidenceToCompanion(BridgeActionResult result) {
    _controller.syncBridgeEvidenceToCompanion(result);
  }

  Future<void> _cancelBridgeAction(
    String messageId,
    int actionIndex, {
    required String message,
  }) =>
      _bridgeActionStatusHandler().cancelBridgeAction(
        messageId,
        actionIndex,
        message: message,
      );

  void _showBridgeResultSnackBar(BridgeActionResult result) =>
      _bridgeActionStatusHandler().showBridgeResultSnackBar(result);

  BridgeResultHandler _bridgeResultHandler() => BridgeResultHandler(
    BridgeResultHandlerConfig(
      currentConversation: _controller.currentConversation,
      bridgeActionEvidence: _bridgeActionEvidence,
      secondBrainFileIndexStore: _secondBrainFileIndexStore,
      digitalAssetRegistry: _digitalAssetRegistry,
      activeProjectDoor: _controller.activeProjectDoor,
      documentAssetPrimaryPath: _documentAssetPrimaryPath,
      documentAssetRoomForCurrentContext: _documentAssetRoomForCurrentContext,
      basename: _basename,
      desktopCategorySummary: _desktopCategorySummary,
      digitalAssetResultCardFromAsset: _digitalAssetResultCardFromAsset,
      mounted: () => mounted,
      setState: setState,
      scrollToBottom: _scrollToBottom,
      onConversationUpdated: (updated, all) {
        _controller.currentConversation = updated;
        _controller.conversations = all;
      },
    ),
  );

  Future<void> _appendBridgeResultMessage(BridgeActionResult result) =>
      _bridgeResultHandler().appendBridgeResultMessage(result);

  Future<void> _appendBridgeConfirmationMessage(
    BridgeAction action,
    BridgeActionResult result,
  ) =>
      _bridgeResultHandler().appendBridgeConfirmationMessage(action, result);
  /// Skill chip 點擊後的處理邏輯（S17 Step 4 — 從舊 _buildSkillChip 提取）
  void _selectSkillChip(UserIntent intent, String skillCommand) {
    setState(() {
      _controller.manualIntent = intent;
      _controller.currentMode =
          '${IntentClassifier.intentIcon(intent)} ${IntentClassifier.intentName(intent)}';
      _showSkillPanel = false;
      _setMessageInputText(skillChipPrefixes[skillCommand] ?? '');
    });
  }

  /// 建立 Skill 快捷 Chip

  String _formatTime(DateTime dt) => formatTime(dt);

  @override
  void dispose() {
    _controller.removeListener(_syncFromController);
    _controller.dispose();
    _memoryFlashTimer?.cancel();
    _thoughtPulseTimer?.cancel();
    _messageFocusNode.dispose();
    _titleController.dispose();
    JsBridge.instance.chatCommand.removeListener(_handleBridgeCommand);
    CapabilityActivationBus.instance.latest.removeListener(
      _handleCapabilityActivationSignal,
    );
    DoorDecisionStore.pendingReturn.removeListener(_handlePendingDoorReturn);
    unawaited(_tts.dispose());
    // ── Voice AI 引擎清理 ──
    _voiceEngine.state.removeListener(_onVoiceStateChanged);
    _voiceLive?.dispose();  // [教練 Agent 2026-08-03] 釋放 voice live
    _voiceSpeech.dispose();
    _micVolumeSub?.cancel();  // [教練 Agent 2026-08-03] 取消音量訂閱
    _partialTextSub?.cancel();  // [教練 Agent 2026-08-03] 取消 partial 訂閱
    _micVolume.dispose();  // [教練 Agent 2026-08-03] 釋放 ValueNotifier
    unawaited(_voiceEngine.stopConversation());
    _voiceEngine.dispose();
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }
}

