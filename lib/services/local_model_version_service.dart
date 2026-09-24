// local_model_version_service.dart
// 追蹤 llama.cpp 和模型的最新版本，提醒使用者更新。
// 橋樑精神：最新、最開源、最去中心化、最自由。

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// llama.cpp GitHub release 資訊
class LlamaCppRelease {
  final String tag;       // e.g. "b10069"
  final String publishedAt; // ISO 8601
  final String htmlUrl;
  final String body;      // release notes

  const LlamaCppRelease({
    required this.tag,
    required this.publishedAt,
    required this.htmlUrl,
    required this.body,
  });

  factory LlamaCppRelease.fromJson(Map<String, dynamic> json) {
    return LlamaCppRelease(
      tag: json['tag_name'] ?? '',
      publishedAt: json['published_at'] ?? '',
      htmlUrl: json['html_url'] ?? '',
      body: json['body'] ?? '',
    );
  }

  /// 從 release notes 中擷取 Qwen3.5 相關更新
  bool get hasQwenUpdate {
    final lower = body.toLowerCase();
    return lower.contains('qwen3.5') ||
           lower.contains('qwen35') ||
           lower.contains('qwen3-5');
  }

  /// 從 release notes 中擷取視覺/多模態相關更新
  bool get hasVisionUpdate {
    final lower = body.toLowerCase();
    return lower.contains('vision') ||
           lower.contains('multimodal') ||
           lower.contains('mmproj') ||
           lower.contains('mtmd');
  }
}

/// 模型版本資訊（HuggingFace）
class ModelVersionInfo {
  final String repoId;
  final String lastModified; // ISO 8601
  final int downloads;
  final int likes;

  const ModelVersionInfo({
    required this.repoId,
    required this.lastModified,
    required this.downloads,
    required this.likes,
  });

  factory ModelVersionInfo.fromJson(String repoId, Map<String, dynamic> json) {
    return ModelVersionInfo(
      repoId: repoId,
      lastModified: json['lastModified'] ?? json['createdAt'] ?? '',
      downloads: json['downloads'] ?? 0,
      likes: json['likes'] ?? 0,
    );
  }
}

/// 版本更新檢查結果
class VersionCheckResult {
  final LlamaCppRelease? latestLlamaCpp;
  final String? currentLlamaCppTag;
  final bool llamaCppUpdateAvailable;
  final String? llamaCppUpdateSummary;
  final List<String> notableChanges; // 關鍵變更摘要（給使用者看）

  const VersionCheckResult({
    required this.latestLlamaCpp,
    required this.currentLlamaCppTag,
    required this.llamaCppUpdateAvailable,
    required this.llamaCppUpdateSummary,
    required this.notableChanges,
  });
}

/// 版本追蹤服務 — 定期檢查 llama.cpp GitHub releases 和模型更新。
///
/// 使用方式：
/// 1. App 啟動時呼叫 [checkForUpdates]
/// 2. 若有更新，透過 [VersionCheckResult.notableChanges] 顯示通知
/// 3. 使用者確認後觸發更新流程
class LocalModelVersionService {
  static const _ghApi = 'https://api.github.com/repos/ggml-org/llama.cpp';
  static const _hfApi = 'https://huggingface.co/api/models';
  static const _prefsKeyLlamaCpp = 'local_llama_cpp_version';
  static const _prefsKeyLastCheck = 'local_version_last_check';

  final Dio _dio;

