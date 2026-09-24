// P0.5 對話任務證據（Task Evidence）。
//
// 設計原則見 docs/CHAT_TASK_EVIDENCE_DESIGN.md:
//   - 不暴露 raw AgentToolResult / 絕對路徑 / token / 完整 command output
//   - 由 ChatController 從 AgentLoopResult.turns 白名單 mapper 產出
//   - 寫進 assistant Message.metadata，落 conversation store，重開仍可見
//   - UI 只負責讀取 TaskEvidence.fromMetadata，無法拿到 metadata 原始 map

import 'package:flutter/foundation.dart';

enum TaskEvidenceKind {
  image,
  document,
  search,
  canvas,
  file,
  delegation,
  capability,
  other,
}

enum TaskEvidenceOutcome { completed, partial, failed }

/// [view] 為空白（已開啟 / 已查看）時隱藏按鈕；空字串代表不渲染。
@immutable
class TaskEvidenceAction {
  final String label;
  final String? view; // 對應 ViewKind，null = 不需要跳頁，只執行 callback
  const TaskEvidenceAction({required this.label, this.view});
}

/// 不暴露 raw ref。URL 必須清洗過；本機只保留不洩漏個資的顯示檔名／canvas id。
@immutable
class TaskEvidenceSafeRef {
  final String label;
  final String? url;
  const TaskEvidenceSafeRef({required this.label, this.url});
}

@immutable
class TaskEvidence {
  final String id;
  final TaskEvidenceKind kind;
  final TaskEvidenceOutcome outcome;
  final String headline;
  final String summary;
  final List<TaskEvidenceAction> actions;
  final List<TaskEvidenceSafeRef> references;
  final String? mediaUrl;
  final Map<String, dynamic>? safeMetadata;

  const TaskEvidence({
    required this.id,
    required this.kind,
    required this.outcome,
    required this.headline,
    required this.summary,
    this.actions = const [],
    this.references = const [],
    this.mediaUrl,
    this.safeMetadata,
  });

  /// 從 assistant message.metadata.tasks 讀取，無資料回傳空列表。
  /// 此方法為 UI 唯一入口；不要繞過它直接讀 raw map。
  static List<TaskEvidence> fromMetadata(Map<String, dynamic>? raw) {
    final list = raw?['tasks'];
    if (list is! List) return const [];
    final out = <TaskEvidence>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final kind = _parseKind(entry['kind']?.toString());
      final outcome = _parseOutcome(entry['outcome']?.toString());
      final headline = entry['headline']?.toString() ?? '';
      if (headline.isEmpty) continue;
      out.add(
        TaskEvidence(
          id: entry['id']?.toString() ?? '',
          kind: kind,
          outcome: outcome,
          headline: headline,
          summary: entry['summary']?.toString() ?? '',
          actions: _parseActions(entry['actions']),
          references: _parseRefs(entry['refs']),
          mediaUrl: entry['mediaUrl']?.toString(),
          safeMetadata: entry['safeMetadata'] is Map
              ? Map<String, dynamic>.from(
                  (entry['safeMetadata'] as Map).cast<String, dynamic>(),
                )
              : null,
        ),
      );
    }
    return out;
  }

  static TaskEvidenceKind _parseKind(String? raw) {
    for (final k in TaskEvidenceKind.values) {
      if (k.name == raw) return k;
    }
    return TaskEvidenceKind.other;
  }

  static TaskEvidenceOutcome _parseOutcome(String? raw) {
    for (final o in TaskEvidenceOutcome.values) {
      if (o.name == raw) return o;
    }
    return TaskEvidenceOutcome.completed;
  }

  static List<TaskEvidenceAction> _parseActions(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (a) => TaskEvidenceAction(
            label: a['label']?.toString() ?? '',
            view: a['view']?.toString(),
          ),
        )
        .where((a) => a.label.isNotEmpty)
        .toList(growable: false);
  }

  static List<TaskEvidenceSafeRef> _parseRefs(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (r) => TaskEvidenceSafeRef(
            label: r['label']?.toString() ?? '',
            url: r['url']?.toString(),
          ),
        )
        .where((r) => r.label.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'kind': kind.name,
    'outcome': outcome.name,
    'headline': headline,
    'summary': summary,
    'actions': actions
        .map((a) => {'label': a.label, if (a.view != null) 'view': a.view})
        .toList(),
    'refs': references
        .map((r) => {'label': r.label, if (r.url != null) 'url': r.url})
        .toList(),
    if (mediaUrl != null) 'mediaUrl': mediaUrl,
    if (safeMetadata != null) 'safeMetadata': safeMetadata,
  };
}

