// task_dispatcher.dart
// [隊友訊息流 第 1 刀 C1 2026-09-08]
// 派工編排：建工作畫布 → 建 TaskSession → push ambient → (C2 接 AgentLoop)。
// 設計稿：docs/specs/2026-09-08-teammate-inbox.md §6
//
// C1 骨架範圍：session 生命週期 + 工作畫布路由 + ChangeNotifier 廣播。
// AgentLoop 的接入點以 [C2] 標註——C1 階段 dispatch() 會建立 session 並
// 誠實地停在 dispatched（未接引擎不假裝在跑，UI 誠實鐵則）。

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/canvas_store.dart';
import 'package:bridge_app/services/digital_asset_registry_store.dart';
import 'package:bridge_app/services/entity_graph/entity_graph_service.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:bridge_app/services/project_door_store.dart';
import 'package:bridge_app/services/tasks/task_session.dart';
import 'package:bridge_app/services/tasks/task_session_store.dart';
import 'package:bridge_app/services/collab/agent_status_store.dart';
import 'package:bridge_app/services/collab/resource_lease.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_mcp_registry.dart';

/// 派工事件——UI（任務卡）訂閱這個即可，不碰內部狀態
class TaskDispatcherEvent {
  final String sessionId;
  final TaskSession session; // 事件後的最新狀態
  const TaskDispatcherEvent(this.sessionId, this.session);
}

/// 派工編排器（singleton——與 CanvasMcpRegistry 同模式）
class TaskDispatcher extends ChangeNotifier {
  TaskDispatcher._();
  static final TaskDispatcher instance = TaskDispatcher._();

  /// [C2] AgentLoop 執行器接入點——由 ChatController 注入。
  /// 簽名：對指定 session 跑 Agent Loop；回傳最終摘要文字。
  /// C1 階段為 null → dispatch() 停在 dispatched 並記錄原因。
  Future<String> Function(TaskSession session)? agentRunner;

  /// 活躍任務的 headless 工作畫布 controller（sessionId → controller）
  final Map<String, CanvasController> _workCanvases = {};

  /// 進行中任務快取（記憶體態；持久化靠 TaskSessionStore）
  final Map<String, TaskSession> _active = {};

  /// 進行中任務列表（唯讀視圖）
  List<TaskSession> get activeSessions =>
      _active.values.where((s) => s.isActive).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// App 啟動時恢復——把持久化中 isActive 的任務載回記憶體態。
  /// （App 重啟前任務若在跑，Loop 已斷——標記 failed 誠實呈現，
  /// UI 誠實鐵則：不假裝還在跑。C7 關窗背景續跑後，行程不死故不會走到這。）
  Future<void> restoreFromStore() async {
    final all = await TaskSessionStore.getAll();
    for (final s in all.where((t) => t.isActive)) {
      final revived = s.isActive && s.status != TaskStatus.dispatched
          ? s.transitionTo(TaskStatus.failed,
              reason: 'App 重啟——任務中斷（restoreFromStore 誠實標記）')
          : s;
      // [TRIO M1] 重啟後殘留任務 → unverifiable（斷線≠死亡，D1 詞彙表）
      if (revived.status == TaskStatus.failed) {
        AgentStatusStore.instance.setUnverifiable(revived.companionId,
            sessionId: revived.id, detail: 'App 重啟——Loop 已斷');
      }
      _active[revived.id] = revived;
      await TaskSessionStore.save(revived);
    }
    if (_active.isNotEmpty) notifyListeners();
  }

