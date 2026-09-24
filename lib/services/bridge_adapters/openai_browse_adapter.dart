import 'dart:async';

import 'package:dio/dio.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class OpenAiBrowseAdapter extends BridgeActionAdapter {
  OpenAiBrowseAdapter({
    Dio? dio,
    Duration timeout = const Duration(seconds: 45),
  }) : _dio = dio ?? Dio(),
       _timeout = timeout;

  final Dio _dio;
  final Duration _timeout;

  @override
  String get id => 'openai';

  @override
  String get displayName => 'OpenAI 網頁搜尋';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.browse};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    final token = await StorageService.getToken(provider: id);
    if (token == null || token.trim().isEmpty) {
      return BridgeActionResult.needsProvider(
        action,
        'OpenAI API Token 尚未設定，無法執行新聞與網頁搜尋',
        provider: id,
      );
    }

    // [以利沙修正 2026-06-24] gpt-5.5 不支援 web_search，改為 gpt-4o 避免 API 靜默失敗
    final model = action.model?.trim().isNotEmpty == true
        ? action.model!.trim()
        : 'gpt-4o';

    try {
      final query = action.prompt.trim();
      final timeSensitive = _isTimeSensitiveQuery(query);
      final response = await _dio
          .post(
            'https://api.openai.com/v1/responses',
            options: Options(
              sendTimeout: _timeout,
              receiveTimeout: _timeout,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            ),
            data: {
              'model': model,
              'tools': [
                {
                  'type': 'web_search',
                  'search_context_size': _searchContextSize(query),
                },
              ],
              'tool_choice': 'required',
              'input': _prompt(action),
            },
          )
          .timeout(_timeout);

      final output = _extractOutputText(response.data);
      final sources = _extractSearchSources(response.data);
      final searchQueries = _extractSearchQueries(response.data);
      final fetchedAt = DateTime.now().toIso8601String();
      final sourceHealth = sources.isEmpty
          ? 'sources_missing'
          : 'sources_available';
      final sourceWarning = sources.isEmpty
          ? '這次搜尋沒有取得可點來源；建議換關鍵字、指定網站，或稍後重試。'
          : null;
      if (output == null || output.trim().isEmpty) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: '網頁搜尋完成，但服務沒有回傳可讀文字。',
          metadata: {
            'type': action.type.legacyType,
            'provider': id,
            'adapter': displayName,
            'model': model,
            'query': query,
            'searchQueries': searchQueries,
            'fetchedAt': fetchedAt,
            'timeSensitive': timeSensitive,
            'searchSources': sources,
            'sourceCount': sources.length,
            'sourceHealth': sourceHealth,
            ..._sourceWarningMetadata(sourceWarning),
          },
        );
      }

      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: _formatOutputForChat(output),
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
          'kind': 'web_search',
          'model': model,
          'query': query,
          'searchQueries': searchQueries,
          'fetchedAt': fetchedAt,
          'timeSensitive': timeSensitive,
          'searchSources': sources,
          'sourceCount': sources.length,
          'sourceHealth': sourceHealth,
          ..._sourceWarningMetadata(sourceWarning),
        },
      );
    } on TimeoutException {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message:
            '網頁搜尋逾時：搜尋服務沒有在 ${_timeout.inSeconds} 秒內回應。請稍後重試，或把問題改成更精準的關鍵字。',
        metadata: {
          'type': action.type.legacyType,
          'kind': 'web_search',
          'provider': id,
          'adapter': displayName,
          'query': action.prompt.trim(),
          'sourceHealth': 'timeout',
          'sourceWarning': '搜尋服務逾時，這次沒有取得來源。',
        },
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['error']?['message'] ?? e.message)
          : e.message;
      final status = _isProviderSetupError(detail?.toString())
          ? BridgeActionStatus.needsProvider
          : BridgeActionStatus.unsupported;
      return BridgeActionResult(
        status: status,
        message: '網頁搜尋失敗：$detail',
        metadata: {
          'type': action.type.legacyType,
          'kind': status == BridgeActionStatus.needsProvider
              ? 'capability_gap'
              : 'web_search',
          'provider': id,
          'adapter': displayName,
          'query': action.prompt.trim(),
          'setupRoute': '/golden-keys?returnTo=/chat',
        },
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '網頁搜尋失敗：$e',
        metadata: {
          'type': action.type.legacyType,
          'kind': 'web_search',
          'provider': id,
          'adapter': displayName,
          'query': action.prompt.trim(),
        },
      );
    }
  }

  String _prompt(BridgeAction action) {
    final request = action.prompt.trim().isEmpty
        ? '請搜尋目前重要新聞並整理重點。'
        : action.prompt.trim();
    return [
      '你是橋樑 APP 的新聞與網頁搜尋橋。',
      '請務必使用網頁搜尋取得最新資料，再用繁體中文回答。',
      '請把聊天回答寫成給一般使用者看的整理，不要輸出工程筆記。',
      '不要使用 Markdown 標題、粗體符號或原始 URL；來源連結會由下方「搜尋證據卡」呈現。',
      '不要另外輸出來源清單；把來源交給搜尋證據卡，聊天回答只保留結論、重點與下一步。',
      '每個重點請一行一點，最多 5 點，不要把多個來源或網址塞在句尾。',
      '請用清楚短段落回答，固定包含：',
      '搜尋摘要：一句話說明查到什麼。',
      '關鍵重點：3 到 5 點，避免塞入過長清單。',
      '下一步：如果還缺使用者指定條件，請明確問一個最重要的問題。',
      '時間提醒：如果是新聞、時刻表、價格、天氣或今日資訊，說明資料可能會變動。',
      '如果資料不確定、互相矛盾或搜尋不到可靠來源，請明確說明不確定處。',
      '如果是火車、公車、航班、價格、天氣、今日新聞等時間敏感任務，請優先搜尋官方或高可信來源。',
      '如果使用者只問某站時刻表，但沒有指定目的地、方向或時間範圍，不要列出大量班次；請先說明已找到官方站點資訊，然後請使用者補充目的地或方向。',
      '使用者請求：$request',
    ].join('\n');
  }

  String _formatOutputForChat(String text) {
    final value = _cleanSearchMarkup(text);
    final lines = value
        .split('\n')
        .map(_cleanSearchLine)
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';

    final output = <String>[];
    String? currentSection;
    var keyPointCount = 0;
    var skippingSources = false;

    void addBlankBeforeSection() {
      if (output.isNotEmpty && output.last.isNotEmpty) output.add('');
    }

    for (final line in lines) {
      final section = _searchSectionLabel(line);
      if (section != null) {
        skippingSources = section == _sourceSectionLabel;
        if (skippingSources) continue;
        currentSection = section;
        if (section == '關鍵重點') keyPointCount = 0;
        addBlankBeforeSection();
        output.add(section);
        continue;
      }

      if (skippingSources) {
        if (_looksLikeSourceLine(line)) continue;
        skippingSources = false;
      }

      var cleanLine = line;
      if (currentSection == '關鍵重點' && cleanLine.startsWith('• ')) {
        keyPointCount += 1;
        if (keyPointCount > 5) continue;
      }
      cleanLine = _shortenSearchLine(cleanLine);
      if (cleanLine.isNotEmpty) output.add(cleanLine);
    }

    return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static const String _sourceSectionLabel = '來源';

  String _cleanSearchMarkup(String text) {
    var value = text.trim();
    value = value.replaceAll('**', '');
    value = value.replaceAll('__', '');
    value = value.replaceAllMapped(
      RegExp(r'\(\s*\[([^\]]+)\]\(https?:\/\/[^)\s]+\)\s*\)'),
      (match) => match.group(1) ?? '',
    );
    value = value.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(https?:\/\/[^)\s]+\)'),
      (match) => match.group(1) ?? '',
    );
    value = value.replaceAll(RegExp(r'\(\s*https?:\/\/[^)]+\)'), '');
    value = value.replaceAll(RegExp(r'https?:\/\/\S+'), '');
    value = value.replaceAll(RegExp(r'【[^】]*】'), '');
    value = value.replaceAll(
      RegExp(r'\(\s*[A-Za-z0-9.-]+\.[A-Za-z]{2,}[^)]*\)'),
      '',
    );
    value = value.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
    value = value.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    value = value.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return value.trim();
  }

  String _cleanSearchLine(String raw) {
    var line = raw.trim();
    line = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    line = line.replaceFirst(RegExp(r'^\s*\d+[.)、]\s*'), '');
    line = line.replaceFirst(RegExp(r'^\s*[#]+\s*\d+[.)、]?\s*'), '');
    line = line.replaceAll(RegExp(r'\s+'), ' ');
    line = line.replaceAllMapped(
      RegExp(r'\s+([：:，,。])'),
      (match) => match.group(1) ?? '',
    );
    return line.trim();
  }

  String? _searchSectionLabel(String line) {
    final normalized = line
        .replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '')
        .replaceFirst(RegExp(r'^\s*\d+[.)、]\s*'), '')
        .replaceAll(RegExp(r'[：:]\s*$'), '')
        .trim();
    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    if (compact == '搜尋摘要' || compact == '摘要') return '搜尋摘要';
    if (compact == '關鍵重點' || compact == '重點' || compact == '主要資訊') {
      return '關鍵重點';
    }
    if (compact == '下一步' || compact == '建議' || compact == '需要補充') {
      return '下一步';
    }
    if (compact == '時間提醒' || compact == '時間敏感提醒') return '時間提醒';
    if (compact == '可追查來源' ||
        compact == '資料來源' ||
        compact == '參考來源' ||
        compact == '來源') {
      return _sourceSectionLabel;
    }
    return null;
  }

  bool _looksLikeSourceLine(String line) {
    final normalized = line.toLowerCase();
    return line.startsWith('•') ||
        normalized.contains('.gov') ||
        normalized.contains('.com') ||
        normalized.contains('.org') ||
        normalized.contains('官方') ||
        normalized.contains('來源') ||
        normalized.contains('查詢');
  }

  String _shortenSearchLine(String line) {
    if (line.length <= 260) return line;
    final parts = line
        .split('。')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final shortened = '${parts.take(2).join('。')}。';
      if (shortened.length <= 260) return shortened;
    }
    return '${line.substring(0, 240).trim()}…';
  }

  String? _extractOutputText(Object? data) {
    if (data is! Map) return null;
    final directText = data['output_text']?.toString();
    if (directText != null && directText.trim().isNotEmpty) {
      return directText;
    }
    final output = data['output'];
    if (output is! List) return null;
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map) continue;
        final text = part['text']?.toString();
        if (text != null && text.trim().isNotEmpty) {
          if (buffer.isNotEmpty) buffer.write('\n');
          buffer.write(text.trim());
        }
      }
    }
    final value = buffer.toString().trim();
    return value.isEmpty ? null : value;
  }

  List<Map<String, String>> _extractSearchSources(Object? data) {
    if (data is! Map) return const [];
    final output = data['output'];
    if (output is! List) return const [];
    final sources = <Map<String, String>>[];
    final seen = <String>{};

    void addSource({String? title, String? url, String? source}) {
      final cleanUrl = url?.trim();
      final cleanTitle = title?.trim();
      final cleanSource = source?.trim();
      if ((cleanUrl == null || cleanUrl.isEmpty) &&
          (cleanTitle == null || cleanTitle.isEmpty) &&
          (cleanSource == null || cleanSource.isEmpty)) {
        return;
      }
      final key = cleanUrl?.isNotEmpty == true
          ? cleanUrl!
          : '${cleanTitle ?? ''}|${cleanSource ?? ''}';
      if (!seen.add(key)) return;
      sources.add({
        if (cleanTitle != null && cleanTitle.isNotEmpty) 'title': cleanTitle,
        if (cleanUrl != null && cleanUrl.isNotEmpty) 'url': cleanUrl,
        if (cleanSource != null && cleanSource.isNotEmpty)
          'source': cleanSource,
      });
    }

    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map) continue;
        final annotations = part['annotations'];
        if (annotations is! List) continue;
        for (final annotation in annotations) {
          if (annotation is! Map) continue;
          final annotationType = annotation['type']?.toString();
          final url = annotation['url']?.toString();
          final title =
              annotation['title']?.toString() ??
              annotation['site_title']?.toString() ??
              annotation['text']?.toString();
          if (annotationType == null ||
              annotationType.contains('citation') ||
              url != null) {
            addSource(title: title, url: url, source: annotationType);
          }
        }
      }
    }

    return sources.take(8).toList();
  }

  List<String> _extractSearchQueries(Object? data) {
    if (data is! Map) return const [];
    final output = data['output'];
    if (output is! List) return const [];
    final queries = <String>[];
    final seen = <String>{};
    for (final item in output) {
      if (item is! Map) continue;
      final type = item['type']?.toString();
      if (type != 'web_search_call') continue;
      final action = item['action'];
      if (action is! Map) continue;
      final query = action['query']?.toString().trim();
      if (query == null || query.isEmpty) continue;
      if (seen.add(query)) queries.add(query);
    }
    return queries;
  }

  Map<String, String> _sourceWarningMetadata(String? sourceWarning) {
    if (sourceWarning == null || sourceWarning.trim().isEmpty) {
      return const {};
    }
    return {'sourceWarning': sourceWarning.trim()};
  }

  bool _isTimeSensitiveQuery(String query) {
    final normalized = query.toLowerCase();
    return [
      '今天',
      '今日',
      '現在',
      '最新',
      '新聞',
      '時刻表',
      '班次',
      '價格',
      '天氣',
      'today',
      'latest',
      'news',
      'schedule',
      'price',
      'weather',
    ].any(normalized.contains);
  }

  String _searchContextSize(String query) {
    final normalized = query.toLowerCase();
    if ([
      '比較',
      '整理',
      '推薦',
      '分析',
      '來源',
      '證據',
      'compare',
      'analysis',
    ].any(normalized.contains)) {
      return 'medium';
    }
    if (_isTimeSensitiveQuery(query)) return 'medium';
    return 'low';
  }

  bool _isProviderSetupError(String? detail) {
    if (detail == null) return false;
    final normalized = detail.toLowerCase();
    return [
      'api key',
      'unauthorized',
      'permission',
      'not enabled',
      'not available',
      'unsupported tool',
      'web_search',
      'tool',
      'billing',
      'quota',
    ].any(normalized.contains);
  }
}
