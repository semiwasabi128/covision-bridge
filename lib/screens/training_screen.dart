// training_screen.dart
// [Blue 拍板 2026-09-12] 訓練AI夥伴——示範錄製的正式家。
//
// 「名稱『訓練AI夥伴』，唯一入口在首頁進入，進入後頁面先有一段簡單說明
//  與播放一段操作示範，用預錄的滑鼠動作與文字說明泡泡，
//  用畫面演示『錄製操作流程』」
//
// [Blue 規格升級 2026-09-12] 示範動畫要「視覺感受上像真點擊、真操作、
// 真系統反應、真存檔」——假游標點下去，畫面裡的按鈕真的被按下、
// 錄製故事真的進帳、存檔對話框真的彈出、招式真的出現在列表。
// 每個步驟泡泡＝用意說明＋小 Tips。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bridge_app/services/routines/system_routine_recorder.dart';
import 'package:bridge_app/services/routines/system_routine_store.dart';
import 'package:bridge_app/services/routines/system_routine_player.dart';
import 'package:bridge_app/services/routines/move_intent_clarifier.dart'; // [Blue 拍板] 意圖釐清
import 'package:bridge_app/services/routines/move_memory_bridge.dart'; // [Blue 令] 招式入記憶
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:bridge_app/theme/tier.dart';
import 'package:bridge_app/theme/tier_style.dart';

class TrainingScreen extends StatefulWidget {
  final VoidCallback onBack;
  const TrainingScreen({super.key, required this.onBack});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                IconButton(
                    onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
                const SizedBox(width: 8),
                Icon(Icons.school_outlined, color: ds.accentPurple, size: 28),
                const SizedBox(width: 12),
                Text('訓練AI夥伴',
                    style:
                        TierStyle.of(context, Tier.appDisplayLarge).toTextStyle()),
              ]),
              const SizedBox(height: 8),
              Text('你做一遍，夥伴學會，以後換它做——訓練涵蓋整台電腦的操作流程',
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: ds.textMuted)),
              const SizedBox(height: 32),
              Row(children: [
                Expanded(
                    child: _stepCard(context, '1', Icons.fiber_manual_record,
                        ds.accentRed, '你示範', '按下錄製，去任何 App 操作一遍——點按鈕、打字、滾動都算')),
                const SizedBox(width: 16),
                Expanded(
                    child: _stepCard(context, '2', Icons.psychology_outlined,
                        ds.accentBlue, '橋樑記住', '每個動作變成結構化步驟：哪個 App、哪個按鈕、什麼順序')),
                const SizedBox(width: 16),
                Expanded(
                    child: _stepCard(context, '3', Icons.smart_toy_outlined,
                        ds.accentGreen, '夥伴代操作', '之後喊一聲，夥伴照步驟代你操作——沒接 MCP 的軟體也行')),
              ]),
              const SizedBox(height: 32),
              Text('操作示範',
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
              const SizedBox(height: 8),
              Text('注意看：游標點下去，系統真的反應——按鈕被按、故事進帳、存檔、招式出現，跟真的一樣',
                  style: TierStyle.of(context, Tier.cardCaption)
                      .toTextStyle()
                      .copyWith(color: ds.textMuted)),
              const SizedBox(height: 12),
              const _DemoPlayer(),
              const SizedBox(height: 32),
              const _PracticeSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepCard(BuildContext context, String num, IconData icon,
      Color color, String title, String desc) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 8),
            Text('步驟 $num',
                style: TierStyle.of(context, Tier.cardCaptionBold)
                    .toTextStyle()
                    .copyWith(color: color)),
          ]),
          const SizedBox(height: 10),
          Text(title,
              style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle()),
          const SizedBox(height: 6),
          Text(desc,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textSecondary)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════
// DemoPlayer——模擬真實流程的示範動畫
// [Blue 規格升級] 假游標＋真反應：點了按鈕真的被按、
// 錄製故事真的進帳、存檔對話框真的彈、招式真的出現
// ════════════════════════════════════════════════════