  /// 派工主流程（設計稿 §6 派工瞬間）
  ///
  /// ① 建工作畫布（〔任務〕前綴，綁主對話）
  /// ② 建 TaskSession（dispatched）
  /// ③ 建 headless CanvasController 並 push ambient——
  ///    之後任何 canvas_* 工具呼叫自動路由到工作畫布
  /// ④ 呼叫 [C2] agentRunner（未注入 → session 停在 dispatched，
  ///    步驟記錄誠實寫「引擎未接」）
  Future<TaskSession> dispatch({
    required String conversationId,
    required String companionId,
    required String instruction,
    String? title,
  }) async {
    final taskTitle = (title ?? instruction).trim();
    final shortTitle = taskTitle.length > 24 ? '${taskTitle.substring(0, 24)}…' : taskTitle;

    // ① 工作畫布
    final canvas = await CanvasStore.create(
      title: '〔任務〕$shortTitle',
      conversationId: conversationId,
    );

    // ② session
    var session = TaskSession.create(
      conversationId: conversationId,
      companionId: companionId,
      workCanvasId: canvas.id,
      title: shortTitle,
      instruction: instruction,
    );
    await TaskSessionStore.save(session);
    _active[session.id] = session;
    notifyListeners();

    // ③ headless 工作畫布（與 CanvasV2Workspace L212-223 同配方，零 UI 依賴）
    final entityGraph = EntityGraphService.withSqliteCanvasStore(
      memoryStore: MemoryStore(),
      doorStore: ProjectDoorStore(),
      assetStore: DigitalAssetRegistryStore(),
    );
    final workController = CanvasController(
      entityGraph: entityGraph,
      canvasId: canvas.id,
    );
    _workCanvases[session.id] = workController;
    CanvasMcpRegistry.instance.pushAmbientCanvas(workController);

    try {
      // ④ 引擎
      final runner = agentRunner;
      if (runner == null) {
        // C1 骨架：誠實停在 dispatched，不假裝在跑
        debugPrint('[TaskDispatcher] agentRunner 未注入（C1 骨架）——'
            'session ${session.id} 停在 dispatched');
        return session;
      }
      session = session.transitionTo(TaskStatus.working);
      // [TRIO M1] 狀態單一真相源——開工即 live（D1）
      AgentStatusStore.instance.setLive(session.companionId,
          sessionId: session.id, detail: shortTitle);
      session = session.copyWith(
        steps: [
          ...session.steps,
          TaskStep(
            id: 'step-${DateTime.now().millisecondsSinceEpoch}',
            tool: 'dispatch',
            summary: '已派工：$shortTitle',
            at: DateTime.now(),
          ),
        ],
      );
      _active[session.id] = session;
      await TaskSessionStore.save(session);
      notifyListeners();

      final summary = await runner(session);

      session = session.copyWith(
        steps: [
          ...session.steps,
          TaskStep(
            id: 'step-${DateTime.now().millisecondsSinceEpoch}',
            tool: 'done',
            summary: summary,
            at: DateTime.now(),
          ),
        ],
      );
      session = session.transitionTo(TaskStatus.delivered);
      session = session.copyWith(finalSummary: summary);
      // [TRIO M1] 交付即 exited（帶摘要）
      AgentStatusStore.instance.setExited(session.companionId,
          sessionId: session.id, detail: 'delivered：$summary');
      _active[session.id] = session;
      await TaskSessionStore.save(session);
      return session;
    } catch (e) {
      session = session.transitionTo(TaskStatus.failed, reason: e.toString());
      // [TRIO M1] 失敗即 exited（誠實帶原因）＋清租約（兵敗不能留鎖）
      AgentStatusStore.instance.setExited(session.companionId,
          sessionId: session.id, detail: 'failed：$e');
      ResourceLease.instance.releaseAllOf(session.id);
      ResourceLease.instance.releaseAllOf(session.companionId);
      _active[session.id] = session;
      await TaskSessionStore.save(session);
      rethrow;
    } finally {
      _teardownWorkCanvas(session.id);
      notifyListeners();
    }
  }

  /// 取消任務（任一非終態可取消）
  Future<void> cancel(String sessionId, {String? reason}) async {
    var session = _active[sessionId];
    if (session == null) {
      session = await TaskSessionStore.getById(sessionId);
      if (session == null) return;
    }
    if (!session.isActive) return;
    final cancelled = session.transitionTo(TaskStatus.cancelled,
        reason: reason ?? '使用者取消');
    // [TRIO M1] 取消即 exited＋清租約
    AgentStatusStore.instance.setExited(session.companionId,
        sessionId: session.id, detail: 'cancelled：${reason ?? '使用者取消'}');
    ResourceLease.instance.releaseAllOf(session.id);
    ResourceLease.instance.releaseAllOf(session.companionId);
    _active[sessionId] = cancelled;
    await TaskSessionStore.save(cancelled);
    _teardownWorkCanvas(sessionId);
    notifyListeners();
  }

  /// 外部更新（C2 的 AgentLoop turn 回報掛點；C3/C4 的 review 確認也走這）
  Future<void> updateSession(TaskSession updated) async {
    _active[updated.id] = updated;
    await TaskSessionStore.save(updated);
    notifyListeners();
  }

  /// 任務的工作畫布 controller（直播視圖「查看畫布」用）
  CanvasController? workCanvasOf(String sessionId) => _workCanvases[sessionId];

  void _teardownWorkCanvas(String sessionId) {
    final ctrl = _workCanvases.remove(sessionId);
    if (ctrl != null) {
      CanvasMcpRegistry.instance.popAmbientCanvas(ctrl);
      ctrl.dispose();
    }
  }

  // [隊友訊息流 C7 2026-09-08] 活躍任務旗標 → SharedPreferences（macOS 底層
  // = UserDefaults.standard）——Swift 端 applicationShouldTerminate 讀它，
  // Cmd+Q 時若有活躍任務先彈原生確認框（不中斷鐵則的最後防線）。
  // 寫入 fail-open（失敗不擋通知），非同步不阻塞。
  @override
  void notifyListeners() {
    super.notifyListeners();
    _syncActiveTaskFlag();
  }

  static bool _flagSyncing = false;
  Future<void> _syncActiveTaskFlag() async {
    if (_flagSyncing) return;
    _flagSyncing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final has = activeSessions.isNotEmpty;
      final cur = prefs.getBool('bridge_has_active_tasks') ?? false;
      if (cur != has) {
        await prefs.setBool('bridge_has_active_tasks', has);
      }
    } catch (e) {
      debugPrint('[TaskDispatcher] 旗標同步失敗（fail-open）: $e');
    } finally {
      _flagSyncing = false;
    }
  }
}
