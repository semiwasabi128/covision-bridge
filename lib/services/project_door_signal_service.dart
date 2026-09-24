class ProjectDoorSignal {
  final String title;
  final String sourceIntent;
  final String firstFlow;
  final List<String> intakeQuestions;
  final List<String> requiredBridges;

  const ProjectDoorSignal({
    required this.title,
    required this.sourceIntent,
    required this.firstFlow,
    required this.intakeQuestions,
    required this.requiredBridges,
  });
}

class ProjectDoorSignalService {
  const ProjectDoorSignalService();

  ProjectDoorSignal? detect({
    required String text,
    required Iterable<String> conversationContext,
    String? conversationTitle,
  }) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    final wantsToStart = _containsAny(normalized, const [
      '開始動手',
      '開始做',
      '開始執行',
      '開始推進',
      '一步一步',
      '一步步',
      '帶我完成',
      '帶我做',
      '帶我一步',
      '幫我規劃',
      '幫我設計',
      '完成這個目標',
      '我打算',
      '我要做',
      '我們開始',
      '第一步',
      '下一步',
      '計畫',
      '專案',
      '企劃',
      '案子',
      '開案',
      '立案',
      '開個專案',
      '開一個專案',
      '啟動專案',
      '正式啟動',
      '做成專案',
      '做起來',
      '把它變成專案',
      '把這個做起來',
      '把這件事做起來',
      '落地',
      '實作',
      'mvp',
    ]);
    if (!wantsToStart) return null;

    final context = [
      ...conversationContext,
      ?conversationTitle,
      normalized,
    ].join('\n').toLowerCase();

    final hasProjectScale = _containsAny(context, const [
      '直播帶貨',
      '銷售商品',
      'ai agent',
      '工作流',
      '上線',
      '專案',
      '目標',
      '受眾',
      '品牌',
      '商品',
      '平台',
      'mvp',
      '案子',
      '這件事',
      '做起來',
      '產品定位',
      '成功標準',
      'kpi',
      '工作步驟',
    ]);
    final hasStructuredPlanningAnswer = _containsAny(normalized, const [
      '目標',
      '產品',
      '受眾',
      '定位',
      '成功標準',
      'kpi',
      '預算',
      '時程',
      '平台',
    ]);
    if (!hasProjectScale && !hasStructuredPlanningAnswer) return null;

    return ProjectDoorSignal(
      title: titleForContext(context),
      sourceIntent: text,
      firstFlow: '目標定義',
      intakeQuestions: const [
        '你要銷售或推進的核心產品/服務是什麼？',
        '目標受眾是誰？他們目前最痛的問題是什麼？',
        '你希望 AI 角色扮演什麼定位：專家、陪伴、娛樂、銷售，還是混合？',
        '第一版成功標準是什麼：成交、名單、觀看數、內容產出，還是品牌曝光？',
        '你希望第一版 MVP 在幾天內完成？',
      ],
      requiredBridges: bridgesForContext(context),
    );
  }

  String titleForContext(String context) {
    if (_containsAny(context, const ['semidao', 'semi dao', '山門dao'])) {
      return 'SemiDAO';
    }
    if (_containsAny(context, const [
      '創建角色',
      '創造角色',
      '角色資產',
      '角色資產包',
      '召喚替身',
    ])) {
      return 'AI 角色創建專案';
    }
    if (_containsAny(context, const ['直播帶貨', '銷售商品'])) {
      return 'AI 角色直播帶貨專案';
    }
    if (_containsAny(context, const ['音樂', '品牌聲音'])) {
      return 'AI 品牌聲音專案';
    }
    if (_containsAny(context, const ['影片', '短片', '影像'])) {
      return 'AI 影片內容專案';
    }
    return '新的橋樑專案';
  }

  List<String> bridgesForContext(String context) {
    final bridges = <String>{
      if (_containsAny(context, const ['影片', '直播', '短片', '影像'])) '影片生成橋',
      if (_containsAny(context, const ['語音', '音樂', '聲音', '配樂'])) '語音/音樂橋',
      if (_containsAny(context, const ['直播', 'youtube', 'twitch', 'facebook']))
        '直播平台橋',
      if (_containsAny(context, const ['商品', '銷售', '帶貨'])) '商品資料橋',
      if (_containsAny(context, const ['金流', '物流', '成交', '購買'])) '金流/物流橋',
      if (_containsAny(context, const [
        '創建角色',
        '創造角色',
        '角色資產',
        '角色資產包',
        '召喚替身',
      ]))
        '角色資產橋',
      if (_containsAny(context, const ['semidao', 'semi dao', '山門dao']))
        'SemiDAO 社群資產橋',
      '第二大腦專案索引',
    };
    return bridges.toList(growable: false);
  }

  bool _containsAny(String source, Iterable<String> needles) {
    return needles.any(source.contains);
  }
}