class _DemoPlayer extends StatefulWidget {
  const _DemoPlayer();

  @override
  State<_DemoPlayer> createState() => _DemoPlayerState();
}

class _DemoPlayerState extends State<_DemoPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  // ── 模擬系統狀態（游標的「點擊」會真的改變這些）──
  bool _recording = false;
  bool _cartAdded = false; // 購物車按鈕按下後 → ✓ 已加入
  bool _cartPressed = false; // 按下瞬間的視覺
  String _typed = ''; // 備忘錄打字動畫
  final List<String> _story = []; // 錄製故事（真的進帳）
  bool _showSaveDialog = false; // 存檔對話框真的彈出
  bool _saved = false; // 招式真的出現在列表
  int _savedSteps = 0;

  // ── 動畫狀態 ──
  Offset _from = const Offset(0.10, 0.5);
  Offset _to = const Offset(0.10, 0.5);
  bool _bubbleVisible = false;
  String _bubbleTitle = '';
  String _bubbleTip = '';
  bool _disposed = false;

  // 幾何：跟 build 裡畫的視窗同一組公式（游標才會真的落在按鈕上）
  static Offset _recordBtn(double w, double h) => Offset(w * 0.50, h - 28);
  static Offset _cartBtn(double w, double h) => Offset(w * 0.29, h * 0.44);
  static Offset _notesField(double w, double h) => Offset(w * 0.75, h * 0.33);

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void dispose() {
    _disposed = true;
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _wait(int ms) async =>
      Future.delayed(Duration(milliseconds: ms));

  /// 游標移到目標（帶緩動）——回傳後視為「到達」
  Future<void> _moveTo(Offset target, int ms) async {
    if (_disposed) return;
    setState(() {
      _from = _to;
      _to = target;
      _bubbleVisible = false;
    });
    _ctrl.duration = Duration(milliseconds: ms);
    _ctrl.forward(from: 0);
    await _wait(ms);
  }

  /// 彈出說明泡泡（用意＋小 Tips）
  void _bubble(String title, String tip) {
    if (_disposed) return;
    setState(() {
      _bubbleTitle = title;
      _bubbleTip = tip;
      _bubbleVisible = true;
    });
  }

  Future<void> _play() async {
    // 開場：讓畫面先靜置一下
    await _wait(800);
    while (!_disposed) {
      // ── ① 點「開始錄製」──
      await _moveTo(Offset(430, 312), 900);
      _bubble('① 游標移到「開始錄製」，點下去',
          '💡 雙軌設計：一軌錄「結構化步驟」（給夥伴精準重播），'
          '一軌生「操作故事」（給你看懂它記了什麼）——不是螢幕影片');
      await _wait(500);
      if (_disposed) return;
      setState(() => _recording = true); // 真反應：紅點亮起
      await _wait(1600);

      // ── ② 去購物網站點「加入購物車」──
      await _moveTo(_cartBtnOf(), 1000);
      _bubble('② 你去任何 App 操作——這裡點了「加入購物車」',
          '💡 噪音過濾：只有「誕生與改變」才算教材——工具切換、'
          '節點選取、視窗拖動全部自動忽略，招式乾乾淨淨');
      if (_disposed) return;
      setState(() => _cartPressed = true);
      await _wait(250);
      if (_disposed) return;
      setState(() {
        _cartPressed = false;
        _cartAdded = true; // 真反應：按鈕變「✓ 已加入」
        _story.add('在 購物網站 點了「加入購物車」'); // 真反應：故事進帳
      });
      await _wait(2000);

      // ── ③ 在備忘錄打字 ──
      await _moveTo(_notesFieldOf(), 1000);
      _bubble('③ 打字也是招式——在備忘錄輸入文字',
          '💡 信任層：密碼框自動遮罩成 **** 且絕不重播；'
          '輸入只留前 30 字；一切全程本地，不上雲不進訓練');
      const text = '鹿角蕨澆水提醒';
      for (final ch in text.split('')) {
        if (_disposed) return;
        setState(() => _typed += ch); // 真反應：逐字打字
        await _wait(120);
      }
      await _wait(300);
      if (_disposed) return;
      setState(() => _story.add('在 備忘錄 輸入了「鹿角蕨澆水提醒」'));
      await _wait(1400);

      // ── ④ 點「停止並存檔」──
      await _moveTo(_recordBtnOf(), 900);
      _bubble('④ 點「停止並存檔」——教學完成',
          '💡 AX 錨點：招式記的是「App+按鈕身分」不是座標——'
          '視窗換位置照樣找得到；找不到才退座標，都失敗誠實跳過');
      await _wait(500);
      if (_disposed) return;
      setState(() {
        _recording = false; // 真反應：紅點熄滅
        _showSaveDialog = true; // 真反應：存檔對話框彈出
      });
      await _wait(2200);
      if (_disposed) return;
      setState(() {
        _showSaveDialog = false;
        _saved = true; // 真反應：招式出現在列表
        _savedSteps = _story.length;
      });

      // ── ⑤ 收尾 ──
      await _moveTo(const Offset(0.9, 0.5), 900);
      _bubble('⑤ 招式存好了！之後對夥伴喊一聲就能照做',
          '💡 信任三閘：使出前 Agent 先問清你的目標（可能組合招）；'
          '動手前再確認；執行中按住 Esc 1.5 秒隨時急停');
      await _wait(3200);

      // ── 重置，循環 ──
      if (_disposed) return;
      setState(() {
        _recording = false;
        _cartAdded = false;
        _typed = '';
        _story.clear();
        _saved = false;
        _bubbleVisible = false;
        _from = const Offset(0.10, 0.5);
        _to = const Offset(0.10, 0.5);
      });
      await _wait(800);
    }
  }

  // 幾何 helper（build 前 size 未知，用 approx 常數——與視覺元素位置一致）
  Offset _recordBtnOf() => _recordBtn(860, 340);
  Offset _cartBtnOf() => _cartBtn(860, 340);
  Offset _notesFieldOf() => _notesField(860, 340);

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      height: 340,
      decoration: BoxDecoration(
        color: ds.canvas,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ds.borderDefault),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(builder: (context, size) {
          final w = size.maxWidth, h = size.maxHeight;
          // 游標位置 = from→to 緩動插值
          final t = Curves.easeInOutCubic.transform(_ctrl.value);
          final pos = Offset.lerp(_from, _to, t) ?? _to;
          final arrived = _ctrl.value > 0.92;

          return Stack(children: [
            // ── 🛒 購物網站視窗 ──
            Positioned(
              left: w * 0.12,
              top: h * 0.14,
              width: w * 0.34,
              height: h * 0.46,
              child: _demoWindow(
                ds, '🛒 購物網站',
                child: Column(children: [
                  const Spacer(),
                  // 加入購物車按鈕（游標點了會真的變化）
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 130,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _cartAdded ? ds.accentGreen : ds.accentBlue,
                      borderRadius: BorderRadius.circular(8),
                      border: _cartPressed
                          ? Border.all(color: ds.textPrimary, width: 2)
                          : null,
                    ),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (_cartAdded) ...[
                        Icon(Icons.check, size: 14, color: ds.canvas),
                        const SizedBox(width: 4),
                      ],
                      Text(_cartAdded ? '已加入' : '加入購物車',
                          style: TierStyle.of(context, Tier.cardCaptionBold)
                              .toTextStyle()),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ]),
              ),
            ),

            // ── 📝 備忘錄視窗 ──
            Positioned(
              right: w * 0.10,
              top: h * 0.16,
              width: w * 0.30,
              height: h * 0.40,
              child: _demoWindow(
                ds, '📝 備忘錄',
                child: Column(children: [
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Container(
                      height: 30,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: ds.canvas,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: ds.borderDefault),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                            _typed.isEmpty ? '輸入文字…' : _typed,
                            style: TierStyle.of(context, Tier.cardCaption)
                                .toTextStyle()
                                .copyWith(
                                    color: _typed.isEmpty ? ds.textMuted : null),
                          ),
                        ),
                        if (_typed.isNotEmpty)
          const SizedBox.shrink(),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),

            // ── 錄製故事面板（左上——真的進帳）──
            Positioned(
              left: 12,
              top: 12,
              width: 230,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ds.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _recording
                          ? ds.accentRed.withValues(alpha: 0.6)
                          : ds.borderDefault),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                        _recording
                            ? Icons.fiber_manual_record
                            : Icons.fiber_manual_record_outlined,
                        size: 12,
                        color: _recording ? ds.accentRed : ds.textMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _recording ? '錄製中 · ${_story.length} 步' : '尚未錄製',
                        style: TierStyle.of(context, Tier.cardCaptionBold)
                            .toTextStyle()
                            .copyWith(color: _recording ? ds.accentRed : ds.textMuted),
                      ),
                    ]),
                    if (_story.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      for (final s in _story.reversed.take(3))
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text('· $s',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TierStyle.of(context, Tier.cardCaption)
                                  .toTextStyle()),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            // ── 已存招式卡（右下——存檔後真的出現）──
            if (_saved)
              Positioned(
                right: 12,
                bottom: 70,
                child: AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 400),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ds.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ds.accentGreen.withValues(alpha: 0.5)),
                    ),
                    child: Row(children: [
                      Icon(Icons.check_circle, size: 16, color: ds.accentGreen),
                      const SizedBox(width: 6),
                      Text('招式「鹿角蕨購物示範 · $_savedSteps 步」已存入招式庫',
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()),
                    ]),
                  ),
                ),
              ),

            // ── 底部錄製控制列（按鈕在游標點擊時真的變化）──
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                height: 56,
                color: ds.surface.withValues(alpha: 0.95),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  // 錄製/停止鈕（示範的點擊目標）
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _recording ? ds.accentRed : ds.accentBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(
                        _recording ? Icons.stop : Icons.fiber_manual_record,
                        size: 14, color: ds.canvas,
                      ),
                      const SizedBox(width: 6),
                      Text(_recording ? '停止並存檔' : '開始錄製',
                          style: TierStyle.of(context, Tier.cardCaptionBold)
                              .toTextStyle()
                              .copyWith(color: ds.canvas)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Text('錄製控制列',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: ds.textMuted)),
                  const Spacer(),
                  Icon(Icons.lock_outline, size: 12, color: ds.textMuted),
                  const SizedBox(width: 4),
                  Text('密碼自動遮罩',
                      style: TierStyle.of(context, Tier.cardCaption)
                          .toTextStyle()
                          .copyWith(color: ds.textMuted)),
                ]),
              ),
            ),

            // ── 存檔對話框（停止後真的彈出）──
            if (_showSaveDialog)
              Positioned(
                left: w * 0.5 - 170,
                top: h * 0.24,
                child: Container(
                  width: 340,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: ds.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ds.borderDefault),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 20)
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('儲存招式',
                          style: TierStyle.of(context, Tier.cardCaptionBold)
                              .toTextStyle()),
                      const SizedBox(height: 8),
                      Text('錄到 $_savedStepsPlaceholder 步操作',
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(color: ds.textMuted)),
                      const SizedBox(height: 10),
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: ds.canvas,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ds.accentBlue),
                        ),
                        child: Text('鹿角蕨購物示範',
                            style: TierStyle.of(context, Tier.cardCaption)
                                .toTextStyle()),
                      ),
                      const SizedBox(height: 12),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                              backgroundColor: ds.accentBlue),
                          child: Text('儲存',
                              style: TierStyle.of(context, Tier.cardCaptionBold)
                                  .toTextStyle()
                                  .copyWith(color: ds.canvas)),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

            // ── 說明泡泡（用意＋小 Tips）──
            if (_bubbleVisible)
              Positioned(
                left: (w * 0.5 - 190).clamp(8.0, w - 388),
                top: h * 0.64,
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ds.surfaceElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ds.accentBlue.withValues(alpha: 0.4)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 12)
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline, size: 15, color: ds.accentBlue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_bubbleTitle,
                              style: TierStyle.of(context, Tier.cardCaptionBold)
                                  .toTextStyle()),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(_bubbleTip,
                          style: TierStyle.of(context, Tier.cardCaption)
                              .toTextStyle()
                              .copyWith(color: ds.textSecondary)),
                    ],
                  ),
                ),
              ),

            // ── 假游標（帶點擊漣漪）──
            Positioned(
              left: pos.dx * w - 8,
              top: pos.dy * h - 4,
              child: Stack(alignment: Alignment.center, children: [
                if (arrived)
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: ds.accentBlue
                              .withValues(alpha: 1.0 - (t - 0.92) / 0.08),
                          width: 2),
                    ),
                  ),
                CustomPaint(
                  size: const Size(20, 26),
                  painter: const _CursorPainter(),
                ),
              ]),
            ),
          ]);
        }),
      ),
    );
  }

  int get _savedStepsPlaceholder => _story.length;

  Widget _demoWindow(BridgeDSColors ds, String title, {required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(children: [
        Container(
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ds.surfaceElevated,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(10)),
          ),
          child: Text(title,
              style: TierStyle.of(context, Tier.cardCaption)
                  .toTextStyle()
                  .copyWith(color: ds.textMuted)),
        ),
        Expanded(child: child),
      ]),
    );
  }
}