/// 從 AgentLoopTurn 列表建立安全的 TaskEvidence 列表。
///
/// 安全合約：
///   - 必須是白名單內工具：generate_image / create_document / web_search /
///     browse / memory_search / canvas_place / canvas_connect / canvas_remove /
///     delegate_batch / delegate_subagent / check_capability_status
///   - raw content 不會被吐回；只提取：
///       - 成功／失敗
///       - 已清洗的 mediaUrl
///       - 已清洗的 metadata 白名單 key
///
/// 新增非白名單工具 → 開新分支回傳 kind: other / headline 由 title 推；
/// 若仍無資訊則完全不產生 TaskEvidence。
class TaskEvidenceBuilder {
  static const Set<String> _supported = {
    'generate_image',
    'create_document',
    'web_search',
    'browse',
    'memory_search',
    'canvas_place',
    'canvas_connect',
    'canvas_remove',
    'delegate_batch',
    'delegate_subagent',
    'check_capability_status',
  };

  /// 從 turns 產生 tasks list；寫進 Message.metadata。
  static List<Map<String, dynamic>> build(Iterable<dynamic> turns) {
    final tasks = <Map<String, dynamic>>[];
    final imageIds = <String>{};
    final canvasIds = <String>{};
    final delegatedIds = <String>{};
    String? singleImageUrl;

    for (final t in turns) {
      final toolCall = t.toolCall as dynamic;
      final toolResult = t.toolResult as dynamic;
      final call = toolCall as Object?;
      if (call == null) continue;
      final name = (call as dynamic).name?.toString() ?? '';
      if (!_supported.contains(name)) continue;
      final ok = (toolResult as dynamic)?.success == true;
      final mediaUrl = (toolResult as dynamic)?.mediaUrl?.toString();
      final rawMeta = ((toolResult as dynamic)?.metadata as Map?)
          ?.cast<String, dynamic>();
      final safeMeta = _safeMetadataFor(name, rawMeta);

      switch (name) {
        case 'generate_image':
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            singleImageUrl ??= mediaUrl;
            imageIds.add(mediaUrl);
          }
          tasks.add({
            'id': 'image-${(call as dynamic).name}',
            'kind': TaskEvidenceKind.image.name,
            'outcome': ok
                ? TaskEvidenceOutcome.completed.name
                : TaskEvidenceOutcome.failed.name,
            'headline': ok ? '已生成 1 張圖片' : '圖片生成失敗',
            'summary': ok ? 'AI 已建立圖片，可開啟或加入 Canvas' : '請重新描述需求或換個模型試試',
            'actions': ok
                ? [
                    {'label': '開啟', 'view': 'media'},
                    {'label': '加入 Canvas', 'view': 'canvas_image'},
                  ]
                : const [],
            'mediaUrl': mediaUrl,
            if (safeMeta != null) 'safeMetadata': safeMeta,
          });
          break;
        case 'create_document':
          tasks.add({
            'kind': TaskEvidenceKind.document.name,
            'outcome': ok
                ? TaskEvidenceOutcome.completed.name
                : TaskEvidenceOutcome.failed.name,
            'headline': ok ? '已建立 1 份文件' : '文件未建立',
            'summary': ok ? 'Markdown 已存到 Bridge 路徑，可預覽或開啟' : '請說明文件用途再試一次',
            'actions': ok
                ? [
                    {'label': '預覽', 'view': 'document'},
                    {'label': '開啟', 'view': 'open_path'},
                  ]
                : const [],
            if (mediaUrl != null) 'mediaUrl': mediaUrl,
          });
          break;
        case 'web_search':
        case 'browse':
          tasks.add({
            'kind': TaskEvidenceKind.search.name,
            'outcome': ok
                ? TaskEvidenceOutcome.completed.name
                : TaskEvidenceOutcome.failed.name,
            'headline': ok ? '已查閱網路資料' : '查詢失敗',
            'summary': ok ? '請查看下方來源摘要' : '請調整關鍵字或換個搜尋方向',
            'actions': ok
                ? [
                    {'label': '查看來源', 'view': 'search_results'},
                  ]
                : const [],
          });
          break;
        case 'memory_search':
          tasks.add({
            'kind': TaskEvidenceKind.search.name,
            'outcome': ok
                ? TaskEvidenceOutcome.completed.name
                : TaskEvidenceOutcome.failed.name,
            'headline': ok ? '已查閱內部記憶' : '查詢失敗',
            'summary': ok ? '相關記憶已餵回對話上下文' : '請確認夥伴資料是否已有相關紀錄',
          });
          break;
        case 'canvas_place':
        case 'canvas_connect':
        case 'canvas_remove':
          canvasIds.add(name);
          tasks.add({
            'kind': TaskEvidenceKind.canvas.name,
            'outcome': ok
                ? TaskEvidenceOutcome.completed.name
                : TaskEvidenceOutcome.failed.name,
            'headline': ok ? 'Canvas 已更新' : 'Canvas 未更新',
            'summary': ok ? '新增/連接了節點，可到畫布確認' : '請回到 Canvas 重試',
            'actions': ok
                ? [
                    {'label': '查看 Canvas', 'view': 'canvas'},
                  ]
                : const [],
          });
          break;
        case 'delegate_batch':
        case 'delegate_subagent':
          delegatedIds.add(name);
          tasks.add({
            'kind': TaskEvidenceKind.delegation.name,
            'outcome': ok
                ? TaskEvidenceOutcome.completed.name
                : TaskEvidenceOutcome.partial.name,
            'headline': '已分派子任務',
            'summary': ok ? '子代理完成，可查看摘要' : '部分子代理可能失敗',
            'actions': ok
                ? [
                    {'label': '查看摘要', 'view': 'delegation'},
                  ]
                : const [],
          });
          break;
        case 'check_capability_status':
          tasks.add({
            'kind': TaskEvidenceKind.capability.name,
            'outcome': ok
                ? TaskEvidenceOutcome.completed.name
                : TaskEvidenceOutcome.failed.name,
            'headline': ok ? '已檢查設定狀態' : '設定狀態查詢失敗',
            'summary': ok ? '請查看下方可用能力摘要' : '請到 Bridge 設定重新整理',
            'actions': ok
                ? [
                    {'label': '前往設定', 'view': 'settings'},
                  ]
                : const [],
          });
          break;
      }
    }

