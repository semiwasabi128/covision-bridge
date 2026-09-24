// compass_models.dart
// 羅盤系統資料模型 — 人機共視的器官/規則/手術日誌。
//
// 設計依據 docs/specs/2026-09-06-compass-system.md（Blue 2026-09-06 拍板）：
// - 雙層所有權：事實層（自動採集）不可手改；意義層（人擁有）；
//   規則層（共治）——白名單制：視覺規則即時生效、行為規則需人確認。
// - 每個欄位帶 (author, time)——沒有匿名真相，沒有無主修改。
// - 規則歷史 append-only；退役規則不刪除。

/// 欄位作者標記慣例：`human:Blue` | `agent:小橋` | `auto:harvest`
class CompassAuthor {
  static const harvest = 'auto:harvest';
  static String human(String name) => 'human:$name';
  static String agent(String name) => 'agent:$name';
}

/// 器官健康狀態（證據三源合併後的結論）
enum CompassHealth { green, amber, red }

/// 規則種類 — 白名單制（Blue 2026-09-06 拍板第 6 條）：
/// visual = 純視覺參數，改了即時生效；behavioral = 影響資料/執行行為，需人按「套用」。
enum CompassRuleKind { visual, behavioral }

/// 規則狀態：active 生效中 | retired 退役（保留歷史，不刪除）| pendingApply 待人確認
enum CompassRuleStatus { active, retired, pendingApply }

/// 器官事實層（自動採集擁有，人與 Agent 不可改）
class OrganFacts {
  final List<String> paths; // 檔案路徑（相對 repo lib/）
  final List<String> anchors; // 類別/方法錨點（grep 驗證用）
  final List<String> deps; // 依賴的其他器官 id
  final List<String> endpoints; // 相關端點/port
  final int loc; // 檔案總行數（採集當下）
  final DateTime? lastVerifiedAt; // null = 尚未驗證

  const OrganFacts({
    this.paths = const [],
    this.anchors = const [],
    this.deps = const [],
    this.endpoints = const [],
    this.loc = 0,
    this.lastVerifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'paths': paths,
        'anchors': anchors,
        'deps': deps,
        'endpoints': endpoints,
        'loc': loc,
        'lastVerifiedAt': lastVerifiedAt?.toIso8601String(),
      };

  factory OrganFacts.fromJson(Map<String, dynamic> j) => OrganFacts(
        paths: (j['paths'] as List? ?? []).cast<String>(),
        anchors: (j['anchors'] as List? ?? []).cast<String>(),
        deps: (j['deps'] as List? ?? []).cast<String>(),
        endpoints: (j['endpoints'] as List? ?? []).cast<String>(),
        loc: (j['loc'] as num?)?.toInt() ?? 0,
        lastVerifiedAt: DateTime.tryParse(j['lastVerifiedAt'] as String? ?? ''),
      );
}

/// 器官健康證據（三源：端點回應 + process 存活 + 關鍵 mtime）
class OrganHealthEvidence {
  final CompassHealth status;
  final String summary; // 一句人話：「本地模型 server 回應正常」
  final DateTime checkedAt;

  const OrganHealthEvidence({
    this.status = CompassHealth.green,
    this.summary = '',
    required this.checkedAt,
  });

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'summary': summary,
        'checkedAt': checkedAt.toIso8601String(),
      };

  factory OrganHealthEvidence.fromJson(Map<String, dynamic> j) =>
      OrganHealthEvidence(
        status: CompassHealth.values.firstWhere(
          (s) => s.name == (j['status'] as String? ?? 'green'),
          orElse: () => CompassHealth.green,
        ),
        summary: j['summary'] as String? ?? '',
        checkedAt:
            DateTime.tryParse(j['checkedAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// 羅盤器官 — App 身體的一個部位
class CompassOrgan {
  final String id; // 'chat' | 'canvas.engine' | 'brain.galaxy3d' ...
  final String systemGroup; // 對話|畫布|大腦|向量|服務群|外觀|系統
  final String name;
  final OrganFacts facts;
  final bool anchorOk; // 錨點驗證：false = 琥珀「待重新驗證」

  const CompassOrgan({
    required this.id,
    required this.systemGroup,
    required this.name,
    this.facts = const OrganFacts(),
    this.anchorOk = true,
  });
}

/// 意義層欄位（人擁有，署名制）
class CompassMeaningField {
  final String organId;
  final String key; // nickname | humanDescription | importance | constraints
  final String value; // JSON-encoded value（統一字串儲存）
  final String author;
  final DateTime updatedAt;

  const CompassMeaningField({
    required this.organId,
    required this.key,
    required this.value,
    required this.author,
    required this.updatedAt,
  });
}

/// 已知陷阱（人與 Agent 都可加，各自署名）
class CompassPitfall {
  final int? id;
  final String organId;
  final String text;
  final String author;
  final DateTime at;

  const CompassPitfall({
    this.id,
    required this.organId,
    required this.text,
    required this.author,
    required this.at,
  });
}

/// 顯示規則卡 — 一條規則一張卡（規則層）
class CompassRule {
  final String id; // 'galaxy.lightAuthority' | 'galaxy.modeCoef' ...
  final String organId;
  final String description; // 白話：這條規則管什麼
  final String why; // 強制欄位：這條規則解決什麼問題
  final Map<String, dynamic> params; // 目前生效參數
  final CompassRuleKind kind; // visual=即時生效 | behavioral=需確認
  final CompassRuleStatus status;
  final String updatedBy;
  final DateTime updatedAt;

  const CompassRule({
    required this.id,
    required this.organId,
    required this.description,
    required this.why,
    required this.params,
    this.kind = CompassRuleKind.visual,
    this.status = CompassRuleStatus.active,
    required this.updatedBy,
    required this.updatedAt,
  });

  CompassRule copyWith({
    Map<String, dynamic>? params,
    CompassRuleStatus? status,
    String? updatedBy,
    DateTime? updatedAt,
  }) =>
      CompassRule(
        id: id,
        organId: organId,
        description: description,
        why: why,
        params: params ?? this.params,
        kind: kind,
        status: status ?? this.status,
        updatedBy: updatedBy ?? this.updatedBy,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// 規則修改軌跡（append-only，反覆設定的終結機制）
class CompassRuleChange {
  final int? id;
  final String ruleId;
  final String author;
  final DateTime at;
  final Map<String, dynamic>? prevParams;
  final Map<String, dynamic> newParams;
  final String reason;

  const CompassRuleChange({
    this.id,
    required this.ruleId,
    required this.author,
    required this.at,
    this.prevParams,
    required this.newParams,
    required this.reason,
  });
}

/// 手術日誌（變更時間線的一筆：誰/何時/動了什麼/為什麼）
class CompassSurgeryLog {
  final int? id;
  final String? organId;
  final String? ruleId;
  final String author;
  final DateTime at;
  final String action; // install | repair | meaningEdit | ruleChange | harvest | retire
  final String detail;

  const CompassSurgeryLog({
    this.id,
    this.organId,
    this.ruleId,
    required this.author,
    required this.at,
    required this.action,
    required this.detail,
  });
}
