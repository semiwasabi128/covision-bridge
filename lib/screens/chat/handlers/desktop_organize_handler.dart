// [教練 Agent Sprint 17 Step 7 — 2026-07-07]
// DesktopOrganizeHandler — 桌面整理 / 受管資料夾規則業務邏輯，從
// chat_screen.dart _ChatScreenState 拆出（原行 2849-3229）。
//
// 職責：
//   1. 受管資料夾規則重用入口（沿用已存規則掃描新資料夾）。
//   2. 桌面整理確認訊息、整理報告產出、整理規則產出與匯入。
//   3. 受管資料夾規則登記、語意標題、第二大腦索引。
//   4. 桌面整理規則 prompt 產生。
//
// 設計：
// - 依賴全部透過 DesktopOrganizeHandlerConfig 構造函數傳入，handler 不持有
//   ChatScreenState，方便測試與單獨復用（與 DigitalAssetIndexHandler 同式）。
// - 純搬移，不改邏輯：方法內容與 chat_screen.dart 原始版本一致，只把
//   _currentConversation / _managedFolderRules / _managedFolderRuleStore /
//   _secondBrainFileIndexStore / _managedFolderRuleNamer / _controller /
//   _basename / _desktopCategorySummary 等欄位存取改為 config.xxx，並把
//   _appendLocalSystemMessage / _appendBridgeResultMessage /
//   _appendBridgeConfirmationMessage / _showSuccess /
//   _appendManagedFolderRulePickerCard / widget.bridgeActionExecutor / mounted
//   改成注入的回調或值。
// - 所有方法去掉 `_` 前綴成為 instance method；純輔助方法
//   （normalizeFolderPath / managedFolderRuleIdFor /
//   desktopOrganizeConfirmationMessage / documentMarkdownPath /
//   semanticManagedFolderRuleTitle / desktopPlanRulesPrompt）以 static
//   方法提供，避免對 config 的隱式依賴。

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../controllers/chat_controller.dart';
import '../../../models/bridge_action.dart';
import '../../../models/chat_card_data.dart';
import '../../../models/conversation.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../services/bridge_action_executor.dart';
import '../../../services/bridge_adapters/local_desktop_files_adapter.dart';
import '../../../services/bridge_media_store.dart';
import '../../../services/desktop_organize_report_builder.dart';
import '../../../services/managed_folder_rule_namer.dart';
import '../../../services/managed_folder_rule_store.dart';
import '../../../services/second_brain_file_index_store.dart';
import '../helpers/bridge_action_ui_helper.dart';

/// 桌面整理 / 受管資料夾規則 handler 的依賴封裝。
///
/// 把原本散在 _ChatScreenState 的欄位與跨畫面回調集中成一個 config，
/// 構造時一次傳入，handler 內部不再回頭存取 ChatScreen。
class DesktopOrganizeHandlerConfig {
  const DesktopOrganizeHandlerConfig({
    required this.controller,
    required this.managedFolderRuleStore,
    required this.secondBrainFileIndexStore,
    required this.managedFolderRuleNamer,
    required this.managedFolderRules,
    required this.currentConversation,
    required this.bridgeActionExecutorOverride,
    required this.mounted,
    required this.basename,
    required this.desktopCategorySummary,
    required this.appendLocalSystemMessage,
    required this.appendBridgeResultMessage,
    required this.appendBridgeConfirmationMessage,
    required this.showSuccess,
    required this.appendManagedFolderRulePickerCard,
  });

  /// 用於 executeBridgeAction / loadManagedFolderRules。
  final ChatController controller;

  /// 受管資料夾規則儲存庫（upsert ManagedFolderRule）。
  final ManagedFolderRuleStore managedFolderRuleStore;

  /// 第二大腦檔案索引庫（upsert SecondBrainFileEntry）。
  final SecondBrainFileIndexStore secondBrainFileIndexStore;

  /// 受管資料夾規則命名器（產生語意標題）。
  final ManagedFolderRuleNamer managedFolderRuleNamer;

  /// 目前已載入的受管資料夾規則清單。
  final List<ManagedFolderRule> managedFolderRules;

  /// 目前對話（_executeDesktopPlanReport 會檢查 null 提早返回）。
  final Conversation? currentConversation;

