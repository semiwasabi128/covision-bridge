// layer_card.dart
// Sprint 6 — 七層獨立顯示卡片
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 每張卡片顯示一層的：
// - 標題（層名）
// - value（enum 或主要欄位）
// - source chip（ai/rule/mixed/cached，點擊可 override）
// - confidence 進度條
// - evidence 摺疊文字
// - 若有 GuidanceHint 附加欄位也展開

import 'package:flutter/material.dart';

import '../../models/transurfing_brain.dart';
import '../../services/brain_pipeline/layer_result.dart';
import '../../theme/app_theme.dart';
import 'layer_source_chip.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 七層定義
enum BrainLayerId {
  intent('意圖', 'intent', Icons.lightbulb_outline),
  attention('注意力', 'attention', Icons.visibility_outlined),
  pendulum('擺錘', 'pendulum', Icons.sensors_outlined),
  importance('重要性', 'importance', Icons.speed_outlined),
  heartMind('心腦', 'heartMind', Icons.favorite_outline),
  fraile('頻率', 'fraile', Icons.graphic_eq_outlined),
  doorFlow('門與流', 'doorFlow', Icons.door_front_door_outlined),
  actionRouter('行動路由', 'actionRouter', Icons.assistant_direction_outlined);

  final String displayName;
  final String key;
  final IconData icon;
  const BrainLayerId(this.displayName, this.key, this.icon);
}

class LayerCard extends StatelessWidget {
  final BrainLayerId layerId;
  final LayerResult<dynamic> layerResult;
  final BrainReflection reflection;
  final LayerOverrideMode? overrideMode;
  final VoidCallback? onSourceToggle;

  const LayerCard({
    super.key,
    required this.layerId,
    required this.layerResult,
    required this.reflection,
    this.overrideMode,
    this.onSourceToggle,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = _valueText();
    final confidence = layerResult.confidence.clamp(0.0, 1.0);
    final hasEvidence = layerResult.evidence.trim().isNotEmpty;
    final hintEntries = _hintEntries();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: _sourceBorderColor(layerResult.source).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: icon + layer name + source chip
          Row(
            children: [
              Icon(layerId.icon, size: 14, color: BridgeDSColors.of(context).accentPurple),
              const SizedBox(width: 5),
              Text(
                layerId.displayName,
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w800,
                  color: BridgeDSColors.of(context).textPrimary,),
              ),
              const Spacer(),
              LayerSourceChip(
                source: layerResult.source,
                overrideMode: overrideMode,
                onToggle: onSourceToggle,
              ),
            ],
          ),
          const SizedBox(height: 5),
          // Row 2: value text
          Text(
            valueText,
            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
              color: BridgeDSColors.of(context).textPrimary,),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // Row 3: confidence bar
          if (layerResult.source != LayerSource.rule) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: confidence,
                minHeight: 3,
                backgroundColor: BridgeDSColors.of(context).borderDefault,
                valueColor: AlwaysStoppedAnimation(_sourceColor(layerResult.source)),
              ),
            ),
          ],
          // Row 4: evidence (collapsible)
          if (hasEvidence) ...[
            const SizedBox(height: 4),
            _EvidenceText(
              evidence: layerResult.evidence,
              latencyMs: layerResult.latencyMs,
            ),
          ],
          // Row 5: hint entries (if any)
          if (hintEntries.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...hintEntries.map((e) => _HintLine(label: e.$1, value: e.$2)),
          ],
        ],
      ),
    );
  }

  /// 根據層 ID 從 BrainReflection 取值文字
  String _valueText() {
    return switch (layerId) {
      BrainLayerId.intent => reflection.userIntent,
      BrainLayerId.attention => _attentionLabel(reflection.attentionState),
      BrainLayerId.pendulum => reflection.pendulumSignals.isEmpty
          ? '無擺錘'
          : reflection.pendulumSignals.map((s) => s.label).join('、'),
      BrainLayerId.importance => _importanceLabel(reflection.importanceLevel),
      BrainLayerId.heartMind => _heartMindLabel(reflection.heartMindAlignment),
      BrainLayerId.fraile => _fraileLabel(reflection.fraileResonance),
      BrainLayerId.doorFlow =>
        reflection.doorCandidates.isEmpty ? '無門' : '${reflection.doorCandidates.length} 扇門 · ${_flowLabel(reflection.flowState)}',
      BrainLayerId.actionRouter => _moveLabel(reflection.recommendedMove),
    };
  }

  /// 從 metadata 提取 hint 條目
  List<(String, String)> _hintEntries() {
    final m = layerResult.metadata;
    if (m.isEmpty) return const [];
    final entries = <(String, String)>[];
    // importance 層
    if (m['humorHint'] != null) {
      entries.add(('幽默化解', m['humorHint'].toString()));
    }
    // heartMind 層
    if (m['mindStatement'] != null) {
      entries.add(('心智', m['mindStatement'].toString()));
    }
    if (m['heartStatement'] != null) {
      entries.add(('心', m['heartStatement'].toString()));
    }
    if (m['integrationPrompt'] != null) {
      entries.add(('引導', m['integrationPrompt'].toString()));
    }
    // fraile 層
    if (m['fraileEvidence'] != null) {
      entries.add(('頻率依據', m['fraileEvidence'].toString()));
    }
    return entries;
  }

  Color _sourceColor(LayerSource s) {
    return switch (s) {
      LayerSource.ai => AppTheme.secondary,
      LayerSource.rule => BridgeDS.textMuted,
      LayerSource.mixed => BridgeDS.accentPurple,
      LayerSource.cached => BridgeDS.textSecondary,
    };
  }

  Color _sourceBorderColor(LayerSource s) => _sourceColor(s);
}

