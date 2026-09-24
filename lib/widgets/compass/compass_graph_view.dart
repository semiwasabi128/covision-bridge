// compass_graph_view.dart
// [小葵 2026-09-10 Blue 令] 羅盤 2D 圖譜——視覺對齊最新一代 VaultGraphView
//
// 同代視覺語言（從 vault_graph_view.dart 移植）：
// - 淡網格背景（40px、alpha 0.08）
// - 貝茲曲線連線（不是直線）
// - hover：光暈放大+標籤變粗
// - 節點外圈 ring（半透明）
// - 溫度降溫收斂（300 迭代上限）
// - 拖曳單一節點（拖時局部重排）
//
// 羅盤專屬語義（Blue 設計）：
// - 有規則器官：同群成串（貝茲線+群色）、大節點+亮芯
// - 零規則器官：咖啡色（暖色調）小點散最外圈，等待被接進來

import 'dart:math' as math;

import 'package:bridge_app/services/compass/compass_models.dart';
import 'package:bridge_app/services/compass/compass_store.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

/// 零規則器官的咖啡色（token 混出，不寫死 hex）
Color idleCoffeeFor(BridgeDSColors cs) => Color.alphaBlend(
      Color.alphaBlend(
        cs.accentYellow.withValues(alpha: 0.22),
        cs.accentRuby.withValues(alpha: 0.5),
      ),
      cs.textMuted,
    );

Color _groupColor(BridgeDSColors cs, String group) {
  switch (group) {
    case '對話':
      return cs.accentBlue;
    case '畫布':
      return cs.accentMiro;
    case '大腦':
      return cs.accentPurple;
    case '向量':
      return cs.accentGreen;
    case '服務群':
      return cs.accentYellow;
    case '夥伴':
      return cs.accentMagenta;
    case '專案':
      return cs.accentRuby;
    case '肢體': // [Blue 令 2026-09-12] 招式深橙紅——與🥋節點同族
      return const Color(0xFFFF8A65);
    case '協作系統': // [Blue 令 2026-09-12] 蜂群青色——一眼認出
      return const Color(0xFF26C6DA);
    default:
      return cs.accentBlue;
  }
}

class CompassGraphView extends StatefulWidget {
  final void Function(CompassOrgan organ)? onNodeTap;
  const CompassGraphView({super.key, this.onNodeTap});

  @override
  State<CompassGraphView> createState() => _CompassGraphViewState();
}