class _CursorPainter extends CustomPainter {
  const _CursorPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 18)
      ..lineTo(4.6, 13.5)
      ..lineTo(7.6, 19.5)
      ..lineTo(10.4, 18)
      ..lineTo(7.4, 12.2)
      ..lineTo(13, 12)
      ..close();
    canvas.drawShadow(path, Colors.black, 3, false);
    canvas.drawPath(path, p);
    p.style = PaintingStyle.stroke;
    p.color = Colors.black45;
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _CursorPainter old) => false;
}

// ════════════════════════════════════════════════════
// 實戰區——真的錄＋已訓練列表
// ════════════════════════════════════════════════════

class _PracticeSection extends StatefulWidget {
  const _PracticeSection();

  @override
  State<_PracticeSection> createState() => _PracticeSectionState();
}

class _PracticeSectionState extends State<_PracticeSection> {
  bool _recording = false;
  List<String> _story = [];
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final r = SystemRoutineRecorder.instance;
      if (r.isRecording != _recording || r.story.length != _story.length) {
        if (mounted) {
          setState(() {
            _recording = r.isRecording;
            _story = r.story;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _toggle() async {
    final r = SystemRoutineRecorder.instance;
    if (r.isRecording) {
      final events = await r.stop();
      if (mounted) {
        setState(() {
          _recording = false;
          _story = r.story;
        });
      }
      if (events != null && events.isNotEmpty) await _saveDialog(events);
    } else {
      await r.start();
      if (mounted) {
        setState(() {
          _recording = r.isRecording;
          _story = [];
        });
      }
    }
  }

  Future<void> _saveDialog(List events) async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dctx).surface,
        title: const Text('儲存招式'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('錄到 ${events.length} 個操作'),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '招式名稱'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('放棄')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('儲存')),
        ],
      ),
    );
    if (ok != true) return;
    final routine = SystemRoutineStore.instance.fromRecorder(
        nameCtrl.text.trim().isEmpty
            ? '訓練 ${DateTime.now().month}/${DateTime.now().day}'
            : nameCtrl.text.trim(),
        events.cast());
    await SystemRoutineStore.instance.save(routine);
    // [Blue 令 2026-09-12] 存招式 = 寫程序性記憶——「學會的招式永不遺忘」
    await MoveMemoryBridge.instance.onMoveSaved(routine);
    if (mounted) setState(() {});
  }

  Future<void> _replay(SavedRoutine routine) async {
    // [Blue 拍板 2026-09-12] 重播前先跳出全域對話——Agent 問清意圖再動手。
    // 「搞不好問完才知道必須打組合招式才能滿足使用者的最終需求。」
    final hintCtrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(dctx).surface,
        title: Text('使出「${routine.name}」前——先講清楚目標'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('這招有 ${routine.stepCount} 步。動手前 Agent 會在對話中'
              '跟你確認需求與意圖——可能這招單打就夠，也可能要組合招。\n'),
          TextField(
            controller: hintCtrl,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: '這招打完，你希望得到什麼？（可留空）'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('到對話中釐清')),
        ],
      ),
    );
    if (go != true) return;

    // 跳全域對話（釐清模式——Agent 接手提問，點頭才執行）
    final sent = await MoveIntentClarifier.instance.clarify(
      move: routine,
      userHint: hintCtrl.text.trim().isEmpty ? null : hintCtrl.text.trim(),
    );
    if (!sent && mounted) {
      // callback 沒掛（對話層未初始化）——退回直接執行並誠實告知
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('全域對話不可用——直接執行（Esc 1.5 秒可急停）')));
      final res =
          await SystemRoutinePlayer.instance.replay(routine.events);
      // [Blue 令] 自傳記憶——fallback 執行也寫經歷
      await MoveMemoryBridge.instance.onMoveReplayed(
          move: routine, played: res.played, skipped: res.skipped);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('重播完成：${res.played} 步執行、${res.skipped} 步跳過')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _recording ? ds.accentRed : ds.borderDefault, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_recording ? Icons.fiber_manual_record : Icons.play_circle_outline,
                size: 18, color: _recording ? ds.accentRed : ds.accentBlue),
            const SizedBox(width: 8),
            Text(_recording ? '錄製中——去任何 App 操作，完成後回來停止' : '實戰：錄一個招式',
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle()),
          ]),
          const SizedBox(height: 12),
          if (_recording && _story.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: ds.canvas,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _story.length,
                itemBuilder: (context, i) => Text(
                  '${i + 1}. ${_story[_story.length - 1 - i]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TierStyle.of(context, Tier.cardCaption).toTextStyle(),
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: _toggle,
            style: FilledButton.styleFrom(
                backgroundColor: _recording ? ds.accentRed : ds.accentBlue),
            icon: Icon(
                _recording ? Icons.stop : Icons.fiber_manual_record,
                size: 16),
            label: Text(_recording ? '停止並存檔' : '開始錄製',
                style:
                    TierStyle.of(context, Tier.buttonPrimary).toTextStyle()),
          ),
          const SizedBox(height: 20),
          FutureBuilder<List<SavedRoutine>>(
            future: SystemRoutineStore.instance.list(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final routines = snap.data!;
              if (routines.isEmpty) {
                return Text('還沒有招式——錄第一段吧',
                    style: TierStyle.of(context, Tier.cardCaption)
                        .toTextStyle()
                        .copyWith(color: ds.textMuted));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('招式庫（${routines.length}）',
                      style: TierStyle.of(context, Tier.cardCaptionBold)
                          .toTextStyle()
                          .copyWith(color: ds.textMuted)),
                  const SizedBox(height: 8),
                  ...routines.map((r) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Icon(Icons.play_circle_outline,
                              size: 16, color: ds.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('${r.name} · ${r.stepCount} 步',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TierStyle.of(context, Tier.cardCaption)
                                    .toTextStyle()),
                          ),
                          InkWell(
                            onTap: () => _replay(r),
                            child: Text('使出這招',
                                style: TierStyle.of(context, Tier.cardCaptionBold)
                                    .toTextStyle()
                                    .copyWith(color: ds.accentBlue)),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: () async {
                              await SystemRoutineStore.instance.delete(r.id);
                              // [Blue 令] 刪招式同步歸檔記憶——不留指向虛空的手
                              await MoveMemoryBridge.instance.onMoveDeleted(r);
                              if (mounted) setState(() {});
                            },
                            child: Text('刪除',
                                style: TierStyle.of(context, Tier.cardCaption)
                                    .toTextStyle()
                                    .copyWith(color: ds.textMuted)),
                          ),
                        ]),
                      )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
