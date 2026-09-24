import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class OpenAiVisionAdapter extends BridgeActionAdapter {
  OpenAiVisionAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  String get id => 'openai';

  @override
  String get displayName => 'OpenAI 圖片辨識';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.vision};

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    // [以利沙修正 2026-06-24] 使用者只上傳圖片未輸入文字時，不自動分析，改為詢問意圖
    if (action.prompt.trim().isEmpty &&
        action.referenceImagePaths.isNotEmpty) {
      return BridgeActionResult(
        status: BridgeActionStatus.completed,
        message: '收到你的圖片，你想讓我怎麼處理？',
        metadata: const {'waitingForIntent': true},
      );
    }

    final token = await StorageService.getToken(provider: id);
    if (token == null || token.trim().isEmpty) {
      return BridgeActionResult.needsProvider(
        action,
        'OpenAI API Token 尚未設定，無法執行圖片辨識',
        provider: id,
      );
    }

    final imageInputs = await _buildImageInputs(action.referenceImagePaths);
    if (imageInputs.isEmpty) {
      return BridgeActionResult(
        status: BridgeActionStatus.needsProvider,
        message: '請先上傳要辨識的圖片，再讓夥伴分析內容。',
        metadata: {
          'type': action.type.legacyType,
          'provider': id,
          'adapter': displayName,
          'prompt': action.prompt,
        },
      );
    }

    final model = action.model?.trim().isNotEmpty == true
        ? action.model!.trim()
        : 'gpt-5-mini';

    try {
      final response = await _dio.post(
        'https://api.openai.com/v1/responses',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'model': model,
          'input': [
            {
              'role': 'user',
              'content': [
                {'type': 'input_text', 'text': _prompt(action)},
                ...imageInputs,
              ],
            },
          ],
        },
      );

      final output = _extractOutputText(response.data);
      if (output == null || output.trim().isEmpty) {
        return BridgeActionResult(
          status: BridgeActionStatus.unsupported,
          message: '圖片辨識完成，但服務沒有回傳可讀文字。',
          metadata: {
            'type': action.type.legacyType,
            'provider': id,
            'adapter': displayName,
            'model': model,
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
          'kind': 'vision',
          'model': model,
          'prompt': action.prompt,
          'imageCount': imageInputs.length,
          'imageSource': _imageSourceSummary(action.referenceImagePaths),
        },
      );
    } on DioException catch (e) {
      final detail = e.response?.data is Map
          ? (e.response?.data['error']?['message'] ?? e.message)
          : e.message;
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '圖片辨識失敗：$detail',
        metadata: {'type': action.type.legacyType, 'provider': id},
      );
    } catch (e) {
      return BridgeActionResult(
        status: BridgeActionStatus.unsupported,
        message: '圖片辨識失敗：$e',
        metadata: {'type': action.type.legacyType, 'provider': id},
      );
    }
  }

  String _prompt(BridgeAction action) {
    final request = action.prompt.trim().isEmpty
        ? '請描述這張圖片的內容。'
        : action.prompt.trim();
    return [
      '你是橋樑 APP 的 Vision 圖片辨識橋。',
      '請用繁體中文回答使用者，直接描述圖片中可見的內容。',
      '請把回答寫成一般使用者看得懂的整理，不要輸出工程筆記。',
      '不要使用 Markdown 標題、粗體符號或原始 URL。',
      '請固定包含：',
      '圖片摘要：一句話說明這張圖大致是什麼。',
      '重要細節：3 到 5 點，列出畫面中值得注意的元素。',
      '可用線索：說明這張圖可以幫使用者推進什麼判斷或任務。',
      '下一步：如果需要使用者補充目的、放大局部或提供更多圖片，請明確問一個最重要的問題。',
      '如果圖片是截圖，請摘要畫面、文字、可能的操作狀態與值得注意的問題。',
      '如果看不清楚，請誠實說明不確定處，不要編造。',
      '使用者請求：$request',
    ].join('\n');
  }

  String _formatOutputForChat(String text) {
    final value = _cleanVisionMarkup(text);
    final lines = value
        .split('\n')
        .map(_cleanVisionLine)
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';

    final hasSection = lines.any((line) => _visionSectionLabel(line) != null);
    if (!hasSection) {
      return [
        '圖片摘要',
        _shortenVisionLine(lines.first),
        if (lines.length > 1) ...[
          '',
          '重要細節',
          ...lines.skip(1).take(5).map(_asVisionBullet),
        ],
        '',
        '下一步',
        '如果你有特定目的，可以告訴我想看構圖、文字、錯誤訊息、商品資訊，或其他細節。',
      ].join('\n').trim();
    }

    final output = <String>[];
    String? currentSection;
    var detailCount = 0;
    void addBlankBeforeSection() {
      if (output.isNotEmpty && output.last.isNotEmpty) output.add('');
    }

    for (final line in lines) {
      final section = _visionSectionLabel(line);
      if (section != null) {
        currentSection = section;
        if (section == '重要細節') detailCount = 0;
        addBlankBeforeSection();
        output.add(section);
        continue;
      }

      var cleanLine = line;
      if (currentSection == '重要細節' && cleanLine.startsWith('• ')) {
        detailCount += 1;
        if (detailCount > 5) continue;
      }
      cleanLine = _shortenVisionLine(cleanLine);
      if (cleanLine.isNotEmpty) output.add(cleanLine);
    }

    return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  String _cleanVisionMarkup(String text) {
    var value = text.trim();
    value = value.replaceAll('**', '');
    value = value.replaceAll('__', '');
    value = value.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\(https?:\/\/[^)\s]+\)'),
      (match) => match.group(1) ?? '',
    );
    value = value.replaceAll(RegExp(r'\(\s*https?:\/\/[^)]+\)'), '');
    value = value.replaceAll(RegExp(r'https?:\/\/\S+'), '');
    value = value.replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
    value = value.replaceAll(RegExp(r'[ \t]+\n'), '\n');
    value = value.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return value.trim();
  }

  String _cleanVisionLine(String raw) {
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

  String? _visionSectionLabel(String line) {
    final normalized = line
        .replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '')
        .replaceFirst(RegExp(r'^\s*\d+[.)、]\s*'), '')
        .replaceAll(RegExp(r'[：:]\s*$'), '')
        .trim();
    final compact = normalized.replaceAll(RegExp(r'\s+'), '');
    if (compact == '圖片摘要' || compact == '摘要' || compact == '畫面摘要') {
      return '圖片摘要';
    }
    if (compact == '重要細節' || compact == '畫面細節' || compact == '細節') {
      return '重要細節';
    }
    if (compact == '可用線索' || compact == '可用資訊' || compact == '判斷線索') {
      return '可用線索';
    }
    if (compact == '下一步' || compact == '建議' || compact == '需要補充') {
      return '下一步';
    }
    return null;
  }

  String _asVisionBullet(String line) {
    final clean = _shortenVisionLine(line);
    if (clean.startsWith('• ')) return clean;
    return '• $clean';
  }

  String _shortenVisionLine(String line) {
    if (line.length <= 240) return line;
    final parts = line
        .split('。')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final shortened = '${parts.take(2).join('。')}。';
      if (shortened.length <= 240) return shortened;
    }
    return '${line.substring(0, 220).trim()}…';
  }

  String _imageSourceSummary(List<String> references) {
    if (references.isEmpty) return '未附加圖片';
    final localCount = references
        .where(
          (item) =>
              item.trim().isNotEmpty &&
              !item.startsWith('data:image/') &&
              !item.startsWith('http'),
        )
        .length;
    final dataCount = references
        .where((item) => item.startsWith('data:image/'))
        .length;
    final urlCount = references
        .where(
          (item) => item.startsWith('http://') || item.startsWith('https://'),
        )
        .length;
    final parts = <String>[
      if (localCount > 0) '本機圖片 $localCount 張',
      if (dataCount > 0) '上傳圖片 $dataCount 張',
      if (urlCount > 0) '網路圖片 $urlCount 張',
    ];
    return parts.isEmpty ? '${references.length} 張圖片' : parts.join('、');
  }

  Future<List<Map<String, String>>> _buildImageInputs(
    List<String> references,
  ) async {
    final images = <Map<String, String>>[];
    for (final ref in references) {
      final dataUrl = await _asImageUrl(ref.trim());
      if (dataUrl == null || dataUrl.isEmpty) continue;
      images.add({'type': 'input_image', 'image_url': dataUrl});
    }
    return images;
  }

  Future<String?> _asImageUrl(String value) async {
    if (value.isEmpty) return null;
    if (value.startsWith('data:image/')) return value;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (kIsWeb) return null;
    final file = File(value);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return 'data:${_mimeFromPath(value)};base64,${base64Encode(bytes)}';
  }

  String _mimeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/png';
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
}