class _CompassGraphViewState extends State<CompassGraphView>
    with SingleTickerProviderStateMixin {
  final store = CompassStore.instance;

  final Map<String, Offset> _pos = {};
  final Map<String, Offset> _anchors = {}; // 扇區錨點（Q 彈回位目標）
  final Map<String, Offset> _vel = {}; // 速度場（欠阻尼→Q 彈）
  bool _calm = false; // 全場靜止（只剩呼吸）——拖曳/回彈時喚醒
  final Map<String, double> _radius = {};
  final List<({String a, String b, String group})> _edges = [];
  // idle → 同群 active 的「待接線」（等待被接進來的視覺）
  final Map<String, String> _pendingLinks = {};
  List<CompassOrgan> _organs = [];
  final Set<String> _activeIds = {};
  final Map<String, int> _ruleCount = {};

  late final Ticker _ticker;
  Size _canvasSize = const Size(800, 600);

  // [退役 2D 圖譜復活] 呼吸脈動（painter 內聯漂移計算）
  double _pulse = 0.0;
  bool _sizeInitialized = false;

  // 互動（同 VaultGraphView）
  Offset _panOffset = Offset.zero;
  double _zoom = 1.0;
  String? _draggingNodeId;
  String? _hoveredNodeId;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_onTick);
    _loadData();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _loadData() {
    _organs = store.organs();
    _activeIds.clear();
    _ruleCount.clear();
    for (final o in _organs) {
      final n = store.rules(organId: o.id).length;
      if (n > 0) {
        _activeIds.add(o.id);
        _ruleCount[o.id] = n;
      }
    }
    _edges.clear();
    final byGroup = <String, List<CompassOrgan>>{};
    for (final o in _organs) {
      if (!_activeIds.contains(o.id)) continue;
      byGroup.putIfAbsent(o.systemGroup, () => []).add(o);
    }
    byGroup.forEach((g, list) {
      for (var i = 0; i < list.length - 1; i++) {
        _edges.add((a: list[i].id, b: list[i + 1].id, group: g));
      }
    });
    // 同群 idle → 該群第一個 active：待接線（淡虛線，畫在 painter）
    _pendingLinks.clear();
    for (final o in _organs) {
      if (_activeIds.contains(o.id)) continue;
      final sameGroup = _organs.where((a) =>
          a.systemGroup == o.systemGroup && _activeIds.contains(a.id));
      if (sameGroup.isNotEmpty) {
        _pendingLinks[o.id] = sameGroup.first.id;
      }
    }
    // 佈局等到 LayoutBuilder 給真實尺寸才跑（見 build）
  }

  void _initLayout() {
    final center = Offset(_canvasSize.width / 2, _canvasSize.height / 2);
    final rng = math.Random(42); // 固定種子可重現（同 VaultGraphView）
    final active =
        _organs.where((o) => _activeIds.contains(o.id)).toList();
    final idle =
        _organs.where((o) => !_activeIds.contains(o.id)).toList();
    // 有規則：內環輻射；零規則：外圈散佈
    // [退役圖譜 _layoutSector 手法] 按群分扇區：每個 systemGroup 一個
    // 扇區中心（圍成內環），群成員繞扇區中心小半徑散布——天生成叢。
    // 力導向只做微調（局部斥力去重疊），不再承擔全局佈局。
    final minSide = math.min(_canvasSize.width, _canvasSize.height);
    final groups = <String>[];
    for (final o in active) {
      if (!groups.contains(o.systemGroup)) groups.add(o.systemGroup);
    }
    final sectorR = minSide * 0.26;
    final groupAngles = <String, double>{};
    for (var g = 0; g < groups.length; g++) {
      groupAngles[groups[g]] =
          -math.pi / 2 + 2 * math.pi * g / math.max(groups.length, 1);
    }
    final memberIdx = <String, int>{};
    for (final o in active) {
      final g = o.systemGroup;
      final ga = groupAngles[g]!;
      final gi = memberIdx[g] ?? 0;
      memberIdx[g] = gi + 1;
      final gn = active.where((a) => a.systemGroup == g).length;
      // 扇區內：成員圍繞扇區中心（扇區局部小圈）
      final ma = ga + (gn > 1 ? 2 * math.pi * gi / gn : 0);
      final mr = math.min(46.0 * math.sqrt(gn.toDouble()), sectorR * 0.5);
      _pos[o.id] = center +
          Offset(math.cos(ga), math.sin(ga)) * sectorR +
          Offset(math.cos(ma), math.sin(ma)) * mr;
      _radius[o.id] =
          12.0 + math.min((_ruleCount[o.id] ?? 1) * 1.2, 10);
    }
    for (var i = 0; i < idle.length; i++) {
      final o = idle[i];
      // 有同群 active：掛在該群扇區外側（140px 待接距離）；
      // 真孤兒：最外圈環
      final ga = groupAngles[o.systemGroup];
      final a = ga ?? rng.nextDouble() * 2 * math.pi;
      final r = ga != null ? sectorR + 140 : minSide * 0.44;
      final jitter = (rng.nextDouble() - 0.5) * 0.5;
      _pos[o.id] = center +
          Offset(math.cos(a + jitter), math.sin(a + jitter)) * r;
      _radius[o.id] = 5.0;
    }
    _anchors.clear();
    _vel.clear();
    _pos.forEach((id, p) {
      _anchors[id] = p;
      _vel[id] = Offset.zero;
    });
    _calm = false;
  }

  void _onTick(Duration elapsed) {
    _pulse = (elapsed.inMilliseconds % 4000) / 4000;
    // [Blue 2026-09-10 Q 彈令] 拖曳中或未平靜 → 跑葡萄串物理；
    // 全場靜止 → 只剩呼吸（省電）
    if (_draggingNodeId != null || !_calm) {
      _stepPhysics();
    }
    if (mounted) setState(() {});
  }

  /// 葡萄串物理：鏈式彈簧＋錨點彈簧＋局部斥力，欠阻尼積分 → Q 彈
  void _stepPhysics() {
    final center =
        Offset(_canvasSize.width / 2, _canvasSize.height / 2);

    // 力累積
    final forces = <String, Offset>{};
    for (final id in _pos.keys) {
      forces[id] = Offset.zero;
    }

    // 1. 錨點彈簧（Q 彈回位主引擎）——欠阻尼：勁度 0.025、
    //    阻尼見速度衰減 0.90（會來回彈 2-3 次才停）
    _pos.forEach((id, p) {
      final a = _anchors[id];
      if (a == null) return;
      forces[id] = forces[id]! + (a - p) * 0.025;
    });

    // 2. 鏈式彈簧（葡萄串牽引）：同群 active 鏈（rest 90）＋
    //    idle 待接線（rest 140，較弱——跟著拖但拖不動太多）
    for (final e in _edges) {
      final a = _pos[e.a], b = _pos[e.b];
      if (a == null || b == null) continue;
      _applySpring(forces, e.a, e.b, 90.0, 0.012);
    }
    _pendingLinks.forEach((idleId, activeId) {
      _applySpring(forces, idleId, activeId, 140.0, 0.006);
    });

    // 3. 局部斥力（近距離去重疊，d<90）
    final ids = _pos.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final d = _pos[ids[i]]! - _pos[ids[j]]!;
        final dist = d.distance;
        if (dist >= 90 || dist < 0.1) continue;
        final f = (90 - dist) / 90 * 2.5;
        final u = d / dist;
        forces[ids[i]] = forces[ids[i]]! + u * f;
        forces[ids[j]] = forces[ids[j]]! - u * f;
      }
    }

    // 4. 極弱中心引力（防整體漂）
    for (final id in _pos.keys) {
      final toC = center - _pos[id]!;
      forces[id] = forces[id]! + toC * 0.0015;
    }

    // 5. 積分：拖曳中的節點釘在指針位置（速度清零），
    //    其餘 vel = vel*0.90 + F*0.35（欠阻尼 → Q 彈）
    var maxVel = 0.0;
    _pos.forEach((id, p) {
      if (id == _draggingNodeId) {
        _vel[id] = Offset.zero;
        return;
      }
      var v = (_vel[id] ?? Offset.zero) * 0.90 +
          (forces[id] ?? Offset.zero) * 0.35;
      // 速度上限（防炸）
      final sp = v.distance;
      if (sp > 26) v = v / sp * 26;
      _vel[id] = v;
      var np = p + v;
      np = Offset(
        np.dx.clamp(30.0, _canvasSize.width - 30),
        np.dy.clamp(30.0, _canvasSize.height - 30),
      );
      _pos[id] = np;
      if (sp > maxVel) maxVel = sp;
    });
    _calm = maxVel < 0.05;
  }

  /// 彈簧助手：a↔b，rest 彈簧原長，k 勁度
  void _applySpring(Map<String, Offset> forces, String a, String b,
      double rest, double k) {
    final pa = _pos[a], pb = _pos[b];
    if (pa == null || pb == null) return;
    final d = pb - pa;
    final dist = math.max(d.distance, 1.0);
    final f = (dist - rest) * k;
    final u = d / dist;
    forces[a] = (forces[a] ?? Offset.zero) + u * f;
    forces[b] = (forces[b] ?? Offset.zero) - u * f;
  }

  Offset _screenToWorld(Offset p) =>
      (p - _panOffset) / (_zoom == 0 ? 1 : _zoom);

  String? _hitTest(Offset world) {
    String? hit;
    _pos.forEach((id, p) {
      final r = (_radius[id] ?? 10) + 6;
      if ((p - world).distance <= r) hit = id;
    });
    return hit;
  }

  @override
  Widget build(BuildContext context) {
    final cs = BridgeDSColors.of(context);
    return LayoutBuilder(builder: (context, cons) {
      final newSize = Size(cons.maxWidth, cons.maxHeight);
      // [小葵 2026-09-10 截圖抓包] 真實尺寸到手才排位——原版用預設
      // 800x600 排完就不重排，節點散錯位置、active 不成叢
      final isFirstRealSize = !_sizeInitialized &&
          newSize.width > 100 &&
          newSize.height > 100;
      if (isFirstRealSize) {
        _sizeInitialized = true;
        _canvasSize = newSize;
        _initLayout();
        if (!_ticker.isActive) _ticker.start();
      } else {
        _canvasSize = newSize;
      }
      return GestureDetector(
        onTapUp: (d) {
          final id = _hitTest(_screenToWorld(d.localPosition));
          if (id != null) {
            final o = _organs.firstWhere((o) => o.id == id);
            widget.onNodeTap?.call(o);
          }
        },
        onScaleStart: (d) {
          final id = _hitTest(_screenToWorld(d.localFocalPoint));
          if (id != null) {
            _draggingNodeId = id;
            _calm = false; // 喚醒葡萄串物理
            if (!_ticker.isActive) _ticker.start();
          }
        },
        onScaleUpdate: (d) {
          setState(() {
            if (_draggingNodeId != null) {
              _pos[_draggingNodeId!] = _pos[_draggingNodeId!]! +
                  d.focalPointDelta / (_zoom == 0 ? 1 : _zoom);
            } else {
              _panOffset += d.focalPointDelta;
              _zoom = (_zoom * d.scale).clamp(0.4, 2.5);
            }
          });
        },
        onScaleEnd: (_) {
          // 放手＝Q 彈回位開始（錨點+鏈式彈簧接管）
          _draggingNodeId = null;
          _calm = false;
        },
        child: MouseRegion(
          onHover: (e) {
            final id = _hitTest(_screenToWorld(e.localPosition));
            if (id != _hoveredNodeId) setState(() => _hoveredNodeId = id);
          },
          child: Listener(
            onPointerSignal: (e) {
              if (e is PointerScrollEvent) {
                setState(() {
                  _zoom = (_zoom * (e.scrollDelta.dy > 0 ? 0.9 : 1.1))
                      .clamp(0.35, 3.0);
                });
              }
            },
            child: CustomPaint(
              painter: _CompassGraphPainter(
                organs: _organs,
                activeIds: _activeIds,
                ruleCount: _ruleCount,
                pendingLinks: _pendingLinks,
                edges: _edges,
                pos: _pos,
                radius: _radius,
                panOffset: _panOffset,
                zoom: _zoom,
                hovered: _hoveredNodeId,
                dragging: _draggingNodeId,
                pulse: _pulse,
                cs: cs,
              ),
              child: Container(),
            ),
          ),
        ),
      );
    });
  }
}

