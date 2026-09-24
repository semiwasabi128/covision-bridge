/// 自訂調用原則確認對話框
///
/// 使用者透過自然語言描述需求後，PolicyGenerator 生成草稿，
/// 本對話框顯示具體改動項目讓使用者確認後啟用。
///
/// 流程（設計文件 §C.3-C.6）：
/// 1. 顯示草稿內容（名稱、說明、套用對象、改動項目）
/// 2. 使用者確認 → createPolicy + activatePolicy
/// 3. 顯示「已生效」一次，不再干擾
///
/// [教練 Agent 2026-07-30 Phase 4]
library;

import 'package:flutter/material.dart';
import '../services/agent_loop/custom_routing_policy.dart';
import '../services/agent_loop/agent_profile_store.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class PolicyConfirmDialog extends StatefulWidget {
  final CustomRoutingPolicy draft;

  const PolicyConfirmDialog({super.key, required this.draft});

  /// 顯示對話框的便捷方法
  /// 回傳 true = 使用者確認啟用；false / null = 取消
  static Future<bool?> show(BuildContext context, CustomRoutingPolicy draft) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PolicyConfirmDialog(draft: draft),
    );
  }

  @override
  State<PolicyConfirmDialog> createState() => _PolicyConfirmDialogState();
}

class _PolicyConfirmDialogState extends State<PolicyConfirmDialog> {
  bool _activating = false;
  bool _activated = false;

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final draft = widget.draft;

    return AlertDialog(
      backgroundColor: ds.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: ds.borderDefault),
      ),
      title: Row(
        children: [
          Icon(Icons.tune_rounded, color: ds.accentPurple, size: 24),
          const SizedBox(width: 8),
          Text(
            '自訂調用原則',
            style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.w900,
              color: ds.textPrimary,),
          ),
        ],
      ),
      content: _activated ? _buildActivatedContent(ds) : _buildDraftContent(ds, draft),
      actions: _activated
          ? [_buildCloseButton(ds)]
          : [_buildCancelButton(ds), _buildConfirmButton(ds)],
    );
  }

  // ── 共用 ──

  Widget _buildInfoRow(BridgeDSColors ds, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: ds.textTertiary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textTertiary)),
              const SizedBox(height: 2),
              Text(value,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary)),
            ],
          ),
        ),
      ],
    );
  }

  // ── 草稿內容 ──

  Widget _buildDraftContent(BridgeDSColors ds, CustomRoutingPolicy draft) {
    final overrides = draft.overrides;
    final modelLabel = draft.model ?? '全部模型';

    return SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名稱
          _buildInfoRow(ds, Icons.label_outline, '名稱', draft.name),
          const SizedBox(height: 12),

          // 說明
          if (draft.description.isNotEmpty) ...[
            _buildInfoRow(ds, Icons.description_outlined, '說明', draft.description),
            const SizedBox(height: 12),
          ],

          // 套用對象
          _buildInfoRow(ds, Icons.gps_fixed, '套用對象', '${draft.provider} / $modelLabel'),
          const SizedBox(height: 16),

          // 改動項目
          Text(
            '改動項目',
            style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
              color: ds.textSecondary,),
          ),
          const SizedBox(height: 8),
          ..._buildOverrideChips(ds, overrides),

          const SizedBox(height: 16),
          // 警告
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ds.tagWarnBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: ds.tagWarnFg, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '一旦啟用，內建的 ${draft.provider} 調用模式會自動棄用。',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.tagWarnFg),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildOverrideChips(BridgeDSColors ds, Map<String, dynamic> overrides) {
    final chips = <Widget>[];
    for (final entry in overrides.entries) {
      final label = _overrideLabel(entry.key);
      final value = _formatOverrideValue(entry.key, entry.value);
      chips.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Chip(
          label: Text('$label: $value',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary)),
          backgroundColor: ds.tagInfoBg,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
        ),
      ));
    }
    if (chips.isEmpty) {
      chips.add(Text('（無覆寫欄位）',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textTertiary)));
    }
    return chips;
  }

  String _overrideLabel(String key) {
    switch (key) {
      case 'maxTurns': return '最大輪數';
      case 'taskChunkSize': return '任務拆分';
      case 'tier': return '能力分層';
      case 'apiParams': return 'API 參數';
      case 'promptNudge': return '提示語';
      case 'forceToolUse': return '工具使用';
      default: return key;
    }
  }

  String _formatOverrideValue(String key, dynamic value) {
    if (key == 'apiParams' && value is Map) {
      return '${value.keys.join(', ')}';
    }
    return value.toString();
  }

  // ── 已生效內容 ──

  Widget _buildActivatedContent(BridgeDSColors ds) {
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: ds.accentGreen, size: 48),
          const SizedBox(height: 16),
          Text(
            '已生效',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: ds.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.draft.name} 已啟用，內建調用模式已自動棄用。',
            textAlign: TextAlign.center,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary),
          ),
        ],
      ),
    );
  }

  // ── 按鈕 ──

  Widget _buildCancelButton(BridgeDSColors ds) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(false),
      child: Text('取消', style: TextStyle(color: ds.textSecondary)),
    );
  }

  Widget _buildConfirmButton(BridgeDSColors ds) {
    return FilledButton.icon(
      onPressed: _activating ? null : _onConfirm,
      icon: _activating
          ? SizedBox(width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: ds.canvas))
          : Icon(Icons.power_settings_new, size: 18),
      label: Text(_activating ? '啟用中…' : '確認並啟用'),
      style: FilledButton.styleFrom(
        backgroundColor: ds.accentPurple,
        foregroundColor: ds.canvas,
      ),
    );
  }

  Widget _buildCloseButton(BridgeDSColors ds) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(true),
      child: Text('關閉', style: TextStyle(color: ds.textPrimary)),
    );
  }

  // ── 確認啟用 ──

  Future<void> _onConfirm() async {
    setState(() => _activating = true);
    try {
      final store = ProviderProfileStore.instance;
      await store.createPolicy(widget.draft);
      await store.activatePolicy(widget.draft.id);
      setState(() {
        _activating = false;
        _activated = true;
      });
    } catch (e) {
      setState(() => _activating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('啟用失敗：$e'),
              backgroundColor: BridgeDSColors.of(context).accentRed),
        );
      }
    }
  }
}
