// system_routine_overlay.dart
// [刀 5 延伸 SR.3 2026-09-09] 全電腦示範錄製面板——錄製中的指揮台。
//
// loop 鐵則：錄製中恆亮紅點＋事件即時滾動——Blue 全程看得到它在錄什麼。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bridge_app/services/routines/system_routine_recorder.dart';
import 'package:bridge_app/services/routines/system_routine_store.dart';
import 'package:bridge_app/services/routines/system_routine_player.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

class SystemRoutineOverlay {
  static OverlayEntry? _entry;

  static void toggle(BuildContext context) {
    if (_entry != null) {
      close();
    } else {
      open(context);
    }
  }

  static void open(BuildContext context) {
    if (_entry != null) return;
    _entry = OverlayEntry(builder: (_) => const _RoutinePanel());
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void close() {
    _entry?.remove();
    _entry = null;
  }
}

class _RoutinePanel extends StatefulWidget {
  const _RoutinePanel();

  @override
  State<_RoutinePanel> createState() => _RoutinePanelState();
}

class _RoutinePanelState extends State<_RoutinePanel> {
  Timer? _refresh;
  bool _recording = false;
  List<String> _story = [];

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final r = SystemRoutineRecorder.instance;
      if (r.isRecording != _recording ||
          r.story.length != _story.length) {
        setState(() {
          _recording = r.isRecording;
          _story = r.story;
        });
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _toggleRecord() async {
    final r = SystemRoutineRecorder.instance;
    if (r.isRecording) {
      final events = await r.stop();
      setState(() {
        _recording = false;
        _story = r.story;
      });
      // [P2.4] 停止後存檔對話框
      if (events != null && events.isNotEmpty) {
        await _showSaveDialog(events);
      }
    } else {
      await r.start();
      setState(() {
        _recording = r.isRecording;
        _story = r.story;
      });
    }
  }

  Future<void> _showSaveDialog(List<dynamic> events) async {
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dctx).surface,
        title: const Text('儲存示範 routine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('錄到 ${events.length} 個操作'),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'routine 名稱'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('放棄'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('儲存'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final routine = SystemRoutineStore.instance.fromRecorder(
      nameCtrl.text.trim().isEmpty
          ? '示範 ${DateTime.now().month}/${DateTime.now().day}'
          : nameCtrl.text.trim(),
      events.cast(),
    );
    await SystemRoutineStore.instance.save(routine);
    if (mounted) setState(() {}); // 列表刷新
  }

  Future<void> _replayRoutine(SavedRoutine routine) async {
    // 確認對話框（重播會動真的電腦——必須明示）
    final go = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dctx).surface,
        title: Text('重播「${routine.name}」？'),
        content: Text(
            '將重現 ${routine.stepCount} 個操作（agent 會動你的電腦）。\n'
            '錄製中按住 Esc 1.5 秒隨時急停。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: const Text('開始重播'),
          ),
        ],
      ),
    );
    if (go != true) return;

    final result = await SystemRoutinePlayer.instance.replay(routine.events);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('重播完成：${result.played} 步執行、${result.skipped} 步跳過')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Positioned(
      right: 20,
      bottom: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 340,
          constraints: const BoxConstraints(maxHeight: 420),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ds.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _recording ? ds.accentRed : ds.borderDefault,
              width: _recording ? 1.5 : 1,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 16)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_recording)
                    const _PulsingDot()
                  else
                    Icon(Icons.fiber_manual_record,
                        size: 14, color: ds.textMuted),
                  const SizedBox(width: 8),
                  Text(
                    _recording ? '全電腦錄製中' : '示範錄製（全電腦）',
                    style: TierStyle.of(context, Tier.cardCaptionBold)
                        .toTextStyle(),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: SystemRoutineOverlay.close,
                    child: Icon(Icons.close, size: 16, color: ds.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_recording)
                Text(
                  '正在錄你的所有點擊/按鍵——密碼框自動遮罩',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.textMuted),
                ),
              const SizedBox(height: 8),
              // 即時事件故事
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  decoration: BoxDecoration(
                    color: ds.canvas,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _story.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              _recording ? '等待第一個操作…' : '按下方開始錄製',
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()
                                  .copyWith(color: ds.textMuted),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _story.length,
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            child: Text(
                              '${i + 1}. ${_story[_story.length - 1 - i]}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle(),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _toggleRecord,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            _recording ? ds.accentRed : ds.accentBlue,
                      ),
                      icon: Icon(
                        _recording ? Icons.stop : Icons.fiber_manual_record,
                        size: 16,
                      ),
                      label: Text(
                        _recording ? '停止並存檔' : '開始錄製',
                        style: TierStyle.of(context, Tier.buttonPrimary)
                            .toTextStyle(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // [P2.4] 已存 routine 列表——一鍵重播
              FutureBuilder<List<SavedRoutine>>(
                future: SystemRoutineStore.instance.list(),
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final routines = snap.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('已存 routine（${routines.length}）',
                          style: TierStyle.of(context, Tier.cardCaptionBold)
                              .toTextStyle()
                              .copyWith(color: ds.textMuted)),
                      const SizedBox(height: 6),
                      ...routines.take(5).map((r) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.play_circle_outline,
                                    size: 16, color: ds.textMuted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${r.name} · ${r.stepCount} 步',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TierStyle.of(context,
                                            Tier.cardCaption)
                                        .toTextStyle(),
                                  ),
                                ),
                                InkWell(
                                  onTap: () => _replayRoutine(r),
                                  child: Text('重播',
                                      style: TierStyle.of(context,
                                              Tier.cardCaptionBold)
                                          .toTextStyle()
                                          .copyWith(color: ds.accentBlue)),
                                ),
                                const SizedBox(width: 10),
                                InkWell(
                                  onTap: () async {
                                    await SystemRoutineStore.instance
                                        .delete(r.id);
                                    if (mounted) setState(() {});
                                  },
                                  child: Text('刪除',
                                      style: TierStyle.of(context,
                                              Tier.cardCaption)
                                          .toTextStyle()
                                          .copyWith(color: ds.textMuted)),
                                ),
                              ],
                            ),
                          )),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot();

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return FadeTransition(
      opacity: Tween(begin: 0.3, end: 1.0)
          .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: Container(
        width: 12,
        height: 12,
        decoration:
            BoxDecoration(color: ds.accentRed, shape: BoxShape.circle),
      ),
    );
  }
}