    // 連續相同任務收成單卡，避免重複噪音。
    return _deduplicate(tasks);
  }

  static Map<String, dynamic>? _safeMetadataFor(
    String toolName,
    Map<String, dynamic>? raw,
  ) {
    if (raw == null) return null;
    final safe = <String, dynamic>{};
    for (final key in const ['title', 'provider', 'model', 'mime']) {
      final v = raw[key];
      if (v == null) continue;
      safe[key] = v.toString();
    }
    return safe.isEmpty ? null : safe;
  }

  /// 同 kind 連續出現 → 合併成一張卡（累計摘要）；失敗的拆出來顯示。
  /// 任何非支援 kind 在這個函式裡都會被忽略。
  static List<Map<String, dynamic>> _deduplicate(
    List<Map<String, dynamic>> tasks,
  ) {
    final byKind = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final t in tasks) {
      final kind = t['kind']?.toString() ?? 'other';
      if (!byKind.containsKey(kind)) {
        byKind[kind] = <Map<String, dynamic>>[];
        order.add(kind);
      }
      byKind[kind]!.add(t);
    }
    final out = <Map<String, dynamic>>[];
    for (final kind in order) {
      final group = byKind[kind]!;
      if (group.length == 1) {
        out.add(group.first);
        continue;
      }
      final allOk = group.every(
        (t) => t['outcome'] == TaskEvidenceOutcome.completed.name,
      );
      final merged = Map<String, dynamic>.from(group.first);
      merged['outcome'] = allOk
          ? TaskEvidenceOutcome.completed.name
          : TaskEvidenceOutcome.partial.name;
      merged['summary'] = allOk
          ? '${group.length} 個 Canvas 變更已生效'
          : '${group.length} 個 Canvas 變更，請查看 Canvas 確認';
      // 合併多個 actions，去重
      final actions = <Map<String, dynamic>>[];
      final seenActions = <String>{};
      for (final t in group) {
        final list = t['actions'];
        if (list is! List) continue;
        for (final a in list) {
          if (a is! Map) continue;
          final label = a['label']?.toString() ?? '';
          if (label.isEmpty) continue;
          if (seenActions.add(label)) {
            actions.add(
              a is Map<String, dynamic>
                  ? a
                  : Map<String, dynamic>.from(a.cast<String, dynamic>()),
            );
          }
        }
      }
      merged['actions'] = actions;
      out.add(merged);
    }
    return out;
  }

  /// 匯出 metadata.tasks 使用的 wrapper；key 固定為 'tasks'。
  static Map<String, dynamic> patchAssistantMetadata({
    Map<String, dynamic>? existing,
    required List<Map<String, dynamic>> tasks,
  }) {
    final next = Map<String, dynamic>.from(existing ?? const {});
    if (tasks.isEmpty) {
      next.remove('tasks');
    } else {
      next['tasks'] = tasks;
    }
    return next;
  }
}