class _EvidenceText extends StatefulWidget {
  final String evidence;
  final int latencyMs;

  const _EvidenceText({required this.evidence, required this.latencyMs});

  @override
  State<_EvidenceText> createState() => _EvidenceTextState();
}

class _EvidenceTextState extends State<_EvidenceText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.background.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 12,
                  color: BridgeDSColors.of(context).textMuted,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    _expanded ? widget.evidence : widget.evidence,
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                      height: 1.3,),
                  ),
                ),
                if (widget.latencyMs > 0)
                  Text(
                    '${widget.latencyMs}ms',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HintLine extends StatelessWidget {
  final String label;
  final String value;

  const _HintLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.secondary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              label,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(fontWeight: FontWeight.w700,
                color: AppTheme.secondary,),
            ),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              value,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textSecondary,
                height: 1.3,),
            ),
          ),
        ],
      ),
    );
  }
}

// === Label helpers ===

String _attentionLabel(AttentionState s) {
  return switch (s) {
    AttentionState.clear => '清醒',
    AttentionState.captured => '被捕獲',
    AttentionState.scattered => '分散',
  };
}

String _importanceLabel(ImportanceLevel l) {
  return switch (l) {
    ImportanceLevel.low => '偏低',
    ImportanceLevel.balanced => '平衡',
    ImportanceLevel.elevated => '升高',
    ImportanceLevel.excessive => '過度',
  };
}

String _heartMindLabel(HeartMindAlignment a) {
  return switch (a) {
    HeartMindAlignment.aligned => '一致',
    HeartMindAlignment.mixed => '混合',
    HeartMindAlignment.conflicted => '衝突',
    HeartMindAlignment.unknown => '未知',
  };
}

String _fraileLabel(FraileResonance r) {
  return switch (r) {
    FraileResonance.strong => '強',
    FraileResonance.present => '在線',
    FraileResonance.weak => '弱',
    FraileResonance.obscured => '模糊',
  };
}

String _flowLabel(FlowState f) {
  return switch (f) {
    FlowState.withFlow => '順流',
    FlowState.againstFlow => '逆流',
    FlowState.stalled => '停滯',
    FlowState.unknown => '未知',
  };
}

String _moveLabel(RecommendedMove m) {
  return switch (m) {
    RecommendedMove.answerDirectly => '直接回答',
    RecommendedMove.askClarifyingQuestion => '釐清提問',
    RecommendedMove.reduceImportance => '降低重要性',
    RecommendedMove.convertToOutput => '轉為輸出',
    RecommendedMove.takeNextAction => '下一步行動',
    RecommendedMove.routeBridge => '接橋',
    RecommendedMove.declareIntention => '宣告意圖',
    RecommendedMove.recordWaterAction => '記錄行動',
  };
}
