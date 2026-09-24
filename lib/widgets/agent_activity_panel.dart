import 'package:flutter/material.dart';

import '../models/agent_activity.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';

enum AgentActivityPanelDensity { full, compact }

class AgentActivityPanel extends StatelessWidget {
  final AgentActivityStage stage;
  final List<AgentActivityStage> stages;
  final AgentActivityTelemetry telemetry;
  final bool pulse;
  final AgentActivityPanelDensity density;
  final bool showPulseIndicator;

  const AgentActivityPanel({
    super.key,
    required this.stage,
    required this.telemetry,
    this.stages = agentActivityStages,
    this.pulse = false,
    this.density = AgentActivityPanelDensity.full,
    this.showPulseIndicator = true,
  });

  @override
  Widget build(BuildContext context) {
    if (density == AgentActivityPanelDensity.compact) {
      return _CompactActivityPanel(
        stage: stage,
        telemetry: telemetry,
        pulse: pulse,
        showPulseIndicator: showPulseIndicator,
      );
    }

    final currentIndex = stages.indexOf(stage);
    final glowAlpha = pulse ? 0.24 : 0.08;
    final borderAlpha = pulse ? 0.42 : 0.22;
    final statusColor = pulse ? BridgeDSColors.of(context).accentPurple : BridgeDSColors.of(context).textPrimary;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: AnimatedContainer(
        key: ValueKey(stage.label),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: BridgeDSColors.of(context).accentPurple.withValues(alpha: borderAlpha),
          ),
          boxShadow: [
            BoxShadow(
              color: BridgeDSColors.of(context).accentPurple.withValues(alpha: glowAlpha),
              blurRadius: pulse ? 24 : 12,
              spreadRadius: pulse ? 1 : 0,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: BridgeDSColors.of(context).accentPurple,
                    backgroundColor: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeInOut,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                      shadows: [
                        Shadow(
                          color: BridgeDSColors.of(context).accentPurple.withValues(
                            alpha: pulse ? 0.32 : 0,
                          ),
                          blurRadius: pulse ? 10 : 0,
                        ),
                      ],
                    ),
                    child: Text(stage.label),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                stage.detail,
                style: TextStyle(
                  fontSize: 14,
                  color: BridgeDSColors.of(context).textSecondary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _TelemetryStrip(stage: stage, telemetry: telemetry, pulse: pulse),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: stages.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final isActive = index == currentIndex;
                final isDone = index < currentIndex;
                final color = isActive
                    ? BridgeDSColors.of(context).accentPurple
                    : isDone
                    ? BridgeDS.successGreen
                    : BridgeDSColors.of(context).textMuted;

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: isActive ? 0.13 : 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(color: color.withValues(alpha: 0.28)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isDone ? Icons.check_circle : item.icon,
                        size: 13,
                        color: color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.shortLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactActivityPanel extends StatelessWidget {
  final AgentActivityStage stage;
  final AgentActivityTelemetry telemetry;
  final bool pulse;
  final bool showPulseIndicator;

  const _CompactActivityPanel({
    required this.stage,
    required this.telemetry,
    required this.pulse,
    required this.showPulseIndicator,
  });

  @override
  Widget build(BuildContext context) {
    final glowAlpha = pulse ? 0.20 : 0.06;
    final borderAlpha = pulse ? 0.38 : 0.18;
    final statusColor = pulse ? BridgeDSColors.of(context).accentPurple : BridgeDSColors.of(context).textPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: BridgeDSColors.of(context).accentPurple.withValues(alpha: borderAlpha),
        ),
        boxShadow: [
          BoxShadow(
            color: BridgeDSColors.of(context).accentPurple.withValues(alpha: glowAlpha),
            blurRadius: pulse ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: BridgeDSColors.of(context).accentPurple.withValues(alpha: pulse ? 0.16 : 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(stage.icon, size: 17, color: BridgeDSColors.of(context).accentPurple),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeInOut,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    height: 1.15,
                    shadows: [
                      Shadow(
                        color: BridgeDSColors.of(context).accentPurple.withValues(
                          alpha: pulse ? 0.28 : 0,
                        ),
                        blurRadius: pulse ? 8 : 0,
                      ),
                    ],
                  ),
                  child: Text(
                    stage.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _TelemetryCell(
                      label: '階段',
                      value: stage.shortLabel,
                      pulse: pulse,
                      compact: true,
                    ),
                    _TelemetryCell(
                      label: '上下文',
                      value: telemetry.messages.toString(),
                      pulse: pulse,
                      compact: true,
                    ),
                    _TelemetryCell(
                      label: '行動',
                      value: telemetry.bridgeActions.toString(),
                      pulse: pulse,
                      compact: true,
                    ),
                    _TelemetryCell(
                      label: '用量',
                      value: _formatMetric(telemetry.tokens),
                      pulse: pulse,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showPulseIndicator) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: BridgeDSColors.of(context).accentPurple,
                backgroundColor: BridgeDSColors.of(context).accentPurple.withValues(alpha: 0.12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TelemetryStrip extends StatelessWidget {
  final AgentActivityStage stage;
  final AgentActivityTelemetry telemetry;
  final bool pulse;

  const _TelemetryStrip({
    required this.stage,
    required this.telemetry,
    required this.pulse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).textPrimary.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: BridgeDSColors.of(context).accentPurple.withValues(alpha: pulse ? 0.24 : 0.14),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _TelemetryCell(label: '目前階段', value: stage.shortLabel, pulse: pulse),
          _TelemetryCell(
            label: '對話輪次',
            value: telemetry.messages.toString(),
            pulse: pulse,
          ),
          _TelemetryCell(
            label: '文字量',
            value: _formatMetric(telemetry.chars),
            pulse: pulse,
          ),
          _TelemetryCell(
            label: '記憶線索',
            value: telemetry.memories.toString(),
            pulse: pulse,
          ),
          _TelemetryCell(
            label: '橋樑行動',
            value: telemetry.bridgeActions.toString(),
            pulse: pulse,
          ),
          _TelemetryCell(
            label: '附件',
            value: telemetry.attachments.toString(),
            pulse: pulse,
          ),
          _TelemetryCell(
            label: '用量',
            value: _formatMetric(telemetry.tokens),
            pulse: pulse,
          ),
        ],
      ),
    );
  }
}

class _TelemetryCell extends StatelessWidget {
  final String label;
  final String value;
  final bool pulse;
  final bool compact;

  const _TelemetryCell({
    required this.label,
    required this.value,
    required this.pulse,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = pulse ? BridgeDSColors.of(context).accentPurple : AppTheme.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 7,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: BridgeDSColors.of(context).borderDefault.withValues(alpha: pulse ? 0.9 : 0.55),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            height: 1.15,
          ),
          children: [
            TextSpan(
              text: '$label=',
              style: TextStyle(
                color: BridgeDSColors.of(context).textMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(color: valueColor, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatMetric(int value) {
  if (value >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}m';
  }
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return value.toString();
}