  LocalModelVersionService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));

  /// 檢查 llama.cpp 和模型的更新。
  ///
  /// [currentModelRepoId] — 當前安裝的模型 repo ID（用於檢查模型更新）
  /// [forceCheck] — 是否強制檢查（忽略快取）
  Future<VersionCheckResult> checkForUpdates({
    String? currentModelRepoId,
    bool forceCheck = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // 快取：非強制模式下，24 小時內不重複檢查
    if (!forceCheck) {
      final lastCheck = prefs.getString(_prefsKeyLastCheck);
      if (lastCheck != null) {
        final last = DateTime.tryParse(lastCheck);
        if (last != null &&
            DateTime.now().difference(last) < const Duration(hours: 24)) {
          // 使用快取結果
          final cachedTag = prefs.getString(_prefsKeyLlamaCpp) ?? '';
          return VersionCheckResult(
            latestLlamaCpp: null,
            currentLlamaCppTag: cachedTag,
            llamaCppUpdateAvailable: false,
            llamaCppUpdateSummary: '近期已檢查過，無新版本。',
            notableChanges: [],
          );
        }
      }
    }

    // 1. 查 llama.cpp 最新 release
    LlamaCppRelease? latestRelease;
    try {
      final response = await _dio.get('$_ghApi/releases/latest');
      if (response.statusCode == 200) {
        latestRelease = LlamaCppRelease.fromJson(response.data);
      }
    } catch (_) {
      // 網路失敗不阻斷
    }

    // 2. 比對當前版本
    final currentTag = prefs.getString(_prefsKeyLlamaCpp) ?? '';
    bool updateAvailable = false;
    String updateSummary = '';
    final changes = <String>[];

    if (latestRelease != null) {
      if (currentTag.isEmpty || _isNewerTag(latestRelease.tag, currentTag)) {
        updateAvailable = true;
        updateSummary = 'llama.cpp ${latestRelease.tag} 已發布'
            '${currentTag.isEmpty ? '' : '（目前 $currentTag）'}。';

        // 擷取值得提醒使用者的變更
        if (latestRelease.hasQwenUpdate) {
          changes.add('🔑 Qwen3.5 相容性改善 — 建議更新以獲得最佳本地模型體驗');
        }
        if (latestRelease.hasVisionUpdate) {
          changes.add('👁️ 視覺/多模態功能更新 — 視覺識別可能已可用，更新後可嘗試開啟');
        }
        // 擷取 release notes 前 5 行作為摘要
        final noteLines = latestRelease.body
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .take(5)
            .toList();
        changes.addAll(noteLines);
      }

      // 更新最後檢查時間
      await prefs.setString(_prefsKeyLastCheck, DateTime.now().toIso8601String());
    }

    return VersionCheckResult(
      latestLlamaCpp: latestRelease,
      currentLlamaCppTag: currentTag,
      llamaCppUpdateAvailable: updateAvailable,
      llamaCppUpdateSummary: updateSummary,
      notableChanges: changes,
    );
  }

  /// 記錄當前安裝的 llama.cpp 版本（安裝/更新後呼叫）
  Future<void> recordLlamaCppVersion(String tag) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyLlamaCpp, tag);
  }

  /// 查詢 HuggingFace 上模型的最新資訊（下載量、更新時間）
  Future<ModelVersionInfo?> checkModelVersion(String repoId) async {
    try {
      final response = await _dio.get('$_hfApi/$repoId');
      if (response.statusCode == 200) {
        return ModelVersionInfo.fromJson(repoId, response.data);
      }
    } catch (_) {}
    return null;
  }

  /// 比較 llama.cpp 版本標籤（如 b10069 > b9123）
  bool _isNewerTag(String latest, String current) {
    // 格式：b<數字>
    final latestNum = int.tryParse(latest.replaceAll(RegExp(r'[^0-9]'), ''));
    final currentNum = int.tryParse(current.replaceAll(RegExp(r'[^0-9]'), ''));
    if (latestNum != null && currentNum != null) {
      return latestNum > currentNum;
    }
    // 無法比較時，標籤不同就視為有更新
    return latest != current;
  }

  /// 搜尋 HuggingFace 上可用的替代模型（未來讓使用者自由下載）
  ///
  /// [query] — 搜尋關鍵字（如 "qwen3.5 uncensored"）
  /// [maxResults] — 最多回傳數量
  Future<List<ModelVersionInfo>> searchAvailableModels({
    required String query,
    int maxResults = 10,
  }) async {
    try {
      final response = await _dio.get(
        _hfApi,
        queryParameters: {
          'search': query,
          'filter': 'gguf',
          'sort': 'downloads',
          'direction': '-1',
          'limit': maxResults,
        },
      );
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((m) => ModelVersionInfo.fromJson(
                  m['id'] ?? '',
                  m as Map<String, dynamic>,
                ))
            .where((m) => m.repoId.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }
}
