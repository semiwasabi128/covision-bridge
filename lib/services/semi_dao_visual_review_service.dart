import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/companion.dart';
import 'openai_visual_review_adapter.dart';

enum SemiDaoVisualReviewSignal { approved, watching, blocked }
class SemiDaoVisualReviewResult {
  final SemiDaoVisualReviewSignal signal;
  final List<String> passedChecks;
  final List<String> warningChecks;
  final List<String> blockedChecks;
  // 資訊性提示：不影響燈號（例如「裝了 OpenAI Key 可做更完整的內容審查」）。
  final List<String> infoNotes;
  // 內容深度審查（Vision/moderation）是否真的有跑。false 代表只做了本地圖片品質檢查。
  final bool deepContentReviewRan;
  final int inspectedImageCount;
  final String reviewer;
  final DateTime reviewedAt;

  const SemiDaoVisualReviewResult({
    required this.signal,
    required this.passedChecks,
    required this.warningChecks,
    required this.blockedChecks,
    this.infoNotes = const [],
    this.deepContentReviewRan = false,
    required this.inspectedImageCount,
    required this.reviewer,
    required this.reviewedAt,
  });

  static SemiDaoVisualReviewResult empty() {
    return SemiDaoVisualReviewResult(
      signal: SemiDaoVisualReviewSignal.watching,
      passedChecks: const [],
      warningChecks: const ['尚未完成圖片安全與品質審查。'],
      blockedChecks: const [],
      inspectedImageCount: 0,
      reviewer: 'none',
      reviewedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'signal': signal.name,
    'passedChecks': passedChecks,
    'warningChecks': warningChecks,
    'blockedChecks': blockedChecks,
    'infoNotes': infoNotes,
    'deepContentReviewRan': deepContentReviewRan,
    'inspectedImageCount': inspectedImageCount,
    'reviewer': reviewer,
    'reviewedAt': reviewedAt.toIso8601String(),
  };

  factory SemiDaoVisualReviewResult.fromJson(Map<String, dynamic> json) {
    return SemiDaoVisualReviewResult(
      signal: SemiDaoVisualReviewSignal.values.firstWhere(
        (value) => value.name == json['signal'],
        orElse: () => SemiDaoVisualReviewSignal.watching,
      ),
      passedChecks: _stringList(json['passedChecks']),
      warningChecks: _stringList(json['warningChecks']),
      blockedChecks: _stringList(json['blockedChecks']),
      infoNotes: _stringList(json['infoNotes']),
      deepContentReviewRan: json['deepContentReviewRan'] == true,
      inspectedImageCount: (json['inspectedImageCount'] as num?)?.round() ?? 0,
      reviewer: '${json['reviewer'] ?? 'unknown'}',
      reviewedAt:
          DateTime.tryParse('${json['reviewedAt'] ?? ''}') ?? DateTime.now(),
    );
  }
}

/// [教練 Agent 2026-06-28] 全網支援 Vision（圖片理解）的模型清單
/// 用於審查失敗時告知使用者有哪些選擇
const _visionModelGuide = '''
🔍 全網支援圖片審查（Vision）的 API：

1. OpenAI — GPT-4o / GPT-4o-mini
   取得：https://platform.openai.com/api-keys
   優點：最穩定、辨識精準、支援多圖

2. Google Gemini — Gemini-1.5-Flash / Pro
   取得：https://aistudio.google.com/apikey
   優點：免費額度大、速度快

3. 智譜 GLM — GLM-4V-Flash
   取得：https://open.bigmodel.cn/
   優點：中文理解佳、國內直連

4. Anthropic Claude — Claude-3-Haiku
   取得：https://console.anthropic.com/
   優點：判斷細膩、安全審查強

⚠️ 不支援圖片審查的：
   Kimi (純文字) / 本地模型 (除非裝 LLaVA)

設定方式：到 App 設定頁 → 選擇 Provider → 填入對應的 API Key 和 Gateway URL''';

class SemiDaoVisualReviewService {
  final OpenAiVisualReviewAdapter? openAiAdapter;

