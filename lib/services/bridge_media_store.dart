import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'document_type_classifier.dart';
import 'vector_db/media_ingest_hook.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

class BridgeMediaStore {
  static Future<String> persistImageDataUrl(String dataUrl, {String? prompt}) async {
    if (kIsWeb) return dataUrl;

    final commaIndex = dataUrl.indexOf(',');
    final encoded = commaIndex >= 0
        ? dataUrl.substring(commaIndex + 1)
        : dataUrl;
    final bytes = base64Decode(encoded);
    return _writeImageBytes(bytes, prompt: prompt);
  }

  static Future<String> persistImageBytes(Uint8List bytes, {String? prompt}) async {
    if (kIsWeb) {
      return 'data:image/png;base64,${base64Encode(bytes)}';
    }
    return _writeImageBytes(bytes, prompt: prompt);
  }

  static Future<String> persistMarkdownDocument({
    required String title,
    required String content,
    String? documentCategory,
  }) async {
    if (kIsWeb) {
      return 'data:text/markdown;base64,${base64Encode(utf8.encode(content))}';
    }

    return _writeDocumentText(
      title: title,
      extension: 'md',
      content: content,
      documentCategory: documentCategory,
    );
  }

  static Future<String?> documentsDirectoryPath() async {
    return documentDirectoryPath();
  }

  static Future<String?> documentDirectoryPath({String? category}) async {
    if (kIsWeb) return null;
    final documents = await getApplicationDocumentsDirectory();
    final categoryPath = _documentCategoryPath(category);
    final documentDir = Directory(
      categoryPath == null
          ? '${documents.path}/bridge_media/documents'
          : '${documents.path}/bridge_media/documents/$categoryPath',
    );
    if (!await documentDir.exists()) {
      await documentDir.create(recursive: true);
    }
    return documentDir.path;
  }

  static Future<String> persistHtmlDocument({
    required String title,
    required String markdown,
    String? documentCategory,
  }) async {
    final html = _markdownToSimpleHtml(title: title, markdown: markdown);
    if (kIsWeb) {
      return 'data:text/html;base64,${base64Encode(utf8.encode(html))}';
    }
    return _writeDocumentText(
      title: title,
      extension: 'html',
      content: html,
      documentCategory: documentCategory,
    );
  }