  /// 對應 ChatScreen.bridgeActionExecutor；非 null 代表開發預覽環境，
  /// 走不掃描本機資料夾的提示分支。
  final BridgeActionExecutor? bridgeActionExecutorOverride;

  /// 目前 State 是否仍 mounted（避免 setState 後使用失效的 context）。
  final bool Function() mounted;

  /// 取路徑檔名（basename）的回調。
  final String? Function(String?) basename;

  /// 把桌面整理 metadata 換成主要分類摘要的回調。
  final String Function(Map<String, dynamic>) desktopCategorySummary;

  /// 附加本地系統訊息的回調。
  final Future<void> Function(String) appendLocalSystemMessage;

  /// 附加橋樑動作結果訊息的回調。
  final Future<void> Function(BridgeActionResult) appendBridgeResultMessage;

  /// 附加橋樑動作確認訊息的回調。
  final Future<void> Function(BridgeAction, BridgeActionResult)
  appendBridgeConfirmationMessage;

  /// 顯示成功 SnackBar 的回調。
  final void Function(String) showSuccess;

  /// 附加受管資料夾規則選擇卡的回調。
  final void Function(String, {String? targetFolderPath, String? targetFolderLabel})
  appendManagedFolderRulePickerCard;
}

/// 桌面整理 / 受管資料夾規則 handler。
///
/// 把 chat_screen.dart 原行 2849-3229 的 desktop/managed-folder 方法群搬過來，
/// 去掉 `_` 前綴成為 instance method；純輔助方法以 static 提供。
class DesktopOrganizeHandler {
  DesktopOrganizeHandler({required this.config});

  final DesktopOrganizeHandlerConfig config;

  // ─── 受管資料夾規則重用入口 ───

  Future<void> startManagedFolderRuleReuse(
    ManagedFolderRulePickerItem rule, {
    required ManagedFolderRulePickerCardData card,
  }) async {
    if (kIsWeb || config.bridgeActionExecutorOverride != null) {
      await config.appendLocalSystemMessage(
        card.targetFolderPath == null || card.targetFolderPath!.trim().isEmpty
            ? '我已選到規則「${rule.ruleTitle}」。\n\n開發預覽環境暫不支援直接選本機資料夾；請在桌面 App 使用這張卡，選擇要套用規則的資料夾後，我會先只讀掃描並列出整理計畫。'
            : '我已選到規則「${rule.ruleTitle}」，會套用到「${card.targetFolderLabel ?? card.targetFolderPath}」。\n\n開發預覽環境暫不支援直接掃描本機資料夾；請在桌面 App 使用這張卡。',
      );
      return;
    }
    var normalizedPath = card.targetFolderPath?.trim();
    if (normalizedPath == null || normalizedPath.isEmpty) {
      final folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '選擇要套用「${rule.ruleTitle}」的資料夾',
      );
      normalizedPath = folderPath?.trim();
    }
    if (normalizedPath == null || normalizedPath.isEmpty) return;

