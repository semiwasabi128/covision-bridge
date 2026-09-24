// [Sprint 18c-3 — 上下文移植]
// ContextTransferService：把對話上下文帶到新專案門。
//
// 流程：
// 1. extractContext：從來源對話提取關鍵上下文（最近的 N 則訊息摘要）
// 2. transferToDoor：將上下文寫入目標門，作為 intakeQuestions 或 flowStep 的初始內容
// 3. transferToBrain：將上下文寫入大腦容器的 Projects 房間（如果有 BrainContainerService）

import '../models/conversation.dart';
import '../models/flow_step.dart';
import '../models/project_door.dart';
import 'project_door_store.dart';

/// 移植上下文結果
class ContextTransferResult {
  final String targetDoorId;
  final int contextCount;
  final List<String> contextLines;
  final String message;

  const ContextTransferResult({
    required this.targetDoorId,
    required this.contextCount,
    required this.contextLines,
    required this.message,
  });
}

class ContextTransferService {
  final ProjectDoorStore _doorStore;

  const ContextTransferService({
    ProjectDoorStore? doorStore,
  }) : _doorStore = doorStore ?? const ProjectDoorStore();

  /// 從對話中提取上下文
  /// 取最後 [maxMessages] 則有意義的訊息，壓縮為摘要行
  List<String> extractContext(
    Conversation conversation, {
    int maxMessages = 10,
  }) {
    final messages = conversation.messages;
    if (messages.isEmpty) return const [];

    // 取最後 N 則，過濾空訊息
    final recent = messages
        .skip((messages.length - maxMessages).clamp(0, messages.length))
        .toList();

    final lines = <String>[];
    for (final msg in recent) {
      final text = msg.content.trim();
      if (text.isEmpty) continue;

      // 截斷過長的訊息
      final truncated = text.length > 200 ? '${text.substring(0, 197)}...' : text;
      final speaker = msg.role == 'user' ? '使用者' : '夥伴';
      lines.add('[$speaker] $truncated');
    }

    return lines;
  }

  /// 從對話中提取關鍵意圖摘要（用於門的 sourceIntent）
  String extractIntent(Conversation conversation) {
    // 取使用者的最後幾則訊息作為意圖來源
    final userMessages = conversation.messages
        .where((m) => m.role == 'user')
        .toList();
    if (userMessages.isEmpty) return conversation.title;

    final recent = userMessages.reversed.take(3).toList();
    final combined = recent.map((m) => m.content.trim()).where((t) => t.isNotEmpty).join(' ');
    if (combined.length > 300) {
      return '${combined.substring(0, 297)}...';
    }
    return combined.isEmpty ? conversation.title : combined;
  }

  /// 移植對話上下文到目標門
  /// 將上下文轉為 flow steps 加入門中
  Future<ContextTransferResult> transferToDoor({
    required String sourceConversationId,
    required String targetDoorId,
    required List<String> contextLines,
    String? intentSummary,
  }) async {
    if (contextLines.isEmpty) {
      return ContextTransferResult(
        targetDoorId: targetDoorId,
        contextCount: 0,
        contextLines: const [],
        message: '無上下文可移植',
      );
    }

    // 將上下文加入門的 flowSteps 作為初始步驟
    final all = await _doorStore.loadAll();
    final index = all.indexWhere((d) => d.id == targetDoorId);
    if (index < 0) {
      return ContextTransferResult(
        targetDoorId: targetDoorId,
        contextCount: 0,
        contextLines: const [],
        message: '目標門不存在',
      );
    }

    final door = all[index];
    final now = DateTime.now();

    // 建立移植摘要步驟
    final transferStep = FlowStep(
      id: 'flow-transfer-${now.microsecondsSinceEpoch}',
      doorId: targetDoorId,
      title: '移植上下文（${contextLines.length} 則）',
      description: contextLines.take(5).join('\n'),
      status: FlowStep.statusDone,
      order: door.flowSteps.length,
      createdAt: now,
      updatedAt: now,
      completedAt: now,
    );

    await _doorStore.addFlowStep(targetDoorId, transferStep);

    // 如果有 intent 摘要，更新門的 sourceIntent
    if (intentSummary != null && intentSummary.trim().isNotEmpty) {
      await _doorStore.updateDoorStatus(targetDoorId, door.status);
      // 更新 sourceIntent 需要透過 saveActive
      final updated = door.copyWith(
        sourceIntent: intentSummary,
        updatedAt: now,
      );
      all[index] = updated;
    }

    return ContextTransferResult(
      targetDoorId: targetDoorId,
      contextCount: contextLines.length,
      contextLines: contextLines,
      message: '已移植 ${contextLines.length} 則上下文到「${door.title}」',
    );
  }

  /// 從對話建立新門並移植上下文
  Future<ContextTransferResult> transferToNewDoor({
    required Conversation sourceConversation,
    required String doorTitle,
    String? parentDoorId,
  }) async {
    final contextLines = extractContext(sourceConversation);
    final intent = extractIntent(sourceConversation);

    final now = DateTime.now();
    final door = ProjectDoor(
      id: 'project-door-${now.microsecondsSinceEpoch}',
      title: doorTitle,
      sourceIntent: intent,
      currentFlow: '目標定義',
      intakeQuestions: const [],
      requiredBridges: const [],
      createdAt: now,
      updatedAt: now,
      status: ProjectDoor.statusActive,
      secondBrainEntryId: 'second-brain-project-door-${now.microsecondsSinceEpoch}',
      parentDoorId: parentDoorId,
    );

    await _doorStore.saveActive(door);

    return transferToDoor(
      sourceConversationId: sourceConversation.id,
      targetDoorId: door.id,
      contextLines: contextLines,
      intentSummary: intent,
    );
  }
}
