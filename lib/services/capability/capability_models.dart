/// Capability 資料模型 — 能力導向的金鑰與服務管理
///
/// 設計文件: 02-架構設計/keychain-settings-design.md
/// [教練 Agent 2026-08-01] Phase 0 — 能力中心地基
///
/// 核心概念: 使用者選擇「我想做什麼」（能力），
/// 而不是「我想用哪個 Provider」。
/// 每個能力下可以有多個服務提供者。
library;

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════
// Enums
// ═══════════════════════════════════════════════════

/// 10 大能力分類
enum CapabilityId {
  textReasoning,      // 文字推理（LLM）
  imageGeneration,    // 圖片生成
  imageUnderstanding, // 圖片理解（Vision）
  videoGeneration,    // 影片生成
  musicGeneration,    // 音樂生成
  voiceSynthesis,     // 語音合成（TTS）
  voiceRecognition,   // 語音辨識（STT）
  webSearch,          // 網頁搜尋
  vectorEmbedding,    // 向量嵌入
  characterLock,      // 角色一致性
}

extension CapabilityIdX on CapabilityId {
  String get id {
    switch (this) {
      case CapabilityId.textReasoning: return 'text_reasoning';
      case CapabilityId.imageGeneration: return 'image_generation';
      case CapabilityId.imageUnderstanding: return 'image_understanding';
      case CapabilityId.videoGeneration: return 'video_generation';
      case CapabilityId.musicGeneration: return 'music_generation';
      case CapabilityId.voiceSynthesis: return 'voice_synthesis';
      case CapabilityId.voiceRecognition: return 'voice_recognition';
      case CapabilityId.webSearch: return 'web_search';
      case CapabilityId.vectorEmbedding: return 'vector_embedding';
      case CapabilityId.characterLock: return 'character_lock';
    }
  }

  String get displayName {
    switch (this) {
      case CapabilityId.textReasoning: return '文字推理';
      case CapabilityId.imageGeneration: return '圖片生成';
      case CapabilityId.imageUnderstanding: return '圖片理解';
      case CapabilityId.videoGeneration: return '影片生成';
      case CapabilityId.musicGeneration: return '音樂生成';
      case CapabilityId.voiceSynthesis: return '語音合成';
      case CapabilityId.voiceRecognition: return '語音辨識';
      case CapabilityId.webSearch: return '網頁搜尋';
      case CapabilityId.vectorEmbedding: return '向量嵌入';
      case CapabilityId.characterLock: return '角色一致性';
    }
  }

  String get description {
    switch (this) {
      case CapabilityId.textReasoning: return '聊天、判斷、上下文壓縮與思維儀表';
      case CapabilityId.imageGeneration: return '生成角色形象、插畫、產品圖';
      case CapabilityId.imageUnderstanding: return '辨識圖片內容、物件、文字（OCR）';
      case CapabilityId.videoGeneration: return '從文字或圖片生成影片';
      case CapabilityId.musicGeneration: return '生成音樂曲目與音效';
      case CapabilityId.voiceSynthesis: return '文字轉語音（TTS）';
      case CapabilityId.voiceRecognition: return '語音轉文字（STT）';
      case CapabilityId.webSearch: return '搜尋新聞、網頁、即時資訊';
      case CapabilityId.vectorEmbedding: return '檔案向量化，供語意搜尋使用';
      case CapabilityId.characterLock: return '角色多視角、多服裝一致性圖卡';
    }
  }

  IconData get icon {
    switch (this) {
      case CapabilityId.textReasoning: return Icons.psychology_alt_outlined;
      case CapabilityId.imageGeneration: return Icons.auto_awesome_outlined;
      case CapabilityId.imageUnderstanding: return Icons.visibility_outlined;
      case CapabilityId.videoGeneration: return Icons.movie_creation_outlined;
      case CapabilityId.musicGeneration: return Icons.music_note_outlined;
      case CapabilityId.voiceSynthesis: return Icons.record_voice_over_outlined;
      case CapabilityId.voiceRecognition: return Icons.mic_outlined;
      case CapabilityId.webSearch: return Icons.travel_explore_outlined;
      case CapabilityId.vectorEmbedding: return Icons.hub_outlined;
      case CapabilityId.characterLock: return Icons.face_retouching_natural_outlined;
    }
  }

