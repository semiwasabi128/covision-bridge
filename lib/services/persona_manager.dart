// PersonaManager — 人格分身層
// 不換腦，只換面貌。同一個原生 Agent，人格只是設定檔。
// [Phase 0 Track B 2026-07-17]
//
// 設計原則：
// - 不新建 PersonaConfig 系統（使用者拍板：擴充 Companion，不另建）
// - 直接用 Companion 的 proactivity/verbosity/preferredTools + systemPrompt getter
// - 人格切換不改變 Agent Loop，只換 system prompt suffix
// - 所有人格共享 BrainContainer 記憶

import 'package:flutter/foundation.dart';
import '../models/companion.dart';

class PersonaManager extends ChangeNotifier {
  Companion? _activeCompanion;

  Companion? get activeCompanion => _activeCompanion;

  /// 設定當前活躍夥伴
  void setActiveCompanion(Companion? companion) {
    _activeCompanion = companion;
    notifyListeners();
  }

  /// 組裝人格 system prompt（附加到基礎 prompt 後面）
  ///
  /// 包含：名字、角色、MBTI、個性、專長、行為參數
  String? buildPersonaPrompt() {
    final c = _activeCompanion;
    if (c == null) return null;

    final parts = <String>[];

    // 基本身份
    parts.add('## 你的人格設定');
    parts.add('名稱：${c.name}');
    parts.add('角色：${_roleLabel(c.role)}');

    if (c.mbtiCode.isNotEmpty) {
      parts.add('MBTI：${c.mbtiCode}');
    }

    if (c.personalityTags.isNotEmpty) {
      parts.add('個性：${c.personalityTags.map(_tagLabel).join('、')}');
    }

    // 行為參數 [Phase 0 2026-07-17]
    parts.add('主動程度：${(c.proactivity * 100).round()}%');
    parts.add('話多程度：${(c.verbosity * 100).round()}%');

    if (c.preferredTools.isNotEmpty) {
      parts.add('偏好工具：${c.preferredTools.join('、')}');
    }

    // 系統提示（如果 Companion 有自訂的）
    final sysPrompt = c.systemPrompt;
    if (sysPrompt.isNotEmpty) {
      parts.add('');
      parts.add(sysPrompt);
    }

    // 行為指導
    parts.add('');
    parts.add(_buildBehaviorGuide(c));

    return parts.join('\n');
  }

  /// 根據行為參數生成行為指導
  String _buildBehaviorGuide(Companion c) {
    final guides = <String>[];

    // 主動程度
    if (c.proactivity >= 0.7) {
      guides.add('你是主動的——可以適時提出建議、發現問題時主動告知。');
    } else if (c.proactivity >= 0.4) {
      guides.add('你的主動程度適中——在使用者需要時提供幫助，不過度干涉。');
    } else {
      guides.add('你是被動的——主要回應使用者的請求，不主動發起。');
    }

    // 話多程度
    if (c.verbosity >= 0.7) {
      guides.add('你的回覆可以詳細豐富，適當補充背景和脈絡。');
    } else if (c.verbosity >= 0.4) {
      guides.add('你的回覆適中，重點清楚不囉嗦。');
    } else {
      guides.add('你的回覆精簡，只說必要的話。');
    }

    return '## 行為指導\n${guides.join('\n')}';
  }

  String _roleLabel(CompanionRole role) {
    switch (role) {
      case CompanionRole.research:
        return '研究員';
      case CompanionRole.writing:
        return '寫作夥伴';
      case CompanionRole.translation:
        return '翻譯夥伴';
      case CompanionRole.farmManager:
        return '管家';
      case CompanionRole.general:
        return '通用夥伴';
      case CompanionRole.custom:
        return '自訂角色';
    }
  }

  String _tagLabel(PersonalityTag tag) {
    switch (tag) {
      case PersonalityTag.warm:
        return '溫暖';
      case PersonalityTag.humorous:
        return '幽默';
      case PersonalityTag.concise:
        return '簡潔';
      case PersonalityTag.detailed:
        return '詳盡';
      case PersonalityTag.precise:
        return '嚴謹';
      case PersonalityTag.direct:
        return '直率';
    }
  }
}