  const SemiDaoVisualReviewService({this.openAiAdapter});

  Future<SemiDaoVisualReviewResult> reviewCompanionImages(
    Companion companion,
  ) async {
    final passed = <String>[];
    final warnings = <String>[];
    final blocked = <String>[];
    final refs = _imageRefs(companion);
    var inspected = 0;

    if (refs.isEmpty) {
      warnings.add('沒有可檢查的主形象或狀態圖。');
    }

    for (final ref in refs) {
      final inspection = await _inspectImage(ref);
      if (inspection == null) {
        warnings.add('${ref.label} 無法讀取，圖片審查未完成。');
        continue;
      }
      inspected += 1;
      if (!inspection.isSupportedRaster) {
        warnings.add('${ref.label} 格式尚未完整支援：${inspection.mimeType}。');
        continue;
      }
      if (inspection.width < 256 || inspection.height < 256) {
        warnings.add(
          '${ref.label} 解析度偏低：${inspection.width}x${inspection.height}，建議重新生成較清楚的圖。',
        );
      }
      final ratio = inspection.width / inspection.height;
      // [教練 Agent 2026-08-14] 放寬長寬比閾值 + 修正 typo「過端」→「過度偏斜」
      // 舊閾值 0.42/2.4 太嚴格，正常的 2:3 直式人像（ratio≈0.67）不該觸發
      // 新閾值只擋極端比例（< 0.3 或 > 3.5）
      if (ratio < 0.3 || ratio > 3.5) {
        warnings.add('${ref.label} 長寬比例過度偏斜，可能影響社群卡片展示。');
      }
    }

    if (inspected > 0) {
      passed.add('已完成 $inspected 張圖片的可讀性與基本品質檢查。');
      passed.add('未在本地檢查中發現破圖或無法解析的主要圖片。');
    }

    if (companion.stateAnimationPaths.isNotEmpty) {
      warnings.add('動圖首幀 Vision 審查尚未接入，已先保留為待檢項。');
    }

    // [教練 Agent 2026-06-28] 改用 VisionReviewOutcome，取得明確失敗原因
    final outcome = await _runVisionReview(companion);
    final infoNotes = <String>[];
    var deepContentReviewRan = false;
    var reviewer = 'bridge.local-image-preflight.v0.1';

    if (outcome != null && outcome.isSuccess) {
      // --- 審查成功 ---
      final vision = outcome.result!;
      deepContentReviewRan = true;
      reviewer = 'vision-api.${outcome.providerUsed}.${outcome.modelUsed}';

      if (vision.adultContent) {
        blocked.add('偵測到疑似成人、裸露或性暗示內容（無法分享至社群，仍可自用）。');
      } else {
        passed.add('未偵測到成人、裸露或性暗示內容。');
      }
      if (vision.violenceOrHate) {
        blocked.add('偵測到疑似暴力、仇恨或危險符號（無法分享至社群，仍可自用）。');
      } else {
        passed.add('未偵測到暴力或仇恨符號。');
      }
      if (vision.officialConfusion || vision.logoOrTrademark) {
        blocked.add('偵測到疑似 Logo、商標或官方混淆風險（無法分享至社群，仍可自用）。');
      } else {
        passed.add('未偵測到明顯 Logo、商標或官方混淆。');
      }
      if (vision.identifiableIpRisk) {
        warnings.add('偵測到可能近似既有 IP 或知名角色，建議自行確認原創性。');
      } else {
        passed.add('未偵測到明顯可識別的既有 IP。');
      }
      if (vision.qualityScore < 2) {
        warnings.add('圖片可能嚴重破圖或難以辨識（品質 ${vision.qualityScore}/5），建議重新生成。');
      } else {
        passed.add('未偵測到嚴重破圖或難以辨識的圖片。');
      }
      for (final issue in vision.qualityIssues.take(3)) {
        infoNotes.add('觀察：$issue');
      }
      if (vision.notes.trim().isNotEmpty) {
        infoNotes.add('備註：${vision.notes.trim()}');
      }
    } else if (outcome != null) {
      // --- 審查失敗：根據原因給出明確引導 ---
      final guidance = _buildFailureGuidance(outcome);
      infoNotes.addAll(guidance);
      reviewer = 'bridge.local-image-preflight.v0.1';
    } else {
      // outcome == null（adapter 建構失敗等極端情況）
      infoNotes.add('圖片內容安全審查未能執行。已完成本地基本品質檢查。');
    }

    final signal = blocked.isNotEmpty
        ? SemiDaoVisualReviewSignal.blocked
        : warnings.isEmpty
        ? SemiDaoVisualReviewSignal.approved
        : SemiDaoVisualReviewSignal.watching;

    return SemiDaoVisualReviewResult(
      signal: signal,
      passedChecks: passed,
      warningChecks: warnings,
      blockedChecks: blocked,
      infoNotes: infoNotes,
      deepContentReviewRan: deepContentReviewRan,
      inspectedImageCount: inspected,
      reviewer: reviewer,
      reviewedAt: DateTime.now(),
    );
  }