class _CompassGraphPainter extends CustomPainter {
  final List<CompassOrgan> organs;
  final Set<String> activeIds;
  final Map<String, int> ruleCount;
  final Map<String, String> pendingLinks;
  final List<({String a, String b, String group})> edges;
  final Map<String, Offset> pos;
  final Map<String, double> radius;
  final Offset panOffset;
  final double zoom;
  final String? hovered;
  final String? dragging;
  final double pulse;
  final BridgeDSColors cs;

  _CompassGraphPainter({
    required this.organs,
    required this.activeIds,
    required this.ruleCount,
    required this.pendingLinks,
    required this.edges,
    required this.pos,
    required this.radius,
    required this.panOffset,
    required this.zoom,
    required this.hovered,
    required this.dragging,
    required this.pulse,
    required this.cs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(zoom);

    // ── 背景（[Blue 令 2026-09-12] 移除格子底線——乾淨畫布）──

    // ── 群聚叢光暈（退役圖譜房間聚類視覺）：同群 active 外擴大光暈 ══
    final groupCenters = <String, List<Offset>>{};
    for (final o in organs) {
      if (!activeIds.contains(o.id)) continue;
      final p = pos[o.id];
      if (p == null) continue;
      groupCenters.putIfAbsent(o.systemGroup, () => []).add(p);
    }
    groupCenters.forEach((g, pts) {
      if (pts.length < 2) return;
      var cx = 0.0, cy = 0.0;
      for (final p in pts) {
        cx += p.dx;
        cy += p.dy;
      }
      final c = Offset(cx / pts.length, cy / pts.length);
      var maxD = 0.0;
      for (final p in pts) {
        final d = (p - c).distance;
        if (d > maxD) maxD = d;
      }
      final gr = maxD + 34;
      final gc = _groupColor(cs, g);
      canvas.drawCircle(
        c,
        gr,
        Paint()
          ..color = gc.withValues(alpha: 0.06)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
      );

    });

    // ── 貝茲曲線連線（同 VaultGraphView——不是直線）──
    for (final e in edges) {
      final p1 = pos[e.a], p2 = pos[e.b];
      if (p1 == null || p2 == null) continue;
      final isHot = hovered == e.a || hovered == e.b;
      final paint = Paint()
        ..color = _groupColor(cs, e.group)
            .withValues(alpha: isHot ? 0.85 : 0.4)
        ..strokeWidth = isHot ? 2.0 : 1.2
        ..style = PaintingStyle.stroke;
      final midX = (p1.dx + p2.dx) / 2;
      final midY = (p1.dy + p2.dy) / 2;
      final cp = Offset(midX + (p2.dy - p1.dy) * 0.1,
          midY - (p2.dx - p1.dx) * 0.1);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..quadraticBezierTo(cp.dx, cp.dy, p2.dx, p2.dy);
      canvas.drawPath(path, paint);
    }

    // ── 待接虛線：idle → 同群 active（等待被接進來）──
    for (final entry in pendingLinks.entries) {
      final p1 = pos[entry.key], p2 = pos[entry.value];
      if (p1 == null || p2 == null) continue;
      final paint = Paint()
        ..color = idleCoffeeFor(cs).withValues(alpha: 0.35)
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      // 手動虛線（Flutter 無內建 dash）
      final dist = (p2 - p1).distance;
      const dash = 6.0, gap = 5.0;
      final dir = (p2 - p1) / dist;
      var d = 0.0;
      while (d < dist) {
        final from = p1 + dir * d;
        final to = p1 + dir * math.min(d + dash, dist);
        canvas.drawLine(from, to, paint);
        d += dash + gap;
      }
    }

    // ── 節點（退役 2D 圖譜視覺規格：光暈底/半透明填充/ring/漂移）──
    for (final o in organs) {
      final base = pos[o.id];
      if (base == null) continue;
      // 呼吸漂移（退役圖譜 idleDrift——醒著才呼吸）
      final phase = (o.id.hashCode & 0x3FF) / 256.0;
      final p = base +
          Offset(
            1.2 * math.sin(pulse * 2 * math.pi + phase),
            1.0 * math.sin(pulse * 2 * math.pi + phase * 1.7 + 1.3),
          );
      final isActive = activeIds.contains(o.id);
      final r = radius[o.id] ?? (isActive ? 12 : 5);
      // 零規則=咖啡暖色：由 token 混出（accentYellow 暖金 + textMuted 灰
      // → 混出低飽和咖啡調），不寫死 hex（app.colorTokens 規則）
      final color = isActive
          ? _groupColor(cs, o.systemGroup)
          : idleCoffeeFor(cs);
      final isHovered = hovered == o.id;
      final isDragging = dragging == o.id;

      // [退役圖譜規格] 光暈底：blur 18、alpha 0.10（active 大光暈）
      final glow = Paint()
        ..color = color.withValues(alpha: isActive ? 0.10 : 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(p, r * (isActive ? 1.8 : 1.4), glow);

      // [退役圖譜規格] 半透明填充 0.28 + ring 0.7
      canvas.drawCircle(
        p,
        r,
        Paint()..color = color.withValues(alpha: 0.28),
      );
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..color = color.withValues(alpha: isHovered || isDragging ? 0.95 : 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // hover 亮外環（退役圖譜規格）
      if (isHovered || isDragging) {
        canvas.drawCircle(
          p,
          r + 5,
          Paint()
            ..color = color.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0,
        );
      }

      // 亮芯（有規則——半透明填充上的視覺錨點）
      if (isActive) {
        canvas.drawCircle(
            p, r * 0.40, Paint()..color = color.withValues(alpha: 0.95));
      }

      // 標籤（hover 變粗變大——同 VaultGraphView）
      // [Blue 2026-09-10] 全部光球名字常駐；字級隨縮放（全景大、
      // 推進後相對小——同 3D 星系體驗）
      final zf = math.sqrt(zoom.clamp(0.35, 3.0));
      final fs = (isActive ? 13.0 : 11.0) / zf;
      final tp = TextPainter(
        text: TextSpan(
          text: isActive ? '${o.name}·${ruleCount[o.id]}' : o.name,
          style: TextStyle(
            color: isActive
                ? (isHovered ? cs.textPrimary : cs.textSecondary)
                : (isHovered ? cs.textTertiary : cs.textQuaternary),
            fontSize: fs,
            fontWeight:
                isHovered ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 110);
      tp.paint(canvas,
          Offset(p.dx - tp.width / 2, p.dy + r + 4));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CompassGraphPainter old) => true;
}