    final prompt = LocalDesktopFilesAdapter.scanPrompt(
      rootPath: normalizedPath,
      taskPrompt: [
        '沿用已存整理規則產生整理計畫，不要搬移、改名或刪除檔案。',
        '整理規則：${rule.ruleTitle}',
        '規則文件：${rule.rulePath}',
        if (rule.categorySummary.trim().isNotEmpty)
          '規則摘要：${rule.categorySummary}',
        '請先比對這個資料夾目前檔案與規則，列出建議分類、保留項目、需要我確認的例外。',
      ].join('\n'),
    );
    await config.controller.executeBridgeAction(
      BridgeAction(
        type: BridgeActionType.desktopFiles,
        prompt: prompt,
        provider: 'local_desktop_files',
      ),
      confirmed: true,
    );
  }

  // ─── 桌面整理確認 ───

  Future<void> requestDesktopOrganizeConfirmation(
    Map<String, dynamic> metadata,
    String applyPrompt,
  ) async {
    await config.appendBridgeConfirmationMessage(
      BridgeAction(
        type: BridgeActionType.desktopFiles,
        prompt: applyPrompt,
        provider: 'local_desktop_files',
      ),
      BridgeActionResult(
        status: BridgeActionStatus.needsConfirmation,
        message: desktopOrganizeConfirmationMessage(
          metadata,
          desktopCategorySummary: config.desktopCategorySummary,
        ),
        metadata: {
          'type': 'desktop_files',
          'kind': 'desktop_organize_confirmation',
          'rootPath': metadata['rootPath'],
          'plannedFolderCount': metadata['plannedFolderCount'],
          'plannedMoveCount': metadata['plannedMoveCount'],
          'skippedCount': metadata['skippedCount'],
          'categorySummary': config.desktopCategorySummary(metadata),
        },
      ),
    );
  }

  // ─── 桌面整理報告產出 ───

  Future<void> executeDesktopPlanReport(Map<String, dynamic> metadata) async {
    if (config.currentConversation == null) return;
    final rootPath = metadata['rootPath']?.toString().trim();
    final rootName = config.basename(rootPath) ?? '授權資料夾';
    final title = '桌面整理報告：$rootName';
    final content = const DesktopOrganizeReportBuilder().build(metadata);
    final markdownPath = await BridgeMediaStore.persistMarkdownDocument(
      title: title,
      content: content,
      documentCategory: '報告',
    );
    final htmlPath = await BridgeMediaStore.persistHtmlDocument(
      title: title,
      markdown: content,
      documentCategory: '報告',
    );
    final pdfPath = await BridgeMediaStore.persistPdfDocument(
      title: title,
      markdown: content,
      documentCategory: '報告',
    );
    final exportPaths = {
      'Markdown': markdownPath,
      'HTML': htmlPath,
      'PDF': pdfPath,
    };
    final result = BridgeActionResult(
      status: BridgeActionStatus.completed,
      message: [
        '整理報告已保存。',
        '已依 Bridge Desktop 實際掃描資料產生 Markdown / HTML / PDF，不使用雲端模型補寫樣本。',
        '',
        '可開啟檔案：',
        for (final entry in exportPaths.entries)
          '- ${entry.key}：${entry.value}',
        '',
        '下一步可以請我改寫、補充、轉成正式規格、企劃書或簡報大綱。',
      ].join('\n'),
      mediaUrl: markdownPath,
      metadata: {
        'type': BridgeActionType.document.legacyType,
        'kind': 'document',
        'provider': 'bridge_desktop',
        'adapter': 'Bridge Desktop 確定性整理報告',
        'generationMode': 'scan_metadata',
        'title': title,
        'documentType': '報告',
        'format': 'Markdown / HTML / PDF',
        'path': markdownPath,
        'exportPaths': exportPaths,
        'sourceBridge': 'desktop_files',
        'sourceMetadataKind': metadata['kind'],
        'rootPath': metadata['rootPath'],
        'plannedFormats': const ['DOCX', 'PPTX'],
        'workflowActions': const [
          {'label': '改寫成正式版', 'prompt': '請把這份桌面整理報告改寫成正式交付版本。'},
          {'label': '轉成簡報大綱', 'prompt': '請把這份桌面整理報告轉成簡報大綱。'},
          {'label': '補目錄', 'prompt': '請為這份桌面整理報告補上目錄。'},
          {'label': '補摘要', 'prompt': '請為這份桌面整理報告補上摘要。'},
          {'label': '另存新版本', 'prompt': '請依目前文件另存一份新版本。'},
        ],
        'pluginInterfaces': const [
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
    await config.appendBridgeResultMessage(result);
    if (!config.mounted()) return;
    config.showSuccess('已保存完整整理報告。');
  }

  // ─── 桌面整理規則產出 / 匯入 ───

  Future<void> executeDesktopPlanRules(Map<String, dynamic> metadata) async {
    await executeDesktopPlanDocument(
      metadata,
      titleSuffix: '規則',
      body: desktopPlanRulesPrompt(
        metadata,
        desktopCategorySummary: config.desktopCategorySummary,
      ),
      onCompleted: (result) => registerManagedFolderRuleFromResult(
        metadata,
        result,
        source: 'generated',
      ),
    );
  }

  Future<void> importDesktopOrganizeRules(
    Map<String, dynamic> metadata,
  ) async {
    final rootPath = metadata['rootPath']?.toString().trim();
    final rootLabel = config.basename(rootPath) ?? '目前資料夾';
    config.appendManagedFolderRulePickerCard(
      '替目前資料夾套用已存整理規則',
      targetFolderPath: rootPath == null || rootPath.isEmpty ? null : rootPath,
      targetFolderLabel: rootLabel,
    );
  }

  Future<void> executeDesktopPlanDocument(
    Map<String, dynamic> metadata, {
    required String titleSuffix,
    required String body,
    Future<void> Function(BridgeActionResult result)? onCompleted,
  }) async {
    final rootPath = metadata['rootPath']?.toString().trim();
    final rootName = config.basename(rootPath) ?? '授權資料夾';
    await config.controller.executeBridgeAction(
      BridgeAction(
        type: BridgeActionType.document,
        prompt: '桌面整理$titleSuffix：$rootName|$body',
        provider: 'local_document',
      ),
      confirmed: true,
      onCompleted: onCompleted,
    );
  }

  // ─── 受管資料夾規則登記 ───

  Future<void> registerManagedFolderRuleFromResult(
    Map<String, dynamic> desktopPlanMetadata,
    BridgeActionResult result, {
    required String source,
  }) async {
    final resultMetadata = result.metadata;
    final rulePath = resultMetadata == null
        ? result.mediaUrl?.trim()
        : documentMarkdownPath(resultMetadata) ?? result.mediaUrl?.trim();
    final title = resultMetadata?['title']?.toString().trim();
    if (rulePath == null || rulePath.isEmpty) return;
    await registerManagedFolderRuleFromPath(
      desktopPlanMetadata,
      rulePath,
      title: title == null || title.isEmpty ? '整理規則' : title,
      source: source,
    );
  }

  Future<void> registerManagedFolderRuleFromPath(
    Map<String, dynamic> desktopPlanMetadata,
    String rulePath, {
    required String title,
    required String source,
  }) async {
    final rootPath = desktopPlanMetadata['rootPath']?.toString().trim();
    if (rootPath == null || rootPath.isEmpty || rulePath.trim().isEmpty) {
      return;
    }
    final folderLabel = config.basename(rootPath) ?? rootPath;
    final semanticRuleTitle = semanticManagedFolderRuleTitle(
      desktopPlanMetadata,
      folderLabel: folderLabel,
      source: source,
      namer: config.managedFolderRuleNamer,
      desktopCategorySummary: config.desktopCategorySummary,
    );
    final saved = await config.managedFolderRuleStore.upsert(
      ManagedFolderRule(
        id: managedFolderRuleIdFor(rootPath),
        folderPath: rootPath,
        folderLabel: folderLabel,
        rulePath: rulePath.trim(),
        ruleTitle: semanticRuleTitle,
        ruleSource: source,
        categorySummary: config.desktopCategorySummary(desktopPlanMetadata),
        mode: 'suggest_only',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await indexManagedFolderRuleDocument(saved, config.secondBrainFileIndexStore);
    await config.controller.loadManagedFolderRules(trigger: '整理規則更新');
    config.showSuccess('已把「${saved.folderLabel}」登記為受管資料夾。之後新檔案會先依規則判斷，再請你確認。');
  }

  Future<void> indexManagedFolderRuleDocument(
    ManagedFolderRule rule,
    SecondBrainFileIndexStore store,
  ) {
    return store.upsert(
      SecondBrainFileEntry(
        id: 'managed-folder-rule-document-${rule.id}',
        title: rule.ruleTitle,
        path: rule.rulePath,
        room: SecondBrainRoom.files,
        summary: '整理規則文件：${rule.ruleTitle}。已綁定受管資料夾「${rule.folderLabel}」。',
        contentDigest: '文件類型：規則。受管資料夾：${rule.folderPath}。模式：${rule.modeLabel}。',
        contentExcerpt: '後續新檔案會先依此規則判斷，再請使用者確認是否整理。',
        tags: const ['文件資產', '文件產出橋', '規則', '受管資料夾', '任務收尾歸檔'],
        keywords: [
          rule.ruleTitle,
          rule.rulePath,
          rule.folderLabel,
          rule.folderPath,
          '規則',
          '整理規則',
          '受管資料夾',
          '歸檔',
        ],
        indexedAt: rule.updatedAt,
        trustScore: 84,
        pinned: true,
      ),
    );
  }

  // ─── 純輔助方法（static） ───

  /// 正規化資料夾路徑：去頭尾空白、去尾端斜線。
  static String normalizeFolderPath(String path) {
    var value = path.trim();
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 依資料夾路徑產生穩定 ID（base64url，去 padding）。
  static String managedFolderRuleIdFor(String folderPath) {
    return base64Url
        .encode(utf8.encode(normalizeFolderPath(folderPath).toLowerCase()))
        .replaceAll('=', '');
  }

  /// 桌面整理確認訊息（純字串組裝，不依賴 config）。
  static String desktopOrganizeConfirmationMessage(
    Map<String, dynamic> metadata, {
    required String Function(Map<String, dynamic>) desktopCategorySummary,
  }) {
    final rootPath = metadata['rootPath']?.toString().trim();
    final categorySummary = desktopCategorySummary(metadata);
    return [
      '請確認是否執行桌面整理計畫。',
      '',
      '這一步會動到你的本機檔案，所以我會先說清楚：',
      '- 掃描位置：${rootPath == null || rootPath.isEmpty ? '未標示' : rootPath}',
      '- 預計建立資料夾：${metadata['plannedFolderCount'] ?? 0} 個',
      '- 預計搬移檔案：${metadata['plannedMoveCount'] ?? 0} 個',
      '- 保留原處：${metadata['skippedCount'] ?? 0} 個',
      '- 主要分類：$categorySummary',
      '',
      '安全承諾：不刪除檔案、不覆蓋同名檔案、不處理分類不明確的項目。',
      '執行完成後會自動產生整理紀錄與整理報告，並寫入第二大腦檔案房間。',
    ].join('\n');
  }

  /// 從 metadata 取出 Markdown 文件路徑。
  static String? documentMarkdownPath(Map<String, dynamic> metadata) {
    final exportPaths = metadata['exportPaths'];
    if (exportPaths is Map) {
      for (final entry in exportPaths.entries) {
        final key = entry.key.toString().toLowerCase();
        final value = entry.value.toString().trim();
        if (value.isEmpty) continue;
        if (key.contains('markdown') || value.toLowerCase().endsWith('.md')) {
          return value;
        }
      }
    }
    final path = metadata['path']?.toString().trim();
    if (path != null && path.isNotEmpty) return path;
    return null;
  }

  /// 產生受管資料夾規則的語意標題。
  static String semanticManagedFolderRuleTitle(
    Map<String, dynamic> metadata, {
    required String folderLabel,
    required String source,
    required ManagedFolderRuleNamer namer,
    required String Function(Map<String, dynamic>) desktopCategorySummary,
  }) {
    return namer.title(
      folderLabel: folderLabel,
      categorySummary: desktopCategorySummary(metadata),
      source: source,
    );
  }

  /// 桌面整理規則產出 prompt。
  static String desktopPlanRulesPrompt(
    Map<String, dynamic> metadata, {
    required String Function(Map<String, dynamic>) desktopCategorySummary,
  }) {
    final rootPath = metadata['rootPath']?.toString().trim();
    final categorySummary = desktopCategorySummary(metadata);
    final suggestions = BridgeActionUIHelper.stringListFromMetadata(metadata['suggestions']);
    final samples = BridgeActionUIHelper.desktopSampleNames(metadata['samples']);
    return [
      '請根據以下桌面整理橋結果，建立一份可重複使用的「桌面整理規則」。',
      '',
      '規則需要包含：',
      '1. 檔案分類規則。',
      '2. 命名建議。',
      '3. 遇到不確定檔案時的處理原則。',
      '4. 不刪除、不覆蓋、不自動處理敏感檔案的安全規則。',
      '5. 下次掃描時可以沿用的判斷標準。',
      '',
      '桌面整理橋資料：',
      '- 掃描位置：${rootPath == null || rootPath.isEmpty ? '未標示' : rootPath}',
      '- 檔案數：${metadata['fileCount'] ?? 0}',
      '- 資料夾數：${metadata['folderCount'] ?? 0}',
      '- 主要分類：$categorySummary',
      if (suggestions.isNotEmpty) ...[
        '',
        '整理建議：',
        for (final suggestion in suggestions.take(6)) '- $suggestion',
      ],
      if (samples.isNotEmpty) ...[
        '',
        '樣本檔案：',
        for (final sample in samples.take(12)) '- $sample',
      ],
      '',
      '請用繁體中文，整理成能放進第二大腦「檔案房間」長期沿用的規則文件。',
    ].join('\n');
  }
}