  /// [教練 Agent 2026-06-28] 根據失敗狀態建立引導訊息
  /// 核心：告知缺什麼 → 列出選項 → 引導取得 → 不強迫
  List<String> _buildFailureGuidance(VisionReviewOutcome outcome) {
    final notes = <String>[];

    switch (outcome.status) {
      case VisionReviewStatus.noToken:
        notes.add('⚠️ 你的 API 尚未設定服務密碼（Token），無法執行圖片內容安全審查。');
        notes.add('目前已完成本地圖片品質檢查（尺寸、可讀性）。');
        notes.add('如需完整審查（成人/暴力/Logo/IP 偵測），請到設定頁填入 API Key。');
        notes.add(_visionModelGuide);
        break;

      case VisionReviewStatus.noGateway:
        notes.add('⚠️ 尚未設定 Gateway URL，無法執行圖片內容安全審查。');
        notes.add('請到設定頁填入你的 API Gateway 地址。');
        notes.add(_visionModelGuide);
        break;

      case VisionReviewStatus.noImages:
        notes.add('⚠️ 這個角色沒有圖片可審查。請先生成主形象圖再進行預審。');
        break;

      case VisionReviewStatus.apiError:
        notes.add('⚠️ 圖片內容安全審查呼叫失敗，可能原因：');
        notes.add('• 你目前的 API 不支援圖片理解（Vision）功能');
        notes.add('• 或模型名稱不符、額度用完等');
        if (outcome.providerUsed != null && outcome.modelUsed != null) {
          notes.add('嘗試的 Provider：${outcome.providerUsed}，模型：${outcome.modelUsed}');
        }
        if (outcome.errorMessage != null) {
          notes.add('API 錯誤訊息：${outcome.errorMessage}');
        }
        notes.add('目前已完成本地圖片品質檢查。你可以：');
        notes.add('1. 換用支援 Vision 的 API（見下方清單）');
        notes.add('2. 或直接分享——你對自己的角色內容負最終責任，本地檢查已通過。');
        notes.add(_visionModelGuide);
        break;

      case VisionReviewStatus.parseError:
        notes.add('⚠️ API 有回應但格式無法解析，可能是模型不支援圖片輸入。');
        notes.add('目前已完成本地圖片品質檢查。');
        if (outcome.errorMessage != null) {
          notes.add('詳情：${outcome.errorMessage}');
        }
        notes.add('建議換用支援 Vision 的模型，或直接分享（本地檢查已通過）。');
        notes.add(_visionModelGuide);
        break;

      case VisionReviewStatus.success:
        // 不會走到這裡
        break;
    }

    return notes;
  }