  /// 能力分類色（用於 UI 卡片）
  Color color(BuildContext context) {
    switch (this) {
      case CapabilityId.textReasoning: return Colors.purple;
      case CapabilityId.imageGeneration: return Colors.pink;
      case CapabilityId.imageUnderstanding: return Colors.teal;
      case CapabilityId.videoGeneration: return Colors.indigo;
      case CapabilityId.musicGeneration: return Colors.orange;
      case CapabilityId.voiceSynthesis: return Colors.brown;
      case CapabilityId.voiceRecognition: return Colors.blueGrey;
      case CapabilityId.webSearch: return Colors.blue;
      case CapabilityId.vectorEmbedding: return Colors.green;
      case CapabilityId.characterLock: return Colors.deepOrange;
    }
  }

  static CapabilityId? fromString(String id) {
    for (final c in CapabilityId.values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// 鑰匙需求類型
enum KeyType {
  apiKey,  // 最常見: OpenAI, MiniMax, Suno...
  oauth,   // OAuth flow: Google, GitHub...
  url,     // 只需 URL: ComfyUI, 本地服務
  none,    // 不需金鑰: 本地模型
}

/// 服務狀態生命週期
enum ServiceStatus {
  active,        // 正常可用
  deprecated,    // 即將下架（顯示警告）
  discontinued,  // 已下架（灰色，不可選）
  beta,          // 測試中
  community,     // 社群提供
}

extension ServiceStatusX on ServiceStatus {
  bool get isUsable => this == ServiceStatus.active || this == ServiceStatus.beta;
  bool get needsWarning => this == ServiceStatus.deprecated;
  bool get isDisabled => this == ServiceStatus.discontinued;
}

// ═══════════════════════════════════════════════════
// 資料模型
// ═══════════════════════════════════════════════════

/// 描述一個服務需要什麼鑰匙
class KeyRequirement {
  final KeyType type;
  final String label;
  final String? hint;
  final String? getUrl;
  final String? storageKey;

  /// 驗證格式（可選），例如 r'^sk-...'
  final String? validatorPattern;

  const KeyRequirement({
    required this.type,
    required this.label,
    this.hint,
    this.getUrl,
    this.storageKey,
    this.validatorPattern,
  });

  /// 不需要金鑰
  static const none = KeyRequirement(
    type: KeyType.none,
    label: '不需金鑰',
  );

  factory KeyRequirement.fromJson(Map<String, dynamic> json) {
    return KeyRequirement(
      type: KeyType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => KeyType.apiKey,
      ),
      label: json['label'] ?? '',
      hint: json['hint'],
      getUrl: json['getUrl'],
      storageKey: json['storageKey'],
      validatorPattern: json['validatorPattern'],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'label': label,
    if (hint != null) 'hint': hint,
    if (getUrl != null) 'getUrl': getUrl,
    if (storageKey != null) 'storageKey': storageKey,
    if (validatorPattern != null) 'validatorPattern': validatorPattern,
  };
}

/// 計價資訊
class PricingInfo {
  final String type;    // 'per_token', 'per_image', 'per_second', 'per_song', 'flat'
  final String example; // 人類可讀的價格範例

  const PricingInfo({required this.type, required this.example});

  factory PricingInfo.fromJson(Map<String, dynamic> json) {
    return PricingInfo(
      type: json['type'] ?? '',
      example: json['example'] ?? '',
    );
  }
}

/// 一個服務支援的模型
class ServiceModel {
  final String id;
  final String? displayName;
  final bool isDefault;

  const ServiceModel({
    required this.id,
    this.displayName,
    this.isDefault = false,
  });

  String get label => displayName ?? id;
}

/// 一個可用的服務提供者（如 OpenAI 的 gpt-image-1.5）
///
/// 這是 ServiceRegistry 的核心資料結構。
/// 每個 ServiceDefinition 描述：
/// - 它屬於哪個能力
/// - 需要什麼鑰匙
/// - 支援哪些模型
/// - 計價方式
/// - 是否為內建或社群提供
class ServiceDefinition {
  final String id;
  final CapabilityId capability;
  final String providerName;    // "OpenAI"
  final String serviceName;     // "GPT 系列" 或 "gpt-image / DALL-E"
  final String? description;
  final KeyRequirement keyRequirement;
  final String? defaultBaseUrl;
  final List<ServiceModel> models;
  final PricingInfo? pricing;
  final bool isBuiltIn;
  final ServiceStatus status;
  final String? deprecationNotice;
  final String? alternativeServiceId; // 下架時的替代服務
  final String? note; // 額外說明（如「跟 OpenAI LLM 共用同一把 Key」）

  const ServiceDefinition({
    required this.id,
    required this.capability,
    required this.providerName,
    required this.serviceName,
    this.description,
    required this.keyRequirement,
    this.defaultBaseUrl,
    required this.models,
    this.pricing,
    this.isBuiltIn = true,
    this.status = ServiceStatus.active,
    this.deprecationNotice,
    this.alternativeServiceId,
    this.note,
  });

  /// 預設模型（isDefault=true 的那個，或第一個）
  ServiceModel? get defaultModel {
    for (final m in models) {
      if (m.isDefault) return m;
    }
    return models.isNotEmpty ? models.first : null;
  }

  /// 與另一個服務共用同一把 Key（storageKey 相同且不為 null）
  bool sharesKeyWith(ServiceDefinition other) {
    final myKey = keyRequirement.storageKey;
    final otherKey = other.keyRequirement.storageKey;
    if (myKey == null || otherKey == null) return false;
    if (keyRequirement.type == KeyType.none || other.keyRequirement.type == KeyType.none) return false;
    return myKey == otherKey;
  }

  factory ServiceDefinition.fromJson(Map<String, dynamic> json) {
    return ServiceDefinition(
      id: json['id'],
      capability: CapabilityIdX.fromString(json['capability']) ?? CapabilityId.textReasoning,
      providerName: json['providerName'] ?? '',
      serviceName: json['serviceName'] ?? '',
      description: json['description'],
      keyRequirement: json['keyRequirement'] != null
          ? KeyRequirement.fromJson(json['keyRequirement'])
          : KeyRequirement.none,
      defaultBaseUrl: json['defaultBaseUrl'],
      models: (json['models'] as List<dynamic>? ?? [])
          .map((m) {
            if (m is String) {
              return ServiceModel(id: m);
            }
            return ServiceModel(
              id: m['id'],
              displayName: m['displayName'],
              isDefault: m['isDefault'] ?? false,
            );
          })
          .toList(),
      pricing: json['pricing'] != null ? PricingInfo.fromJson(json['pricing']) : null,
      isBuiltIn: json['isBuiltIn'] ?? true,
      status: ServiceStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ServiceStatus.active,
      ),
      deprecationNotice: json['deprecationNotice'],
      alternativeServiceId: json['alternativeServiceId'],
      note: json['note'],
    );
  }
}

/// 一個能力 + 其下所有已註冊的服務
class CapabilityGroup {
  final CapabilityId capability;
  final List<ServiceDefinition> services;

  const CapabilityGroup({
    required this.capability,
    required this.services,
  });

  /// 這個能力是否已開通（至少一個服務有有效 Key 或不需要 Key）
  bool get isActivated => services.any((s) =>
      s.keyRequirement.type == KeyType.none || s.keyRequirement.storageKey != null);

  /// 已開通的服務
  List<ServiceDefinition> get activatedServices =>
      services.where((s) => s.keyRequirement.type == KeyType.none || s.keyRequirement.storageKey != null).toList();

  /// 未開通的服務
  List<ServiceDefinition> get inactiveServices =>
      services.where((s) =>
          s.keyRequirement.type != KeyType.none && s.keyRequirement.storageKey == null).toList();
}
