// transurfing_engine.dart
// [教練 Agent 2026-08-08] Transurfing 運轉核心
//
// 大腦系統的「導航員」——不取代 BrainContainer 的萃取/存儲/檢索，
// 而是在其上層加入水流追蹤、門偵測、橋建造。
//
// 核心檔案：docs/CORE_TRANSURFING.md
//
// 設計原則：
// 1. 輕量——不引入新的 DB table，複用 BrainRoom + memory metadata
// 2. 可選——BrainContainer 沒有它也能正常運作
// 3. 漸進——先做水流偵測，再做門/橋

import 'transurfing_event.dart';
import 'bridge_service.dart';

/// [教練 Agent 2026-08-08] 話題偏離提示
///
/// 當使用者的訊息跟當前水流完全沒有交集時，
/// TransurfingEngine 回傳此物件讓呼叫者決定下一步。
class StreamShiftHint {
  final StreamState currentStream;
  final String message;

  const StreamShiftHint({
    required this.currentStream,
    required this.message,
  });

  /// 建議的橋描述（暫停水流時留下）
  String get suggestedBridgeNote {
    return '水流「${currentStream.title}」暫停——使用者切換到新話題';
  }
}

/// 一條水流的可追蹤狀態
class StreamState {
  /// 水流 ID（從內容 hash 或時間戳生成）
  final String id;

  /// 水流標題（使用者可讀）
  final String title;

  /// 水流當前狀態
  final StreamPhase phase;

  /// 水流的主題關鍵詞
  final List<String> topicKeywords;

  /// 這條水流從哪裡分出來（母水流的 ID，如果是從另一條分出來的）
  final String? parentStreamId;

  /// 創建時間
  final DateTime createdAt;

  /// 最後活動時間
  final DateTime lastActiveAt;

  /// 完成時間（如果有）
  final DateTime? completedAt;

  /// 這條水流的橋——完成或暫停時留下的接續路徑
  final String? bridgeNote;

  /// [Step 1 2026-08-18 復活] 水流去向——完成時匯入 'system' 或分流時指向門 ID
  final String? flowsTo;

  /// [Step 1] 別名：這條水流從哪裡來（= parentStreamId）
  String? get source => parentStreamId;

  const StreamState({
    required this.id,
    required this.title,
    required this.phase,
    required this.topicKeywords,
    this.parentStreamId,
    required this.createdAt,
    required this.lastActiveAt,
    this.completedAt,
    this.bridgeNote,
    this.flowsTo,
  });