  Future<VisionReviewOutcome?> _runVisionReview(
    Companion companion,
  ) async {
    final adapter = openAiAdapter ?? OpenAiVisualReviewAdapter();
    try {
      return await adapter.reviewCompanion(companion);
    } catch (_) {
      return null;
    }
  }

  List<_ImageRef> _imageRefs(Companion companion) {
    final refs = <_ImageRef>[];
    final avatar = companion.avatarImagePath?.trim();
    if (avatar != null && avatar.isNotEmpty) {
      refs.add(_ImageRef(label: '主形象圖', value: avatar));
    }
    final entries = companion.stateImagePaths.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries.take(8)) {
      final value = entry.value.trim();
      if (value.isEmpty) continue;
      refs.add(_ImageRef(label: '狀態圖 ${entry.key}', value: value));
    }
    return refs;
  }

  Future<_ImageInspection?> _inspectImage(_ImageRef ref) async {
    final value = ref.value;
    Uint8List bytes;
    String mimeType;
    if (value.startsWith('data:image/')) {
      final comma = value.indexOf(',');
      if (comma == -1) return null;
      final header = value.substring(0, comma).toLowerCase();
      final payload = value.substring(comma + 1);
      mimeType = header.contains('image/jpeg') || header.contains('image/jpg')
          ? 'image/jpeg'
          : header.contains('image/webp')
          ? 'image/webp'
          : 'image/png';
      try {
        bytes = base64Decode(payload);
      } catch (_) {
        return null;
      }
    } else if (value.startsWith('http://') || value.startsWith('https://')) {
      return null;
    } else {
      final file = File(value);
      if (!await file.exists()) return null;
      bytes = await file.readAsBytes();
      mimeType = _mimeFromPath(value);
    }

    final dimensions = _dimensions(bytes, mimeType);
    if (dimensions == null) {
      return _ImageInspection(
        mimeType: mimeType,
        width: 0,
        height: 0,
        isSupportedRaster: false,
      );
    }
    return _ImageInspection(
      mimeType: mimeType,
      width: dimensions.$1,
      height: dimensions.$2,
      isSupportedRaster: true,
    );
  }

  String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/png';
  }

  (int, int)? _dimensions(Uint8List bytes, String mimeType) {
    if (mimeType == 'image/png') return _pngDimensions(bytes);
    if (mimeType == 'image/jpeg') return _jpegDimensions(bytes);
    return null;
  }

  (int, int)? _pngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return null;
    final signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (var i = 0; i < signature.length; i += 1) {
      if (bytes[i] != signature[i]) return null;
    }
    final data = ByteData.sublistView(bytes);
    return (data.getUint32(16), data.getUint32(20));
  }

  (int, int)? _jpegDimensions(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xff || bytes[1] != 0xd8) return null;
    var offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xff) return null;
      final marker = bytes[offset + 1];
      final length = (bytes[offset + 2] << 8) + bytes[offset + 3];
      if (length < 2 || offset + length >= bytes.length) return null;
      if ((marker >= 0xc0 && marker <= 0xc3) ||
          (marker >= 0xc5 && marker <= 0xc7) ||
          (marker >= 0xc9 && marker <= 0xcb) ||
          (marker >= 0xcd && marker <= 0xcf)) {
        final height = (bytes[offset + 5] << 8) + bytes[offset + 6];
        final width = (bytes[offset + 7] << 8) + bytes[offset + 8];
        return (width, height);
      }
      offset += 2 + length;
    }
    return null;
  }
}

class _ImageRef {
  final String label;
  final String value;

  const _ImageRef({required this.label, required this.value});
}

class _ImageInspection {
  final String mimeType;
  final int width;
  final int height;
  final bool isSupportedRaster;

  const _ImageInspection({
    required this.mimeType,
    required this.width,
    required this.height,
    required this.isSupportedRaster,
  });
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [for (final item in value) '$item'];
}
