// document_type_classifier.dart
// [Phase 2 #18] 共用文件類型偵測——消除 local_document_adapter 與 bridge_media_store 的重複。
// 正則在此處是正確工具（分類精度足夠，不需 LLM）。
// 兩處原本各自維護一份，現統一為此類。

/// 文件類型分類結果。
class DocumentTypeClassification {
  /// 中文顯示名稱（如 'PRD / 規格', '企劃', '報告'...）
  final String displayName;

  /// 英文目錄名稱（如 'specs', 'proposals', 'reports'...）
  final String categoryPath;

  const DocumentTypeClassification({
    required this.displayName,
    required this.categoryPath,
  });

  static const fallback = DocumentTypeClassification(
    displayName: '文件',
    categoryPath: 'general',
  );
}

/// 共用文件類型偵測器。
/// 合併自 local_document_adapter._detectDocumentType() 和 bridge_media_store._documentCategoryPath()。
class DocumentTypeClassifier {
  const DocumentTypeClassifier();

  /// 根據 prompt 文字判斷文件類型。
  /// 返回 displayName + categoryPath 的組合結果。
  DocumentTypeClassification classify(String prompt) {
    final text = prompt.toLowerCase();

    if (RegExp(r'prd|規格|需求|產品需求|產品規格|spec').hasMatch(text)) {
      return const DocumentTypeClassification(
        displayName: 'PRD / 規格',
        categoryPath: 'specs',
      );
    }
    if (RegExp(r'企劃|計畫|專案|proposal|plan').hasMatch(text)) {
      return const DocumentTypeClassification(
        displayName: '企劃',
        categoryPath: 'proposals',
      );
    }
    if (RegExp(r'報告|分析|研究|report|analysis').hasMatch(text)) {
      return const DocumentTypeClassification(
        displayName: '報告',
        categoryPath: 'reports',
      );
    }
    if (RegExp(r'規則|規範|rule|rules|policy|policies').hasMatch(text)) {
      return const DocumentTypeClassification(
        displayName: '規則',
        categoryPath: 'rules',
      );
    }
    if (RegExp(r'摘要|總結|整理重點|summary').hasMatch(text)) {
      return const DocumentTypeClassification(
        displayName: '摘要',
        categoryPath: 'summaries',
      );
    }
    if (RegExp(r'清單|待辦|檢查表|checklist|todo|to-do').hasMatch(text)) {
      return const DocumentTypeClassification(
        displayName: '清單',
        categoryPath: 'checklists',
      );
    }
    if (RegExp(r'簡報|投影片|ppt|slides|slide|大綱').hasMatch(text)) {
      return const DocumentTypeClassification(
        displayName: '簡報大綱',
        categoryPath: 'outlines',
      );
    }

    return DocumentTypeClassification.fallback;
  }
}
