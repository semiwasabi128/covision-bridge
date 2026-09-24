// 橋樑 App — 夥伴列表 / 召喚陣
import "../core/responsive.dart";
// 設計風格：新藍綠色調

import 'package:flutter/material.dart';

import '../widgets/breathing_image.dart'; // [小葵 2026-09-13] 呼吸感預覽
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../models/agent_activity.dart';
import '../theme/app_theme.dart';
import '../services/achievement_store.dart';
import '../services/brain_progress_store.dart';
import '../services/companion_asset_manifest_service.dart';
import '../services/companion_store.dart';
import '../models/companion.dart';
import '../services/companion_pack_service.dart';
import '../services/semi_dao_review_store.dart';
import '../widgets/companion_avatar_image.dart';
import '../widgets/companion_rig.dart';
import '../widgets/companion_rig_animator.dart';
import '../widgets/companion_art.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import 'bridge_desktop_screen.dart';

class CompanionListScreen extends StatefulWidget {
  const CompanionListScreen({super.key});

  @override
  State<CompanionListScreen> createState() => _CompanionListScreenState();
}

class _CompanionListScreenState extends State<CompanionListScreen> {
  @override
  void initState() {
    super.initState();
    _syncExistingSemiDaoPassports();
  }

  @override
  Widget build(BuildContext context) {
    final store = CompanionStore();
    final companions = store.all;
    final activeId = store.activeCompanionId;

    return Scaffold(
      backgroundColor: BridgeDSColors.of(context).canvas,
      appBar: AppBar(
        title: const Text('召喚夥伴'),
        backgroundColor: BridgeDSColors.of(context).canvas,
        actions: [
          // [以利沙 Sprint1 P1-4 2026-06-30] AppBar 最多2個trailing：
          // 保留「設定」icon + 三點選單收其餘功能
          IconButton(
            tooltip: '設定',
            icon: Icon(
              Icons.settings_outlined,
              color: BridgeDSColors.of(context).textPrimary,
            ),
            onPressed: () => BridgeDesktopScreen.navigateTo('system'),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              color: BridgeDSColors.of(context).textPrimary,
            ),
            tooltip: '更多功能',
            onSelected: (value) {
              switch (value) {
                case 'achievements':
                  context.go('/achievements');
                  break;
                case 'import_pack':
                  _showImportDialog();
                  break;
                case 'semi_dao':
                  // [教練 Agent 2026-08-05] 社群評審系統上線前，改導向 placeholder 頁面
                  context.go('/semi-dao/review');
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'achievements',
                child: Row(
                  children: [
                    Icon(Icons.emoji_events_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('山門徽章'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import_pack',
                child: Row(
                  children: [
                    Icon(Icons.file_open_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('匯入角色包'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'semi_dao',
                child: Row(
                  children: [
                    Icon(Icons.how_to_vote_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('SemiDAO 預審池'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: companions.isEmpty
          ? _buildEmptyState()
          : _buildCompanionGrid(companions, activeId),
      floatingActionButton: FloatingActionButton.extended(
        // [教練 Agent 2026-06-28] 軟上限保護：超過 12 個角色時提醒（不硬擋）
        // [P2-19 修復 2026-06-30] SnackBar 加 action button 引導
        onPressed: () {
          if (companions.length >= 12) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '你已建立 12 位夥伴。夥伴越多，手機記憶體使用量越大。'
                  '如需繼續建立，建議先刪除不常用的角色。',
                ),
                duration: const Duration(seconds: 6),
                action: SnackBarAction(
                  label: '查看夥伴館',
                  onPressed: () => context.go('/companions'),
                ),
              ),
            );
          }
          context.go('/companion/create');
        },
        backgroundColor: BridgeDSColors.of(context).canvas,
        // [P3-1 修復 2026-06-30] 去除冗餘 +icon，label 已表達動作
        // [小葵 2026-09-01] FAB 歸範——黑底紫框（side）
        label: Text(
          '鍊成新夥伴',
          style: TextStyle(color: BridgeDSColors.of(context).textPrimary),
        ),
        elevation: 4,
      ),
    );
  }

  Future<void> _syncExistingSemiDaoPassports() async {
    final cases = await const SemiDaoReviewStore().loadCases();
    if (cases.isEmpty) return;
    var changed = false;
    final store = CompanionStore();
    for (final reviewCase in cases) {
      final companion = store.getById(reviewCase.companionId);
      if (companion == null) continue;
      final passport = companion.rightsPassport;
      final shouldUpdate =
          passport == null ||
          passport.reviewCaseId != reviewCase.id ||
          passport.reviewedAt.isBefore(reviewCase.certification.certifiedAt);
      if (!shouldUpdate) continue;
      await store.update(
        companion.copyWith(rightsPassport: _passportFromReviewCase(reviewCase)),
      );
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  Widget _buildEmptyState() {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      children: [
        Container(
          padding: const EdgeInsets.all(AppTheme.spacingM),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                BridgeDSColors.of(context).accentNavy,
                BridgeDSColors.of(context).accentNavy,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            children: [
              Text(
                'SemiDAO 夥伴館',
                style: TierStyle.of(context, Tier.appHeadline)
                    .toTextStyle()
                    .copyWith(
                      color: BridgeDSColors.of(context).textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              SizedBox(height: 8),
              Text(
                '你的第一位替身使者還在山門外等待命名。',
                textAlign: TextAlign.center,
                style: TierStyle.of(context, Tier.listItemSubtitle)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).textSecondary),
              ),
              const SizedBox(height: AppTheme.spacingM),
              const CompanionArt(
                mbtiCode: 'ENFJ',
                seed: 42,
                name: '山門光靈',
                mood: AgentCompanionMood.curious,
                action: AgentCompanionAction.wandering,
                size: 240,
              ),
              SizedBox(height: AppTheme.spacingM),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.go('/companion/create'),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('開始鍊成'),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showImportDialog,
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('匯入角色包'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: BridgeDSColors.of(context).textPrimary,
                        side: BorderSide(
                          color: BridgeDSColors.of(context).textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacingM),
        const _EmptyFeatureStrip(),
      ],
    );
  }

  Widget _buildCompanionGrid(List<Companion> companions, String? activeId) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingM),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacingM),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  BridgeDSColors.of(context).accentNavy,
                  BridgeDSColors.of(context).accentNavy,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              boxShadow: AppTheme.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SemiDAO 夥伴館',
                  style: TierStyle.of(context, Tier.cardHeroTitle)
                      .toTextStyle()
                      .copyWith(
                        fontWeight: FontWeight.w900,
                        color: BridgeDSColors.of(context).textPrimary,
                      ),
                ),
                SizedBox(height: 8),
                Text(
                  '召喚、匯入與切換你的替身使者。每位夥伴都有自己的造型與工作狀態，但共用同一個 Bridge Brain。',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(
                        height: 1.35,
                        color: BridgeDSColors.of(context).textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // [教練 Agent 2026-08-06] 用 Responsive 輔助 columns 判斷
                final columns =
                    (Responsive.isDesktop(context) ||
                        constraints.maxWidth >= 1120)
                    ? 3
                    : constraints.maxWidth >= 680
                    ? 2
                    : 1;
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: columns == 1 ? 0.92 : 0.88,
                  ),
                  itemCount: companions.length,
                  itemBuilder: (context, index) {
                    final companion = companions[index];
                    final isActive = companion.id == activeId;
                    return _CompanionCard(
                      companion: companion,
                      isActive: isActive,
                      // [修復] 夥伴卡片點擊改為進入設定頁面（編輯模式），
                      // 讓使用者調整數值與形象個性後更新招喚，
                      // 而非顯示詳情底部彈窗再進入聊天。
                      onTap: () =>
                          context.go('/companion/create?id=${companion.id}'),
                      onExport: () => _exportCompanion(companion),
                      onEdit: () =>
                          context.go('/companion/create?id=${companion.id}'),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCompanion(Companion companion) async {
    final localOnly = _isLocalOnlyPassport(companion.rightsPassport);
    final commercialUseAllowed = await _askCommercialUseAllowed(
      title: '匯出角色包',
      body:
          '這份檔案會儲存成可備份或私下傳遞的角色資產包。請確認是否允許收到這份資產包的人拿它做商業用途。'
          '${localOnly ? '\n\n注意：這張角色卡目前是黃燈或紅燈，匯出的資產包會標記為本機限定，只能在這台電腦/這個 Bridge 安裝匯入，其他電腦會拒絕載入。' : ''}',
      confirmLabel: '匯出角色包',
    );
    if (commercialUseAllowed == null) return;
    if (!mounted) return;
    // [教練 Agent 2026-06-28] 修復：大型角色包存檔案，不塞剪貼簿（54MB 會 OOM）
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('正在匯出角色包...')),
          ],
        ),
      ),
    );
    try {
      final zipBytes = await CompanionStore().exportCompanionPackToZip(
        companion.id,
        commercialUseAllowed: commercialUseAllowed,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // 關 loading

      // [教練 Agent 2026-06-29] 改用 saveFile 讓使用者選擇存檔位置
      final safeName = companion.name.replaceAll(
        RegExp(r'[^\w\u4e00-\u9fff]'),
        '_',
      );
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: '儲存角色包',
        fileName: '$safeName.bridgepack.zip',
        bytes: Uint8List.fromList(zipBytes),
      );

      if (savedPath == null) {
        // 使用者取消，仍存一份到預設位置當備份
        final dir = await getApplicationDocumentsDirectory();
        final exportDir = Directory('${dir.path}/bridge_media/exports');
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        final file = File('${exportDir.path}/$safeName.bridgepack.zip');
        await file.writeAsBytes(zipBytes, flush: true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已匯出備份到：${file.path}'),
            action: SnackBarAction(
              label: '複製路徑',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: file.path)),
            ),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已匯出 ${companion.name} 的角色包到：$savedPath')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop(); // 關 loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯出失敗：$error')));
    }
  }

  Future<void> _shareToSemiDao(
    Companion companion, {
    String clarification = '',
  }) async {
    if (_isLocalOnlyPassport(companion.rightsPassport)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('目前不能分享社群包'),
          content: const Text(
            '這張角色卡目前是黃燈或紅燈，只能本機使用與本機匯入。請重新生成、補充聲明或通過預審成綠燈後，再分享到 SemiDAO 社群。',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    final commercialUseAllowed = await _askCommercialUseAllowed(
      title: '分享社群包',
      body: '你已選擇把這套角色資產包送入 SemiDAO 社群分享流程。接下來只需要確認是否允許其他人商用這套角色資產。',
      confirmLabel: '送出預審',
    );
    if (commercialUseAllowed == null || !mounted) return;
    final json = CompanionStore().exportCompanionPackToJson(
      companion.id,
      commercialUseAllowed: commercialUseAllowed,
    );
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('SemiDAO 正在進行文字與圖片預審...')),
          ],
        ),
      ),
    );
    SemiDaoReviewCase reviewCase;
    var progressClosed = false;
    try {
      reviewCase = await const SemiDaoReviewStore().submitCompanion(
        companion: companion,
        packJson: json,
        clarification: clarification,
      );
      await CompanionStore().update(
        companion.copyWith(rightsPassport: _passportFromReviewCase(reviewCase)),
      );
    } catch (error) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      progressClosed = true;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('SemiDAO 預審未完成'),
          content: Text('送審過程發生錯誤：$error'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    } finally {
      if (mounted && !progressClosed) {
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) navigator.pop();
      }
    }
    if (!mounted) return;
    setState(() {});
    final action = await showDialog<_SemiDaoReviewAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SemiDAO 平台預審完成'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                reviewCase.signalLabel,
                style: TextStyle(
                  color: switch (reviewCase.signal) {
                    SemiDaoReviewSignal.approved => BridgeDSColors.of(
                      context,
                    ).accentGreen,
                    SemiDaoReviewSignal.watching => BridgeDSColors.of(
                      context,
                    ).accentYellow,
                    SemiDaoReviewSignal.blocked => BridgeDSColors.of(
                      context,
                    ).accentRed,
                  },
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '這是 SemiDAO 平台第一層自動預審。通過代表可以進入社群展示流程；黃燈會列出需要補充的項目；紅燈代表暫不接受分享。',
                style: TextStyle(
                  color: BridgeDSColors.of(context).textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              _SemiDaoCertificationSummary(reviewCase: reviewCase),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_SemiDaoReviewAction.stay),
            child: const Text('留在角色列表'),
          ),
          if (reviewCase.certification.requiredClarifications.isNotEmpty)
            FilledButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_SemiDaoReviewAction.clarify),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('補充聲明後重送'),
            ),
          FilledButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(_SemiDaoReviewAction.openPool),
            icon: const Icon(Icons.how_to_vote_outlined),
            label: const Text('查看預審池'),
          ),
        ],
      ),
    );
    if (action == _SemiDaoReviewAction.clarify && mounted) {
      final supplement = await _showSemiDaoClarificationDialog(reviewCase);
      if (supplement != null && supplement.trim().isNotEmpty && mounted) {
        await _shareToSemiDao(companion, clarification: supplement);
      }
      return;
    }
    // [教練 Agent 2026-08-05] 社群評審系統上線前，改導向 placeholder 頁面
    if (action == _SemiDaoReviewAction.openPool && mounted) {
      context.go('/semi-dao/review');
    }
  }

  bool _isLocalOnlyPassport(CompanionRightsPassport? passport) {
    return passport?.signal == CompanionRightsSignal.watching ||
        passport?.signal == CompanionRightsSignal.blocked;
  }

  Future<bool?> _askCommercialUseAllowed({
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    var allowCommercialUse = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                body,
                style: TextStyle(
                  color: BridgeDSColors.of(context).textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: allowCommercialUse,
                onChanged: (value) =>
                    setDialogState(() => allowCommercialUse = value == true),
                title: const Text(
                  '我同意這份角色資產包可被商用',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('不勾選時，資產包會標記為不允許商用。'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(allowCommercialUse),
              icon: const Icon(Icons.verified_outlined),
              label: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
  }

  CompanionRightsPassport _passportFromReviewCase(
    SemiDaoReviewCase reviewCase,
  ) {
    return CompanionRightsPassport(
      signal: switch (reviewCase.signal) {
        SemiDaoReviewSignal.approved => CompanionRightsSignal.approved,
        SemiDaoReviewSignal.watching => CompanionRightsSignal.watching,
        SemiDaoReviewSignal.blocked => CompanionRightsSignal.blocked,
      },
      label: reviewCase.signalLabel,
      reviewCaseId: reviewCase.id,
      reviewedAt: reviewCase.certification.certifiedAt,
      passedCount: reviewCase.certification.passedChecks.length,
      warningCount: reviewCase.certification.warningChecks.length,
      blockedCount: reviewCase.certification.blockedChecks.length,
      inspectedImageCount:
          reviewCase.certification.visualReview?.inspectedImageCount ?? 0,
      requiredClarifications: reviewCase.certification.requiredClarifications,
      clarification: reviewCase.clarification,
    );
  }

  Future<String?> _showSemiDaoClarificationDialog(
    SemiDaoReviewCase reviewCase,
  ) async {
    final controller = TextEditingController(text: reviewCase.clarification);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('補充預審聲明'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '請根據下列項目補充說明。這不是法律保證，而是讓 SemiDAO 預審知道你對角色來源與使用邊界的聲明。',
                style: TextStyle(
                  color: BridgeDSColors.of(context).textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              for (final item
                  in reviewCase.certification.requiredClarifications)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.help_outline,
                        size: 16,
                        color: BridgeDSColors.of(context).accentYellow,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item,
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(
                                color: BridgeDSColors.of(context).textPrimary,
                                height: 1.35,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: '補充聲明',
                  hintText:
                      '例如：此角色為本人原創，未引用既有角色、Logo、商標或官方素材；動圖內容與主圖一致，無成人、暴力或官方混淆內容。',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍後再說'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(controller.text),
            icon: const Icon(Icons.send_outlined),
            label: const Text('儲存並重新預審'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _deleteCompanion(Companion companion) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除角色？'),
        content: Text('確定要刪除「${companion.name}」嗎？這會移除本機角色卡與設定。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await CompanionStore().delete(companion.id);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已刪除 ${companion.name}')));
  }

  Future<void> _showImportDialog() async {
    // [教練 Agent 2026-06-28] 修復 OOM 閃退：簡化匯入流程，不把 JSON 塞進 TextField
    // 原因：file content 同時存在 bytes+string+TextField+preview=4份記憶體 → iOS OOM kill
    // 改法：選檔 → 直接匯入 → 顯示結果，不留 JSON 在 UI 裡

    // Step 1: 選檔
    String? filePath;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;
      filePath = result.files.first.path;
    } catch (e) {
      debugPrint('[Import] file pick error: $e');
    }

    if (filePath == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未選擇檔案。請選擇 .bridgepack.zip 角色包檔案。')),
      );
      return;
    }

    // Step 2: 讀檔 + 匯入（不在 UI 層持有完整 JSON）
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('正在匯入角色包...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final raw = await File(filePath).readAsBytes();

      // [教練 Agent 2026-06-28] 只支援 ZIP 格式（舊 JSON 已廢止）
      final companion = await CompanionStore().importCompanionPackFromZip(raw);
      final achievement =
          await AchievementStore.unlockCompanionPackFirstImport();
      BrainProgressChange? progressChange;
      if (achievement.isNew) {
        progressChange = await BrainProgressStore.awardXp(
          achievement.achievement.xp,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      setState(() {});
      _showCompanionImportedToast(companion, achievement, progressChange);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('匯入失敗：$error')));
    }
  }

  // ignore: unused_element
  Future<bool?> _showPackPreviewDialog(CompanionPackPreview preview) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              preview.isSafe
                  ? Icons.verified_user_outlined
                  : Icons.warning_amber_outlined,
              color: preview.isSafe
                  ? BridgeDSColors.of(context).accentGreen
                  : BridgeDSColors.of(context).accentRed,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('角色包審核')),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: _CompanionPackPreviewPanel(preview: preview),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: preview.isSafe
                ? () => Navigator.of(context).pop(true)
                : null,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('確認召喚'),
          ),
        ],
      ),
    );
  }

  void _showCompanionImportedToast(
    Companion companion,
    AchievementUnlock achievement,
    BrainProgressChange? progressChange,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        backgroundColor: BridgeDSColors.of(context).accentNavy,
        content: _AchievementToast(
          companionName: companion.name,
          achievement: achievement,
          progressChange: progressChange,
        ),
      ),
    );
  }
}