  StreamState copyWith({
    StreamPhase? phase,
    DateTime? lastActiveAt,
    DateTime? completedAt,
    String? bridgeNote,
    List<String>? topicKeywords,
    String? flowsTo,
  }) {
    return StreamState(
      id: id,
      title: title,
      phase: phase ?? this.phase,
      topicKeywords: topicKeywords ?? this.topicKeywords,
      parentStreamId: parentStreamId,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      completedAt: completedAt ?? this.completedAt,
      bridgeNote: bridgeNote ?? this.bridgeNote,
      flowsTo: flowsTo ?? this.flowsTo,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'phase': phase.name,
        'topicKeywords': topicKeywords,
        'parentStreamId': parentStreamId,
        'createdAt': createdAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'bridgeNote': bridgeNote,
      };

  factory StreamState.fromJson(Map<String, dynamic> json) {
    return StreamState(
      id: json['id'] as String,
      title: json['title'] as String,
      phase: StreamPhase.fromString(json['phase'] as String),
      topicKeywords:
          (json['topicKeywords'] as List<dynamic>?)?.cast<String>() ?? [],
      parentStreamId: json['parentStreamId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      bridgeNote: json['bridgeNote'] as String?,
    );
  }
}

/// 水流的生命階段
enum StreamPhase {
  /// 活躍中——使用者正在這條水流裡工作
  active,

  /// 暫停——使用者切換到別的事，但這條水流還沒完成
  paused,

  /// 已完成——水流已匯入，成果已落地
  completed,

  /// 已分流——這條水流分出了新門，等待從新門回來接續
  branched,

  /// [Step 3 2026-08-18 復活] 等待確認——水流宣稱完成，等使用者/Agent 確認後才匯入
  awaitingConfirmation,
  ;

  static StreamPhase fromString(String value) {
    return StreamPhase.values.firstWhere(
      (p) => p.name == value,
      orElse: () => StreamPhase.active,
    );
  }
}

/// 一扇門的紀錄
class DoorRecord {
  final String id;
  final String title;

  /// 這扇門從哪條水流分出來的
  final String parentStreamId;

  /// 這扇門完成後應該回到哪條水流（通常是 parentStreamId，但可能不同）
  final String returnToStreamId;

  final DateTime createdAt;
  final DateTime? enteredAt;
  final DateTime? completedAt;

  const DoorRecord({
    required this.id,
    required this.title,
    required this.parentStreamId,
    required this.returnToStreamId,
    required this.createdAt,
    this.enteredAt,
    this.completedAt,
  });
}

/// [教練 Agent 2026-08-08] Transurfing Engine
///
/// 大腦系統的導航層。在 BrainContainer 的萃取/存儲之上，
/// 加入水流追蹤、門偵測、橋建造。
///
/// 所有狀態存在記憶體中（Session 級），未來可以持久化到 SharedPreferences。
/// 這是有意的設計：水流追蹤是動態的，不需要永久保存每一次的 session 水流。
class TransurfingEngine {
  TransurfingEngine._();
  static final TransurfingEngine instance = TransurfingEngine._();

  /// 當前活躍的水流
  StreamState? _activeStream;

  /// 所有已知的水流（ID → 狀態）
  final Map<String, StreamState> _streams = {};

  /// 所有門的紀錄
  final Map<String, DoorRecord> _doors = {};

  /// 當前活躍的水流
  StreamState? get activeStream => _activeStream;

  /// 所有水流（活的 + 已完成的）
  List<StreamState> get allStreams =>
      _streams.values.toList()..sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));