  static Future<String> persistPdfDocument({
    required String title,
    required String markdown,
    String? documentCategory,
  }) async {
    final document = pw.Document();
    // [開源整備 2026-09-21] 字型已換 Noto Sans TC；此處載入新檔。
    final fontData =
        await rootBundle.load('assets/fonts/NotoSansTC-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    final regularStyle = pw.TextStyle(font: font, fontSize: 14, height: 1.45);
    final titleStyle = pw.TextStyle(font: font,
      fontSize: 20, fontWeight: pw.FontWeight.bold,);

    document.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(title, style: titleStyle),
          pw.SizedBox(height: 16),
          ..._markdownLinesForPdf(markdown).map(
            (line) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(line, style: regularStyle),
            ),
          ),
        ],
      ),
    );

    final bytes = await document.save();
    if (kIsWeb) {
      return 'data:application/pdf;base64,${base64Encode(bytes)}';
    }
    return _writeDocumentBytes(
      title: title,
      extension: 'pdf',
      bytes: bytes,
      documentCategory: documentCategory,
      ingestContent: markdown,
    );
  }

  static Future<String> readMarkdownDocument(String path) async {
    if (path.startsWith('data:text/markdown')) {
      final commaIndex = path.indexOf(',');
      final encoded = commaIndex >= 0 ? path.substring(commaIndex + 1) : path;
      return utf8.decode(base64Decode(encoded));
    }

    if (kIsWeb) {
      return 'Web 版本無法直接讀取本機檔案路徑。';
    }

    return File(path).readAsString();
  }

  // ── 影片/音訊持久化 ──

  static Future<String> persistVideoBytes(Uint8List bytes, {String? prompt}) async {
    if (kIsWeb) {
      return 'data:video/mp4;base64,${base64Encode(bytes)}';
    }
    return _writeMediaBytes(bytes, subDir: 'videos', extension: 'mp4', prompt: prompt);
  }

  static Future<String> persistAudioBytes(Uint8List bytes, {String extension = 'mp3', String? prompt}) async {
    if (kIsWeb) {
      return 'data:audio/$extension;base64,${base64Encode(bytes)}';
    }
    return _writeMediaBytes(bytes, subDir: 'audio', extension: extension, prompt: prompt);
  }

  static Future<String> _writeMediaBytes(
    Uint8List bytes, {
    required String subDir,
    required String extension,
    String? prompt,
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${documents.path}/bridge_media/$subDir');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${mediaDir.path}/bridge_${subDir}_$timestamp.$extension');
    await file.writeAsBytes(bytes, flush: true);
    // [教練 Agent 2026-08-21] 鐵三角 #8：畫布產出自動入庫（fire-and-forget）
    MediaIngestHook.instance.ingestGeneratedMedia(
      absolutePath: file.path,
      kind: subDir == 'videos' ? 'video' : 'audio',
      prompt: prompt,
    );
    return file.path;
  }

  /// [教練 Agent 2026-08-21] 從 bytes 魔數嗅探圖片實際格式（副檔名）。
  /// Finder 縮圖依副檔名路由——名實不符就 generic 圖示。
  static String sniffImageExtension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 &&
        bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 &&
        bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45) {
      return 'webp';
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x47 && bytes[9] == 0x49 && bytes[10] == 0x46) {
      return 'gif';
    }
    return 'png'; // 預設（與舊行為一致）
  }

  static Future<String> _writeImageBytes(Uint8List bytes, {String? prompt}) async {
    final documents = await getApplicationDocumentsDirectory();
    final mediaDir = Directory('${documents.path}/bridge_media/images');
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // [教練 Agent 2026-08-21] 副檔名必須反映「實際內容」——Finder/QuickLook 縮圖
    // 走副檔名路由：JPEG 內容掛 .png 副檔名會解碼失敗變 generic 圖示
    // （08-08 起 Replicate 等 provider 回傳 JPEG，舊碼硬編 .png 釀 156 張）。
    final ext = BridgeMediaStore.sniffImageExtension(bytes);
    final file = File('${mediaDir.path}/bridge_image_$timestamp.$ext');
    await file.writeAsBytes(bytes, flush: true);
    // [教練 Agent 2026-08-21] 鐵三角 #8：畫布產出自動入庫（fire-and-forget）
    MediaIngestHook.instance.ingestGeneratedMedia(
      absolutePath: file.path,
      kind: 'image',
      prompt: prompt,
    );
    return file.path;
  }

  static Future<String> _writeDocumentText({
    required String title,
    required String extension,
    required String content,
    String? documentCategory,
  }) async {
    return _writeDocumentBytes(
      title: title,
      extension: extension,
      bytes: Uint8List.fromList(utf8.encode(content)),
      documentCategory: documentCategory,
      ingestContent: content,
    );
  }

  static Future<String> _writeDocumentBytes({
    required String title,
    required String extension,
    required List<int> bytes,
    String? documentCategory,
    String? ingestContent, // [教練 Agent 2026-08-21] 入庫用語義內文
  }) async {
    final documents = await getApplicationDocumentsDirectory();
    final categoryPath = _documentCategoryPath(documentCategory);
    final documentDir = Directory(
      categoryPath == null
          ? '${documents.path}/bridge_media/documents'
          : '${documents.path}/bridge_media/documents/$categoryPath',
    );
    if (!await documentDir.exists()) {
      await documentDir.create(recursive: true);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = '${_safeFileName(title)}_$timestamp.$extension';
    final file = File('${documentDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    // [教練 Agent 2026-08-21] 鐵三角 #8：畫布產出自動入庫（fire-and-forget）
    MediaIngestHook.instance.ingestGeneratedMedia(
      absolutePath: file.path,
      kind: 'document',
      title: title,
      contentText: ingestContent,
    );
    return file.path;
  }

  static String _safeFileName(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.isEmpty) return 'bridge_document';
    return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
  }

  static String? _documentCategoryPath(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    // [Phase 2 #18] 使用共用 DocumentTypeClassifier，消除重複代碼
    final result = const DocumentTypeClassifier().classify(value);
    if (result.categoryPath == 'general') return null;
    return result.categoryPath;
  }

  static String _markdownToSimpleHtml({
    required String title,
    required String markdown,
  }) {
    final body = markdown
        .split('\n')
        .map((line) {
          final escaped = htmlEscape.convert(line);
          if (line.startsWith('# ')) {
            return '<h1>${htmlEscape.convert(line.substring(2))}</h1>';
          }
          if (line.startsWith('## ')) {
            return '<h2>${htmlEscape.convert(line.substring(3))}</h2>';
          }
          if (line.startsWith('- ')) {
            return '<p>• ${htmlEscape.convert(line.substring(2))}</p>';
          }
          if (line.trim().isEmpty) return '<br>';
          return '<p>$escaped</p>';
        })
        .join('\n');
    return '''
<!doctype html>
<html lang="zh-Hant">
<head>
  <meta charset="utf-8">
  <title>${htmlEscape.convert(title)}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "PingFang TC", sans-serif; line-height: 1.65; padding: 32px; color: #14213d; }
    h1, h2 { color: #0f766e; }
    p { margin: 0 0 10px; }
  </style>
</head>
<body>
$body
</body>
</html>
''';
  }

  static List<String> _markdownLinesForPdf(String markdown) {
    return markdown
        .split('\n')
        .map(
          (line) => line
              .replaceFirst(RegExp(r'^#{1,6}\s*'), '')
              .replaceFirst(RegExp(r'^-\s*'), '• ')
              .replaceAll('**', '')
              .trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();
  }
}