class _EmptyFeatureStrip extends StatelessWidget {
  const _EmptyFeatureStrip();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.psychology_alt_outlined, '共同大腦', '多位夥伴共用記憶與洞察'),
      (Icons.palette_outlined, '角色圖組', '每位夥伴擁有工作狀態造型'),
      (Icons.emoji_events_outlined, '山門徽章', '召喚與匯入會累積成就'),
    ];

    return Column(
      children: items.map((item) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
          ),
          child: Row(
            children: [
              Icon(item.$1, color: BridgeDSColors.of(context).accentBlue),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$2,
                      style: TextStyle(
                        color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 0),
                    Text(
                      item.$3,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AchievementToast extends StatelessWidget {
  final String companionName;
  final AchievementUnlock achievement;
  final BrainProgressChange? progressChange;

  const _AchievementToast({
    required this.companionName,
    required this.achievement,
    required this.progressChange,
  });

  @override
  Widget build(BuildContext context) {
    final isNew = achievement.isNew;
    final xpText = progressChange == null
        ? '已加入 SemiDAO 綠洲'
        : '+${progressChange!.awardedXp} XP';
    final levelText = progressChange?.didLevelUp == true
        ? 'Bridge Brain Lv ${progressChange!.after.level}'
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: BridgeDSColors.of(context).accentYellow,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          ),
          child: Icon(
            isNew ? Icons.emoji_events_outlined : Icons.auto_awesome,
            color: BridgeDSColors.of(context).accentNavy,
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNew
                    ? '成就解鎖：${achievement.achievement.title}'
                    : '$companionName 已加入綠洲',
                style: TierStyle.of(context, Tier.cardCaptionBold)
                    .toTextStyle()
                    .copyWith(
                      color: BridgeDSColors.of(context).textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              SizedBox(height: 0),
              Text(
                isNew ? achievement.achievement.description : '角色包已通過本機安全審核。',
                style: TierStyle.of(context, Tier.cardCaption)
                    .toTextStyle()
                    .copyWith(color: BridgeDSColors.of(context).textSecondary),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _ToastPill(text: xpText),
                  if (levelText != null) _ToastPill(text: levelText),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToastPill extends StatelessWidget {
  final String text;

  _ToastPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).textPrimary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
      ),
      child: Text(
        text,
        style: TierStyle.of(context, Tier.cardCaption).toTextStyle().copyWith(
          color: BridgeDSColors.of(context).textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DetailPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _DetailPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _RightsPassportPill extends StatelessWidget {
  final CompanionRightsPassport? passport;
  final bool compact;

  const _RightsPassportPill({required this.passport, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final signal = passport?.signal ?? CompanionRightsSignal.unreviewed;
    final color = _colorFor(signal);
    final text = passport?.shortLabel ?? '尚未審查';
    final icon = switch (signal) {
      CompanionRightsSignal.approved => Icons.verified_user_outlined,
      CompanionRightsSignal.watching => Icons.warning_amber_outlined,
      CompanionRightsSignal.blocked => Icons.block_outlined,
      CompanionRightsSignal.unreviewed => Icons.shield_outlined,
    };
    final imageCount = passport?.inspectedImageCount ?? 0;
    final suffix = imageCount > 0 && !compact ? ' · 圖片 $imageCount' : '';

    return Container(
      constraints: compact ? const BoxConstraints(maxWidth: 190) : null,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 14, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '$text$suffix',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(CompanionRightsSignal signal) {
    // [教練 Agent 2026-08-04] 狀態語意色 — 不隨主題變（綠=批准/黃=觀察/紅=封鎖）
    // static 方法內無 context，所以用 BridgeDSColors.dark.xxx 拿固定值
    return switch (signal) {
      CompanionRightsSignal.approved => BridgeDSColors.dark.accentGreen,
      CompanionRightsSignal.watching => BridgeDSColors.dark.accentYellow,
      CompanionRightsSignal.blocked => BridgeDSColors.dark.accentRed,
      CompanionRightsSignal.unreviewed => BridgeDSColors.dark.textSecondary,
    };
  }
}

class _RightsPassportSummaryCard extends StatelessWidget {
  final CompanionRightsPassport? passport;

  const _RightsPassportSummaryCard({required this.passport});

  @override
  Widget build(BuildContext context) {
    final signal = passport?.signal ?? CompanionRightsSignal.unreviewed;
    final color = _RightsPassportPill._colorFor(signal);
    final title = passport?.label ?? '尚未產生角色資產權利護照';
    final reviewedAt = passport == null
        ? '尚未預審'
        : _formatDateTime(passport!.reviewedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RightsPassportPill(passport: passport),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.listItemSubtitle)
                      .toTextStyle()
                      .copyWith(
                        color: BridgeDSColors.of(context).textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            passport == null
                ? '這張角色卡尚未送交 SemiDAO 第一層預審。按「分享社群包」後，系統會自動產生護照並存回角色卡。'
                : '護照已存入角色卡。匯出角色包時會一併帶出這份預審摘要，方便之後追溯與社群展示。',
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                  height: 1.35,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PassportMetricChip(
                icon: Icons.schedule_outlined,
                text: reviewedAt,
              ),
              if (passport != null) ...[
                _PassportMetricChip(
                  icon: Icons.check_circle_outline,
                  text: '通過 ${passport!.passedCount}',
                ),
                _PassportMetricChip(
                  icon: Icons.warning_amber_outlined,
                  text: '提醒 ${passport!.warningCount}',
                ),
                _PassportMetricChip(
                  icon: Icons.block_outlined,
                  text: '封鎖 ${passport!.blockedCount}',
                ),
                _PassportMetricChip(
                  icon: Icons.image_search_outlined,
                  text: '圖片 ${passport!.inspectedImageCount}',
                ),
              ],
            ],
          ),
          if (passport?.requiredClarifications.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              '待補充：${passport!.requiredClarifications.join('、')}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(context).accentYellow,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}/${two(value.month)}/${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }
}

class _PassportMetricChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PassportMetricChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: BridgeDSColors.of(context).textSecondary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(
                  color: BridgeDSColors.of(context).textSecondary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _CompanionPackPreviewPanel extends StatelessWidget {
  final CompanionPackPreview preview;

  const _CompanionPackPreviewPanel({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PreviewHeader(preview: preview),
        const SizedBox(height: 16),
        _PreviewSection(
          title: '靈魂設定',
          icon: Icons.psychology_alt_outlined,
          children: [
            _PreviewLine(label: '角色', value: preview.role),
            _PreviewLine(label: 'MBTI', value: preview.mbtiCode),
            _PreviewLine(
              label: '個性',
              value: _joinOrDash(preview.personalityTags),
            ),
            _PreviewLine(label: '說話風格', value: preview.speakingStyle),
            _PreviewLine(label: '專長', value: _joinOrDash(preview.expertise)),
          ],
        ),
        const SizedBox(height: 16),
        _PreviewSection(
          title: '形象線索',
          icon: Icons.palette_outlined,
          children: [
            _PreviewLine(
              label: 'Prompt',
              value: preview.appearancePrompt,
              maxLines: 3,
            ),
            _PreviewLine(
              label: '描述',
              value: preview.appearanceDescription,
              maxLines: 3,
            ),
            if (preview.palette.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: preview.palette
                    .map((hex) => _PaletteChip(hex: hex))
                    .toList(),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _PreviewSection(
          title: '安全與權限',
          icon: Icons.shield_outlined,
          children: [
            _SafetyBanner(preview: preview),
            _PreviewLine(label: '風險等級', value: preview.riskLevel),
            _PreviewLine(label: '審核狀態', value: preview.reviewStatus),
            _PreviewLine(
              label: '必要權限',
              value: _joinOrDash(preview.requiredPermissions),
            ),
            _PreviewLine(
              label: '選用權限',
              value: _joinOrDash(preview.optionalPermissions),
            ),
            if (preview.contentWarnings.isNotEmpty)
              _PreviewLine(
                label: '內容提示',
                value: preview.contentWarnings.join('、'),
              ),
          ],
        ),
      ],
    );
  }

  static String _joinOrDash(List<String> values) {
    return values.isEmpty ? '未宣告' : values.join('、');
  }
}

class _PreviewHeader extends StatelessWidget {
  final CompanionPackPreview preview;

  const _PreviewHeader({required this.preview});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            preview.name,
            style: TierStyle.of(context, Tier.cardHeroTitle)
                .toTextStyle()
                .copyWith(
                  fontWeight: FontWeight.w700,
                  color: BridgeDSColors.of(context).textPrimary,
                ),
          ),
          if (preview.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview.summary,
              style: TierStyle.of(context, Tier.listItemSubtitle)
                  .toTextStyle()
                  .copyWith(color: BridgeDSColors.of(context).textSecondary),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.person_outline,
                text: preview.authorName.isEmpty ? '未知作者' : preview.authorName,
              ),
              _InfoChip(icon: Icons.sell_outlined, text: preview.version),
              _InfoChip(
                icon: Icons.policy_outlined,
                text: preview.license.isEmpty ? '未宣告授權' : preview.license,
              ),
              ...preview.tags
                  .take(4)
                  .map((tag) => _InfoChip(icon: Icons.tag, text: tag)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _PreviewSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: BridgeDSColors.of(context).accentBlue,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TierStyle.of(context, Tier.cardCaptionBold)
                    .toTextStyle()
                    .copyWith(
                      fontWeight: FontWeight.w700,
                      color: BridgeDSColors.of(context).textPrimary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  final String label;
  final String value;
  final int maxLines;

  const _PreviewLine({
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(
                    color: BridgeDSColors.of(context).textMuted,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '未宣告' : value,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.listItemSubtitle)
                  .toTextStyle()
                  .copyWith(color: BridgeDSColors.of(context).textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  final CompanionPackPreview preview;

  const _SafetyBanner({required this.preview});

  @override
  Widget build(BuildContext context) {
    final text = preview.isSafe
        ? '未宣告私人記憶、API Key 或可執行程式碼'
        : preview.unsafeReasons.join('、');
    final color = preview.isSafe
        ? BridgeDSColors.of(context).accentGreen
        : BridgeDSColors.of(context).accentRed;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        children: [
          Icon(
            preview.isSafe ? Icons.check_circle_outline : Icons.error_outline,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).canvas,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: BridgeDSColors.of(context).textSecondary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: BridgeDSColors.of(context).textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PaletteChip extends StatelessWidget {
  final String hex;

  const _PaletteChip({required this.hex});

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(hex) ?? BridgeDSColors.of(context).accentBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            hex,
            style: TierStyle.of(context, Tier.cardCaption)
                .toTextStyle()
                .copyWith(color: BridgeDSColors.of(context).textSecondary),
          ),
        ],
      ),
    );
  }

  static Color? _colorFromHex(String hex) {
    final normalized = hex.replaceFirst('#', '');
    if (normalized.length != 6) return null;
    final value = int.tryParse('FF$normalized', radix: 16);
    return value == null ? null : Color(value);
  }
}

class _CompanionCard extends StatelessWidget {
  final Companion companion;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onExport;
  final VoidCallback onEdit;

  const _CompanionCard({
    required this.companion,
    required this.isActive,
    required this.onTap,
    required this.onExport,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final mbti = companion.mbtiType;
    final color = mbti != null
        ? Color(int.parse(mbti.colorHex.replaceFirst('#', '0xFF')))
        : BridgeDSColors.of(context).accentBlue;
    final assetCount =
        (const CompanionAssetManifestService().buildForCompanion(
                  companion,
                )['includedAssets']
                as List<dynamic>)
            .length;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).canvas,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: isActive
              ? Border.all(
                  color: BridgeDSColors.of(context).accentBlue,
                  width: 2,
                )
              : Border.all(color: BridgeDSColors.of(context).borderSubtle),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頂部形象區
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                // [教練 Agent 2026-07-03] 背景統一改米色，去背瑕疵不明顯
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F0E1),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppTheme.radiusLarge),
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Material(
                        color: BridgeDSColors.of(
                          context,
                        ).canvas.withValues(alpha: 0.82),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: '匯出角色包',
                          icon: const Icon(Icons.upload_outlined),
                          color: BridgeDSColors.of(context).textPrimary,
                          iconSize: 18,
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          onPressed: onExport,
                        ),
                      ),
                    ),
                    // [P0-3 修復 2026-06-30] 可見的編輯入口，不依賴長按
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Material(
                        color: BridgeDSColors.of(
                          context,
                        ).canvas.withValues(alpha: 0.82),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: '編輯夥伴',
                          icon: const Icon(Icons.edit_outlined),
                          color: BridgeDSColors.of(context).textPrimary,
                          iconSize: 18,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: onEdit,
                        ),
                      ),
                    ),
                    if (companion.mbtiType != null)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          // [教練 Agent 2026-06-29] 放大角色圖，撐滿上下、縮小左右留白
                          final artSize = (constraints.maxHeight * 0.92).clamp(
                            200.0,
                            320.0,
                          );
                          // [小葵 2026-09-13] rig 分支封存（Blue 拍板回歸靜態圖）——重啟=恢復上面分支
                          // 角色卡預覽呼吸感（與懸浮窗/設定頁同一套呼吸語彙）
                          return BreathingImage(
  anchor: const Alignment(0, 0.15),  // 胸口呼吸
                            child: CompanionAvatarImage(
                              companion: companion,
                              mbtiCode: companion.mbtiCode,
                              seed: companion.appearanceSeed,
                              name: companion.name,
                              mood: isActive
                                  ? AgentCompanionMood.proud
                                  : AgentCompanionMood.idle,
                              action: isActive
                                  ? AgentCompanionAction.bouncing
                                  : AgentCompanionAction.standing,
                              size: artSize,
                              framed: false,
                            ),
                          );
                        },
                      )
                    else
                      _buildFallbackAvatar(context, color, 42),

                    // 狀態指示器
                    if (isActive)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: BridgeDSColors.of(context).accentBlue,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusXL,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt,
                                size: 12,
                                color: BridgeDSColors.of(context).textPrimary,
                              ),
                              SizedBox(width: 0),
                              Text(
                                '召喚中',
                                style: TierStyle.of(context, Tier.listItemMeta)
                                    .toTextStyle()
                                    .copyWith(
                                      color: BridgeDSColors.of(
                                        context,
                                      ).textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: BridgeDSColors.of(
                            context,
                          ).canvas.withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXL,
                          ),
                          border: Border.all(
                            color: BridgeDSColors.of(context).borderSubtle,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 12,
                              color: BridgeDSColors.of(context).accentBlue,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$assetCount',
                              style: TierStyle.of(context, Tier.listItemMeta)
                                  .toTextStyle()
                                  .copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: BridgeDSColors.of(
                                      context,
                                    ).textPrimary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 底部資訊
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      companion.name,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(
                            fontWeight: FontWeight.w600,
                            color: BridgeDSColors.of(context).textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          companion.mbtiCode,
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(
                                fontWeight: FontWeight.w600,
                                color: BridgeDSColors.of(context).textSecondary,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·',
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(
                                color: BridgeDSColors.of(context).textMuted,
                              ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${companion.mbtiType?.name ?? '自訂'}型',
                            style: TierStyle.of(context, Tier.cardCaption)
                                .toTextStyle()
                                .copyWith(
                                  color: BridgeDSColors.of(
                                    context,
                                  ).textSecondary,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _RightsPassportPill(
                      passport: companion.rightsPassport,
                      compact: true,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      companion.appearanceDescription.isEmpty
                          ? '點擊查看角色圖組與 Manifest'
                          : companion.appearanceDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                            height: 1.25,
                            color: BridgeDSColors.of(context).textMuted,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 13,
                          color: BridgeDSColors.of(context).accentBlue,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '查看角色卡',
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(
                                color: BridgeDSColors.of(context).accentBlue,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Spacer(),
                        Text(
                          '$assetCount assets',
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(
                                color: BridgeDSColors.of(context).textSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackAvatar(
    BuildContext context,
    Color color,
    double fontSize,
  ) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.6), color.withValues(alpha: 0.3)],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          companion.name.substring(0, 1),
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: BridgeDSColors.of(context).textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SemiDaoCertificationSummary extends StatelessWidget {
  final SemiDaoReviewCase reviewCase;

  const _SemiDaoCertificationSummary({required this.reviewCase});

  @override
  Widget build(BuildContext context) {
    final certification = reviewCase.certification;
    final rows = [
      for (final item in certification.passedChecks)
        (Icons.check_circle, BridgeDSColors.of(context).accentGreen, item),
      for (final item in certification.warningChecks)
        (Icons.warning_amber, BridgeDSColors.of(context).accentYellow, item),
      for (final item in certification.blockedChecks)
        (Icons.block, BridgeDSColors.of(context).accentRed, item),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: BridgeDSColors.of(context).borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CertificationCountChip(
                icon: Icons.check_circle_outline,
                label: '通過 ${certification.passedChecks.length}',
                color: BridgeDSColors.of(context).accentGreen,
              ),
              _CertificationCountChip(
                icon: Icons.warning_amber_outlined,
                label: '提醒 ${certification.warningChecks.length}',
                color: BridgeDSColors.of(context).accentYellow,
              ),
              _CertificationCountChip(
                icon: Icons.block_outlined,
                label: '封鎖 ${certification.blockedChecks.length}',
                color: BridgeDSColors.of(context).accentRed,
              ),
              _CertificationCountChip(
                icon: Icons.image_search_outlined,
                label:
                    '圖片 ${certification.visualReview?.inspectedImageCount ?? 0}',
                color: BridgeDSColors.of(context).accentBlue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (certification.requiredClarifications.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: BridgeDSColors.of(
                  context,
                ).accentYellow.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: BridgeDSColors.of(
                    context,
                  ).accentYellow.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '需要補充說明',
                    style: TextStyle(
                      color: BridgeDSColors.of(context).textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in certification.requiredClarifications)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '• $item',
                        style: TierStyle.of(context, Tier.cardCaption)
                            .toTextStyle()
                            .copyWith(
                              color: BridgeDSColors.of(context).textSecondary,
                              height: 1.35,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final row in rows.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(row.$1, color: row.$2, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.$3,
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(
                            color: BridgeDSColors.of(context).textSecondary,
                            height: 1.3,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

enum _SemiDaoReviewAction { stay, clarify, openPool }

class _CertificationCountChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _CertificationCountChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.10),
      side: BorderSide(color: color.withValues(alpha: 0.18)),
      labelStyle: TierStyle.of(
        context,
        Tier.cardCaption,
      ).toTextStyle().copyWith(color: color, fontWeight: FontWeight.w900),
    );
  }
}
