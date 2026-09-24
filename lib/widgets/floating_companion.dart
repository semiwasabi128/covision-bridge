// floating_companion.dart
// [教練 Agent 2026-08-11] 浮動夥伴——浮在整個畫面最頂層的透明背景夥伴
// 接上 CompanionRuntimeStore 即時狀態，忠實反映 Agent 動作
// 可拖曳移動位置，不擋住使用者操作

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/agent_activity.dart';
import '../models/companion.dart';
import '../models/companion_runtime.dart';
import '../services/agent_activity_store.dart';
import '../services/companion_runtime_store.dart';
import '../services/companion_store.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import 'bridge_cards/companion_status_helper.dart';
import 'companion_rig.dart';
import 'companion_rig_animator.dart';

/// 浮動夥伴——永遠浮在最頂層，透明背景，可拖曳
class FloatingCompanion extends StatefulWidget {
  const FloatingCompanion({super.key});

  @override
  State<FloatingCompanion> createState() => _FloatingCompanionState();
}

class _FloatingCompanionState extends State<FloatingCompanion> {
  // 夥伴位置——預設右下角（不擋左側 sidebar 和輸入框）
  Offset _position = const Offset(0, 0);
  bool _initialized = false;
  bool _dragging = false;

  // 夥伴尺寸
  static const double _size = 120;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CompanionRuntimeState>(
      valueListenable: CompanionRuntimeStore.instance.state,
      builder: (context, runtime, _) {
        return ValueListenableBuilder<AgentActivitySnapshot>(
          valueListenable: AgentActivityStore.instance.snapshot,
          builder: (context, snapshot, _) {
            final companion = CompanionStore().activeCompanion;
            if (companion == null) return const SizedBox.shrink();

            // 根據 stage 決定狀態圖
            final statusSpec = CompanionStatusHelper.statusSpecForRuntime(runtime);

            // 初始化位置——右下角
            if (!_initialized) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final screenSize = MediaQuery.of(context).size;
                if (!_initialized && mounted) {
                  setState(() {
                    _position = Offset(
                      screenSize.width - _size - 280, // 避開右側可能的側欄
                      screenSize.height - _size - 120, // 避開底部輸入框
                    );
                    _initialized = true;
                  });
                }
              });
            }

            return Positioned(
              left: _position.dx,
              top: _position.dy,
              child: GestureDetector(
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (details) {
                  setState(() {
                    _position += details.delta;
                    // 邊界限制——不讓夥伴跑出畫面
                    final screenSize = MediaQuery.of(context).size;
                    _position = Offset(
                      _position.dx.clamp(0.0, screenSize.width - _size),
                      _position.dy.clamp(50.0, screenSize.height - _size - 20),
                    );
                  });
                },
                onPanEnd: (_) => setState(() => _dragging = false),
                child: AnimatedOpacity(
                  opacity: _dragging ? 0.6 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: _buildCompanionLayer(companion, snapshot, statusSpec),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCompanionLayer(
    Companion companion,
    AgentActivitySnapshot snapshot,
    CompanionStatusSpec statusSpec,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: SizedBox(
        width: _size,
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 夥伴狀態圖（透明背景）
            _buildStatusImage(companion, statusSpec),

            // 狀態指示器——底部小標籤
            Positioned(
              bottom: -4,
              left: 0,
              right: 0,
              child: _buildStatusLabel(snapshot, statusSpec),
            ),

            // 拖曳提示（hover 時顯示）
            // 活躍脈動效果
            if (snapshot.active && snapshot.pulse)
              Positioned(
                top: -2,
                right: -2,
                child: _buildPulseIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusImage(Companion companion, CompanionStatusSpec spec) {
    // [小葵 2026-09-11] 活體 rig——有 rig 素材的夥伴（小橋/MimeMi…）走四層
    // 切圖程序動畫，狀態切換參數連續過渡；其他夥伴照舊走靜態狀態圖鏈。
    if (kRigByCompanion.containsKey(companion.name)) {
      return CompanionRigAnimator(
        companionName: companion.name,
        stateId: spec.id,
        size: _size,
      );
    }
    return CompanionStatusHelper.buildStatusPreviewImage(
      runtime: CompanionRuntimeStore.instance.state.value,
      companion: companion,
      spec: spec,
      size: _size,
    );
  }

  Widget _buildStatusLabel(AgentActivitySnapshot snapshot, CompanionStatusSpec spec) {
    // [小葵 2026-09-19 過程直播] 最新近況優先——沒有近況才退回 stage 短標籤
    final liveStatus = AgentActivityStore.instance.latestLoopStatus.value;
    final stageLabel = (snapshot.active && liveStatus != null && liveStatus.isNotEmpty)
        ? liveStatus
        : snapshot.stage.shortLabel;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: BridgeDSColors.of(context).surfaceElevated.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: snapshot.active
              ? BridgeDSColors.of(context).accentBlue.withValues(alpha: 0.3)
              : BridgeDSColors.of(context).borderSubtle,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 狀態圖示
          Icon(
            spec.icon,
            size: 11,
            color: snapshot.active
                ? BridgeDSColors.of(context).accentBlue
                : BridgeDSColors.of(context).textMuted,
          ),
          const SizedBox(width: 3),
          // 狀態文字
          Flexible(
            child: Text(
              snapshot.active ? '$stageLabel · ${spec.label}' : spec.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(
                fontSize: 10,
                color: snapshot.active
                    ? BridgeDSColors.of(context).textPrimary
                    : BridgeDSColors.of(context).textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseIndicator() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: const Duration(milliseconds: 850),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: BridgeDSColors.of(context).accentGreen.withValues(alpha: value),
          ),
        );
      },
    );
  }
}
