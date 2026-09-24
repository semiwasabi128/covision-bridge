import '../../models/bridge_action.dart';
import '../api_service.dart';
import '../bridge_action_executor.dart';
import '../bridge_media_store.dart';
import '../document_type_classifier.dart';
import '../storage_service.dart';
import 'bridge_action_adapter.dart';

class LocalDocumentAdapter extends BridgeActionAdapter {
  @override
  String get id => 'local_document';

  @override
  String get displayName => '本地文件產出橋';

  @override
  Set<BridgeActionType> get supportedTypes => {BridgeActionType.document};

  @override
  bool canHandle(BridgeAction action, String provider) {
    return supportedTypes.contains(action.type);
  }

  @override
  Future<BridgeActionResult> execute(BridgeAction action) async {
    final title = _extractTitle(action.prompt);
    final documentType = _detectDocumentType(action.prompt);
    final provider = await StorageService.getProvider() ?? 'local';
    String? fallbackReason;
    var generationMode = 'provider_generated';
    late final String content;

    try {
      content = await ApiService.generateDocumentMarkdown(action.prompt);
    } catch (error) {
      fallbackReason = error.toString();
      generationMode = 'local_template';
      content = _buildMarkdown(title: title, prompt: action.prompt);
    }

    final markdownPath = await BridgeMediaStore.persistMarkdownDocument(
      title: title,
      content: content,
      documentCategory: documentType,
    );
    final htmlPath = await BridgeMediaStore.persistHtmlDocument(
      title: title,
      markdown: content,
      documentCategory: documentType,
    );
    final pdfPath = await BridgeMediaStore.persistPdfDocument(
      title: title,
      markdown: content,
      documentCategory: documentType,
    );
    final usedLocalTemplate = generationMode == 'local_template';
    final exportPaths = {
      'Markdown': markdownPath,
      'HTML': htmlPath,
      'PDF': pdfPath,
    };

    return BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: usedLocalTemplate
          ? _completionMessage(
              '我先用本地文件模板整理成 Markdown / HTML / PDF 草稿。',
              exportPaths,
            )
          : _completionMessage(
              '已由 $provider 整理成 Markdown / HTML / PDF 草稿。',
              exportPaths,
            ),
      mediaUrl: markdownPath,
      metadata: {
        'type': action.type.legacyType,
        'kind': 'document',
        'provider': usedLocalTemplate ? id : provider,
        'adapter': displayName,
        'generationMode': generationMode,
        'fallbackReason': ?fallbackReason,
        'title': title,
        'documentType': documentType,
        'format': 'Markdown / HTML / PDF',
        'path': markdownPath,
        'exportPaths': exportPaths,
        'workflowActions': _buildWorkflowActions(
          title: title,
          documentType: documentType,
          content: content,
        ),
        'plannedFormats': ['DOCX', 'PPTX'],
        'pluginInterfaces': [
          {
            'label': 'Word / DOCX',
            'status': '插件接口已預留',
            'note': '未來可由社群 adapter 轉成可編輯 Word 文件。',
          },
          {
            'label': '簡報 / PPTX',
            'status': '插件接口已預留',
            'note': '未來可由社群 adapter 轉成簡報檔或投影片模板。',
          },
        ],
      },
    );
  }

  String _completionMessage(String lead, Map<String, String> exportPaths) {
    final lines = [
      '文件已產出。',
      lead,
      '',
      '可開啟檔案：',
      for (final entry in exportPaths.entries) '- ${entry.key}：${entry.value}',
      '',
      '下一步可以請我改寫、補充、轉成正式規格、企劃書或簡報大綱。',
    ];
    return lines.join('\n');
  }

  String _extractTitle(String prompt) {
    final separatorIndex = prompt.indexOf('|');
    final rawTitle = separatorIndex >= 0
        ? prompt.substring(0, separatorIndex)
        : prompt.split(RegExp(r'[\n。.!?]')).first;
    final title = rawTitle.trim();
    return title.isEmpty ? '橋樑文件' : title;
  }

  String _detectDocumentType(String prompt) {
    // [Phase 2 #18] 使用共用 DocumentTypeClassifier，消除重複代碼
    return const DocumentTypeClassifier().classify(prompt).displayName;
  }

  List<Map<String, String>> _buildWorkflowActions({
    required String title,
    required String documentType,
    required String content,
  }) {
    final source = _compactForWorkflow(content);
    return [
      {
        'id': 'formalize',
        'label': '改寫成正式版',
        'description': '把目前草稿整理成正式、可交付的語氣。',
        'prompt':
            '$title - 正式版|請把以下$documentType改寫成正式可交付版本，保留重點，補足段落標題與清楚結論。\n\n$source',
      },
      {
        'id': 'slides',
        'label': '轉成簡報大綱',
        'description': '把目前文件改成投影片章節與每頁重點。',
        'prompt':
            '$title - 簡報大綱|請把以下$documentType轉成簡報大綱，列出每張投影片標題、三個重點與建議視覺。\n\n$source',
      },
      {
        'id': 'toc',
        'label': '補目錄',
        'description': '補上文件目錄、章節層級與閱讀順序。',
        'prompt':
            '$title - 補目錄|請替以下$documentType補上目錄與章節層級，並整理成更好閱讀的文件結構。\n\n$source',
      },
      {
        'id': 'summary',
        'label': '補摘要',
        'description': '補一段開頭摘要與可行動結論。',
        'prompt':
            '$title - 補摘要|請替以下$documentType補上高層摘要、三個關鍵結論與下一步行動。\n\n$source',
      },
      {
        'id': 'new_version',
        'label': '另存新版本',
        'description': '保留原稿，產出一份新版本。',
        'prompt':
            '$title - 新版本|請根據以下$documentType另存一份更清楚的新版本，保留原意但改善順序、語氣與格式。\n\n$source',
      },
    ];
  }

  String _compactForWorkflow(String content) {
    final trimmed = content.trim();
    const limit = 4200;
    if (trimmed.length <= limit) return trimmed;
    return '${trimmed.substring(0, limit)}\n\n（以上為原文件前段摘錄；請依已提供內容延伸整理。）';
  }

  String _buildMarkdown({required String title, required String prompt}) {
    final now = DateTime.now().toIso8601String();
    final body = prompt.contains('|')
        ? prompt.substring(prompt.indexOf('|') + 1).trim()
        : prompt.trim();

    return [
      '# $title',
      '',
      '> 由橋樑 APP 文件產出橋整理。',
      '',
      '## 文件資訊',
      '',
      '- 產出時間：$now',
      '- 產出格式：Markdown',
      '- 來源任務：文件產出橋',
      '',
      '## 整理內容',
      '',
      body.isEmpty ? '（尚無內容）' : body,
      '',
      '## 下一步',
      '',
      '- 你可以回到橋樑 APP 要求我改寫、補充、轉成清單、規格、企劃或報告格式。',
      '- 目前會同步輸出 Markdown、HTML 與 PDF；DOCX / 簡報會保留為下一階段插件接口。',
      '',
    ].join('\n');
  }
}