  /// 所有暫停的水流（可以從橋回來接續的）
  List<StreamState> get pausedStreams =>
      _streams.values.where((s) => s.phase == StreamPhase.paused).toList()
        ..sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));

  /// 所有已分流的水流（等待從新門回來）
  List<StreamState> get branchedStreams =>
      _streams.values.where((s) => s.phase == StreamPhase.branched).toList();

  /// [Step 4 2026-08-18 復活] 所有門（BridgeService 查詢用）
  List<DoorRecord> get allDoors => _doors.values.toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// [2026-08-18 復活] 測試隔離用——清空全部狀態
  void reset() {
    _activeStream = null;
    _streams.clear();
    _doors.clear();
  }

  // ──────────────────────────────────────────────
  // 水流管理
  // ──────────────────────────────────────────────

  /// [教練 Agent 2026-08-08] 偵測使用者訊息是否偏離當前水流
  ///
  /// 判斷邏輯：
  /// - 如果沒有活躍水流 → 回傳 null（不需要偵測）
  /// - 如果有活躍水流 → 比較訊息內容跟水流關鍵詞的交集
  ///   - 交集 ≥ 1 → 不偏離（更新 lastActiveAt）
  ///   - 交集 = 0 且訊息長度 > 5 → 可能偏離，回傳 StreamShiftHint
  ///
  /// 回傳的 StreamShiftHint 讓呼叫者決定：
  /// - 要不要暫停當前水流
  /// - 要不要開新水流
  StreamShiftHint? detectTopicShift(String userMessage) {
    if (_activeStream == null) return null;
    if (userMessage.trim().length < 5) return null;

    final keywords = _activeStream!.topicKeywords;
    if (keywords.isEmpty) return null; // 沒有關鍵詞，無法判斷

    final msgLower = userMessage.toLowerCase();
    final hasOverlap = keywords.any(
      (k) => msgLower.contains(k.toLowerCase()),
    );

    if (hasOverlap) {
      // 還在同一條水流裡——更新時間
      _streams[_activeStream!.id] = _activeStream!.copyWith(
        lastActiveAt: DateTime.now(),
      );
      return null;
    }

    // 偏離了
    return StreamShiftHint(
      currentStream: _activeStream!,
      message: userMessage,
    );
  }

  /// [教練 Agent 2026-08-08] 偵測使用者是否回到一條暫停或分流的水流
  ///
  /// 當使用者沒有活躍水流、或偏離了當前水流時，
  /// 檢查這則訊息是否匹配到某條暫停的水流的關鍵詞。
  ///
  /// 回傳匹配到的水流（如果有的話），呼叫者可以決定是否恢復。
  StreamState? detectResume(String userMessage) {
    if (userMessage.trim().length < 3) return null;

    final msgLower = userMessage.toLowerCase();
    final candidates = [...pausedStreams, ...branchedStreams];
    if (candidates.isEmpty) return null;

    // 找關鍵詞匹配最多的那條
    StreamState? bestMatch;
    int bestOverlap = 0;
    for (final stream in candidates) {
      for (final keyword in stream.topicKeywords) {
        if (msgLower.contains(keyword.toLowerCase())) {
          bestOverlap++;
          if (bestOverlap > 0 && bestMatch == null) {
            bestMatch = stream;
          } else if (bestOverlap > 0 && bestMatch != null) {
            // 比較：這條的水流關鍵詞匹配數 vs 之前的
            final prevOverlap = bestMatch!.topicKeywords
                .where((k) => msgLower.contains(k.toLowerCase()))
                .length;
            final thisOverlap = stream.topicKeywords
                .where((k) => msgLower.contains(k.toLowerCase()))
                .length;
            if (thisOverlap > prevOverlap) {
              bestMatch = stream;
            }
          }
        }
      }
    }

    return bestMatch;
  }

  /// 啟動或恢復一條水流
  ///
  /// [title] 水流標題（使用者可讀）
  /// [topicKeywords] 水流主題關鍵詞（用於跨 session 匹配）
  /// [parentStreamId] 如果是從另一條水流分出來的
  StreamState startStream({
    required String title,
    List<String> topicKeywords = const [],
    String? parentStreamId,
  }) {
    // 如果已有同名活躍水流，恢復它而不是新建
    final existing = _streams.values.where(
      (s) =>
          s.title == title &&
          (s.phase == StreamPhase.active || s.phase == StreamPhase.paused),
    );
    if (existing.isNotEmpty) {
      final stream = existing.first.copyWith(
        phase: StreamPhase.active,
        lastActiveAt: DateTime.now(),
      );
      _streams[stream.id] = stream;
      _activeStream = stream;
      return stream;
    }

    final now = DateTime.now();
    final stream = StreamState(
      id: 'stream_${now.millisecondsSinceEpoch}',
      title: title,
      phase: StreamPhase.active,
      topicKeywords: topicKeywords,
      parentStreamId: parentStreamId,
      createdAt: now,
      lastActiveAt: now,
    );
    _streams[stream.id] = stream;
    _activeStream = stream;
    return stream;
  }

  /// 暫停當前水流——使用者切換到別的事
  ///
  /// [bridgeNote] 留下橋的描述，讓未來可以從另一個門回來接續
  void pauseActiveStream({String? bridgeNote}) {
    if (_activeStream == null) return;
    _streams[_activeStream!.id] = _activeStream!.copyWith(
      phase: StreamPhase.paused,
      bridgeNote: bridgeNote,
    );
    _activeStream = null;
  }

  /// 完成當前水流——成果已落地
  ///
  /// [bridgeNote] 留下橋的描述，標記未來可以從哪個門回來做後續
  void completeActiveStream({String? bridgeNote}) {
    if (_activeStream == null) return;
    final now = DateTime.now();
    final title = _activeStream!.title;
    final completed = _activeStream!.copyWith(
      phase: StreamPhase.completed,
      completedAt: now,
      bridgeNote: bridgeNote,
      // [Step 1] 完成的水流匯入系統海洋
      flowsTo: _activeStream!.flowsTo ?? 'system',
    );
    _streams[completed.id] = completed;
    _activeStream = null;

    // [教練 Agent 2026-08-08] Layer C：水流匯入事件
    TransurfingEventBroadcaster.instance.broadcast(
      TransurfingEvent(
        type: TransurfingEventType.streamConfluence,
        title: title,
        bridgeNote: bridgeNote,
      ),
    );

    // [Step 4/5 2026-08-18 復活] 自動建橋 + 廣播 bridgeFormed + 寫入 bridges 記憶
    BridgeService.instance.onStreamCompleted(completed);
  }

  /// 從暫停的水流中恢復——從橋回來
  ///
  /// [streamId] 要恢復的水流 ID
  StreamState? resumeStream(String streamId) {
    final stream = _streams[streamId];
    if (stream == null) return null;
    if (stream.phase != StreamPhase.paused &&
        stream.phase != StreamPhase.branched) {
      return null;
    }
    final resumed = stream.copyWith(
      phase: StreamPhase.active,
      lastActiveAt: DateTime.now(),
    );
    _streams[streamId] = resumed;
    _activeStream = resumed;

    // [教練 Agent 2026-08-08] Layer C：水流恢復事件
    TransurfingEventBroadcaster.instance.broadcast(
      TransurfingEvent(
        type: TransurfingEventType.streamResumed,
        title: resumed.title,
      ),
    );
    return resumed;
  }

  // ──────────────────────────────────────────────
  // [Step 3 2026-08-18 復活] 完成確認流程
  // ──────────────────────────────────────────────

  /// 水流宣稱完成——先進入等待確認，不直接匯入
  ///
  /// Agent 說「我做完了」時先標記 awaitingConfirmation，
  /// 等使用者或系統確認後才真正 completeActiveStream。
  void markAwaitingConfirmation({String? bridgeNote}) {
    if (_activeStream == null) return;
    _streams[_activeStream!.id] = _activeStream!.copyWith(
      phase: StreamPhase.awaitingConfirmation,
      bridgeNote: bridgeNote,
    );
    _activeStream = _streams[_activeStream!.id];
  }

  /// 確認完成——awaitingConfirmation → completed（建橋 + 匯入 system）
  void confirmStreamCompletion() {
    if (_activeStream == null) return;
    if (_activeStream!.phase != StreamPhase.awaitingConfirmation) {
      // 不在等待確認狀態——直接走完整完成
      completeActiveStream(bridgeNote: _activeStream!.bridgeNote);
      return;
    }
    completeActiveStream(bridgeNote: _activeStream!.bridgeNote);
  }

  /// 反悔——回到活躍狀態繼續做
  void reactivateStream() {
    if (_activeStream == null) return;
    _streams[_activeStream!.id] = _activeStream!.copyWith(
      phase: StreamPhase.active,
      lastActiveAt: DateTime.now(),
    );
    _activeStream = _streams[_activeStream!.id];
  }

  // ──────────────────────────────────────────────
  // 門管理
  // ──────────────────────────────────────────────

  /// 從當前水流開一扇新門
  ///
  /// 關鍵規則（CORE_TRANSURFING.md）：
  /// 門做完後回到的是門被創立分離時的母水流。
  DoorRecord openDoor({
    required String title,
    String? returnToStreamId,
  }) {
    final parent = _activeStream;
    final now = DateTime.now();
    final door = DoorRecord(
      id: 'door_${now.millisecondsSinceEpoch}',
      title: title,
      parentStreamId: parent?.id ?? '',
      returnToStreamId: returnToStreamId ?? parent?.id ?? '',
      createdAt: now,
      enteredAt: now,
    );
    _doors[door.id] = door;

    // 當前水流標記為已分流，並流向這扇門
    if (parent != null) {
      _streams[parent.id] = parent.copyWith(
        phase: StreamPhase.branched,
        lastActiveAt: now,
        // [Step 1] 分流的水流 flowsTo = 門 ID
        flowsTo: door.id,
      );
    }

    // [教練 Agent 2026-08-08] Layer C：門打開事件
    TransurfingEventBroadcaster.instance.broadcast(
      TransurfingEvent(
        type: TransurfingEventType.doorOpened,
        title: title,
      ),
    );

    // [Step 4/5 2026-08-18 復活] 門橋建成 + 廣播 bridgeFormed
    BridgeService.instance.onDoorOpened(door);

    return door;
  }

  /// 門完成——回到母水流
  ///
  /// 核心規則：回到的是門被創立分離時的母水流，
  /// 不是寫死「回到當前水流」。
  StreamState? closeDoor(String doorId) {
    final door = _doors[doorId];
    if (door == null) return null;

    // 更新門紀錄
    _doors[doorId] = DoorRecord(
      id: door.id,
      title: door.title,
      parentStreamId: door.parentStreamId,
      returnToStreamId: door.returnToStreamId,
      createdAt: door.createdAt,
      enteredAt: door.enteredAt,
      completedAt: DateTime.now(),
    );

    // 回到母水流（如果還活著）
    final returnStream = _streams[door.returnToStreamId];
    if (returnStream != null &&
        (returnStream.phase == StreamPhase.branched ||
            returnStream.phase == StreamPhase.paused)) {
      final resumed = returnStream.copyWith(
        phase: StreamPhase.active,
        lastActiveAt: DateTime.now(),
      );
      _streams[returnStream.id] = resumed;
      _activeStream = resumed;
      return resumed;
    }

    // 母水流已死 → 不強行回到一個已死的水流
    // 門的成果成為新的水流起點
    return null;
  }

  // ──────────────────────────────────────────────
  // 查詢
  // ──────────────────────────────────────────────

  /// 取得所有可以從橋回來的水流
  ///
  /// 包含暫停的 + 已分流的，附帶橋的描述
  List<Map<String, dynamic>> getResumableBridges() {
    final result = <Map<String, dynamic>>[];
    for (final stream in [...pausedStreams, ...branchedStreams]) {
      result.add({
        'streamId': stream.id,
        'title': stream.title,
        'phase': stream.phase.name,
        'bridgeNote': stream.bridgeNote ?? '（未留橋）',
        'lastActive': stream.lastActiveAt.toIso8601String(),
        'keywords': stream.topicKeywords,
      });
    }
    return result;
  }

  /// 序列化全部狀態（用於持久化）
  Map<String, dynamic> toJson() {
    return {
      'activeStreamId': _activeStream?.id,
      'streams': _streams.map((k, v) => MapEntry(k, v.toJson())),
      'doors': _doors.map((k, v) => MapEntry(k, {
            'id': v.id,
            'title': v.title,
            'parentStreamId': v.parentStreamId,
            'returnToStreamId': v.returnToStreamId,
            'createdAt': v.createdAt.toIso8601String(),
            'enteredAt': v.enteredAt?.toIso8601String(),
            'completedAt': v.completedAt?.toIso8601String(),
          })),
    };
  }

  /// 從序列化資料恢復
  void fromJson(Map<String, dynamic> json) {
    _streams.clear();
    _doors.clear();
    _activeStream = null;

    final streams = json['streams'] as Map<String, dynamic>?;
    if (streams != null) {
      for (final entry in streams.entries) {
        _streams[entry.key] =
            StreamState.fromJson(entry.value as Map<String, dynamic>);
      }
    }

    final doors = json['doors'] as Map<String, dynamic>?;
    if (doors != null) {
      for (final entry in doors.entries) {
        final d = entry.value as Map<String, dynamic>;
        _doors[entry.key] = DoorRecord(
          id: d['id'] as String,
          title: d['title'] as String,
          parentStreamId: d['parentStreamId'] as String,
          returnToStreamId: d['returnToStreamId'] as String,
          createdAt: DateTime.parse(d['createdAt'] as String),
          enteredAt: d['enteredAt'] != null
              ? DateTime.parse(d['enteredAt'] as String)
              : null,
          completedAt: d['completedAt'] != null
              ? DateTime.parse(d['completedAt'] as String)
              : null,
        );
      }
    }

    final activeId = json['activeStreamId'] as String?;
    if (activeId != null) {
      _activeStream = _streams[activeId];
    }
  }
}
