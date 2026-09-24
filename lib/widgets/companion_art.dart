import 'dart:math';

import 'package:flutter/material.dart';

import '../models/agent_activity.dart';
import '../models/companion.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

class CompanionArt extends StatelessWidget {
  final String mbtiCode;
  final int seed;
  final String name;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final String? label;
  final double size;
  final bool framed;

  const CompanionArt({
    super.key,
    required this.mbtiCode,
    required this.seed,
    required this.name,
    this.mood = AgentCompanionMood.idle,
    this.action = AgentCompanionAction.standing,
    this.label,
    this.size = 180,
    this.framed = true,
  });

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final art = CustomPaint(
      size: Size.square(size),
      painter: _CompanionArtPainter(
        mbtiCode: mbtiCode,
        seed: seed,
        name: name,
        mood: mood,
        action: action,
        colors: ds,
      ),
    );

    final content = Stack(
      alignment: Alignment.center,
      children: [
        art,
        if (label != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: ds.canvas.withValues(alpha: 0.78),
                borderRadius: BorderRadius.circular(AppTheme.radiusXL),
                border: Border.all(color: ds.textPrimary),
              ),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: ds.accentBlue,
                  fontWeight: FontWeight.w800,),
              ),
            ),
          ),
      ],
    );

    if (!framed) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: BridgeDSColors.of(context).surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          border: Border.all(color: BridgeDSColors.of(context).borderDefault),
        ),
        child: content,
      ),
    );
  }
}

class CompanionArtSheet extends StatelessWidget {
  final String mbtiCode;
  final int seed;
  final String name;
  final bool compact;

  const CompanionArtSheet({
    super.key,
    required this.mbtiCode,
    required this.seed,
    required this.name,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final stages = [
      (
        label: '待機',
        mood: AgentCompanionMood.idle,
        action: AgentCompanionAction.standing,
      ),
      (
        label: '閱讀',
        mood: AgentCompanionMood.focused,
        action: AgentCompanionAction.reading,
      ),
      (
        label: '指路',
        mood: AgentCompanionMood.routing,
        action: AgentCompanionAction.pointing,
      ),
      (
        label: '橋接',
        mood: AgentCompanionMood.bridging,
        action: AgentCompanionAction.spinning,
      ),
      if (!compact)
        (
          label: '慶祝',
          mood: AgentCompanionMood.proud,
          action: AgentCompanionAction.bouncing,
        ),
      if (!compact)
        (
          label: '漫遊',
          mood: AgentCompanionMood.curious,
          action: AgentCompanionAction.wandering,
        ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: stages.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: compact ? 4 : 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final stage = stages[index];
        return LayoutBuilder(
          builder: (context, constraints) {
            final artSize = min(constraints.maxWidth, constraints.maxHeight);
            return CompanionArt(
              mbtiCode: mbtiCode,
              seed: seed + (index * 97),
              name: name,
              mood: stage.mood,
              action: stage.action,
              label: stage.label,
              size: artSize,
            );
          },
        );
      },
    );
  }
}

class _CompanionArtPainter extends CustomPainter {
  final String mbtiCode;
  final int seed;
  final String name;
  final AgentCompanionMood mood;
  final AgentCompanionAction action;
  final BridgeDSColors colors;

  const _CompanionArtPainter({
    required this.mbtiCode,
    required this.seed,
    required this.name,
    required this.mood,
    required this.action,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed + mbtiCode.hashCode);
    final palette = _paletteFor(mbtiCode);
    final rect = Offset.zero & size;
    final center = rect.center;
    final scale = size.shortestSide / 180;
    final pulse = action == AgentCompanionAction.bouncing ? -4 * scale : 0.0;
    final spin = action == AgentCompanionAction.spinning ? 0.22 : 0.0;

    final bgPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          palette[0].withValues(alpha: 0.20),
          palette[1].withValues(alpha: 0.10),
          colors.canvas,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, bgPaint);

    _drawMistVeil(canvas, rect, scale, palette, rng);
    _drawAura(canvas, center.translate(0, pulse), scale, palette);
    _drawOrbit(canvas, center.translate(0, pulse), scale, palette, spin);
    _drawShadow(canvas, center.translate(0, 62 * scale), scale);
    _drawUnrevealedFigure(canvas, center.translate(0, pulse), scale, palette);
    _drawQuestionCore(canvas, center.translate(0, pulse), scale, palette);
    _drawActionRune(canvas, center.translate(0, pulse), scale, palette);
    _drawNameSpark(canvas, size, palette);
  }

  void _drawAura(
    Canvas canvas,
    Offset center,
    double scale,
    List<Color> colors,
  ) {
    for (var i = 0; i < 3; i++) {
      final radius = (58 + i * 17) * scale;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = colors[i % colors.length].withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
    }
  }

  void _drawOrbit(
    Canvas canvas,
    Offset center,
    double scale,
    List<Color> colors,
    double spin,
  ) {
    final paint = Paint()
      ..color = colors[1].withValues(alpha: 0.52)
      ..strokeWidth = 2 * scale
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((-0.45 + i * 0.82) + spin);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: (118 - i * 22) * scale,
          height: (62 + i * 8) * scale,
        ),
        paint..color = colors[(i + 1) % colors.length].withValues(alpha: 0.42),
      );
      canvas.restore();
    }
  }

  void _drawShadow(Canvas canvas, Offset center, double scale) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 66 * scale, height: 16 * scale),
      Paint()..color = colors.canvas.withValues(alpha: 0.10),
    );
  }

  void _drawNameSpark(Canvas canvas, Size size, List<Color> colors) {
    if (name.isEmpty) return;
    final paint = Paint()..color = colors[2].withValues(alpha: 0.70);
    final count = min(5, name.runes.length + 1);
    for (var i = 0; i < count; i++) {
      final x = size.width * (0.18 + i * 0.16);
      final y = size.height * (0.13 + (i.isEven ? 0.04 : 0.0));
      canvas.drawCircle(Offset(x, y), 2.4, paint);
    }
  }

  void _drawMistVeil(
    Canvas canvas,
    Rect rect,
    double scale,
    List<Color> colors,
    Random rng,
  ) {
    canvas.drawOval(
      Rect.fromCenter(
        center: rect.center.translate(0, -4 * scale),
        width: 142 * scale,
        height: 126 * scale,
      ),
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.56),
            colors[0].withValues(alpha: 0.16),
            Colors.transparent,
          ],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * scale),
    );

    final dustPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4 * scale;
    for (var i = 0; i < 18; i++) {
      final angle = rng.nextDouble() * pi * 2;
      final distance = (36 + rng.nextDouble() * 54) * scale;
      final point = rect.center.translate(
        cos(angle) * distance,
        sin(angle) * distance,
      );
      dustPaint.color = colors[i % colors.length].withValues(
        alpha: 0.18 + rng.nextDouble() * 0.22,
      );
      canvas.drawCircle(
        point,
        (0.9 + rng.nextDouble() * 1.8) * scale,
        dustPaint,
      );
    }
  }

  void _drawUnrevealedFigure(
    Canvas canvas,
    Offset center,
    double scale,
    List<Color> colors,
  ) {
    final silhouette = Path()
      ..moveTo(center.dx, center.dy - 58 * scale)
      ..cubicTo(
        center.dx + 42 * scale,
        center.dy - 48 * scale,
        center.dx + 56 * scale,
        center.dy - 3 * scale,
        center.dx + 36 * scale,
        center.dy + 52 * scale,
      )
      ..cubicTo(
        center.dx + 17 * scale,
        center.dy + 70 * scale,
        center.dx - 17 * scale,
        center.dy + 70 * scale,
        center.dx - 36 * scale,
        center.dy + 52 * scale,
      )
      ..cubicTo(
        center.dx - 56 * scale,
        center.dy - 3 * scale,
        center.dx - 42 * scale,
        center.dy - 48 * scale,
        center.dx,
        center.dy - 58 * scale,
      );

    canvas.drawPath(
      silhouette,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.accent.withValues(alpha: 0.84),
            colors[0].withValues(alpha: 0.58),
            colors[2].withValues(alpha: 0.38),
          ],
        ).createShader(silhouette.getBounds())
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.4 * scale),
    );
    canvas.drawPath(
      silhouette,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.50)
        ..strokeWidth = 1.3 * scale
        ..style = PaintingStyle.stroke,
    );

    final hood = Rect.fromCenter(
      center: center.translate(0, -25 * scale),
      width: 54 * scale,
      height: 48 * scale,
    );
    canvas.drawOval(
      hood,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.74),
            colors[1].withValues(alpha: 0.40),
            AppTheme.accent.withValues(alpha: 0.20),
          ],
        ).createShader(hood),
    );
  }

  void _drawQuestionCore(
    Canvas canvas,
    Offset center,
    double scale,
    List<Color> colors,
  ) {
    final coreCenter = center.translate(0, -24 * scale);
    canvas.drawCircle(
      coreCenter,
      19 * scale,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.82),
            colors[2].withValues(alpha: 0.34),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: coreCenter, radius: 25 * scale)),
    );
    final textPainter = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: AppTheme.accent.withValues(alpha: 0.82),
          fontSize: 32 * scale,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      coreCenter - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  void _drawActionRune(
    Canvas canvas,
    Offset center,
    double scale,
    List<Color> colors,
  ) {
    final paint = Paint()
      ..color = colors[2].withValues(alpha: 0.70)
      ..strokeWidth = 2.2 * scale
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final runeCenter = center.translate(0, 34 * scale);

    switch (action) {
      case AgentCompanionAction.reading:
        final book = Rect.fromCenter(
          center: runeCenter,
          width: 46 * scale,
          height: 24 * scale,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(book, Radius.circular(5 * scale)),
          Paint()..color = Colors.white.withValues(alpha: 0.38),
        );
        canvas.drawLine(book.centerLeft, book.centerRight, paint);
      case AgentCompanionAction.pointing:
        canvas.drawLine(
          runeCenter.translate(-24 * scale, 9 * scale),
          runeCenter.translate(27 * scale, -11 * scale),
          paint,
        );
        canvas.drawCircle(
          runeCenter.translate(31 * scale, -13 * scale),
          4.5 * scale,
          Paint()..color = colors[2].withValues(alpha: 0.78),
        );
      case AgentCompanionAction.spinning:
        canvas.drawCircle(runeCenter, 24 * scale, paint);
        canvas.drawCircle(
          runeCenter,
          38 * scale,
          paint..color = colors[1].withValues(alpha: 0.34),
        );
      case AgentCompanionAction.wandering:
        for (var i = 0; i < 3; i++) {
          canvas.drawCircle(
            runeCenter.translate(
              (-22 + i * 22) * scale,
              (i.isEven ? 5 : -5) * scale,
            ),
            3.2 * scale,
            Paint()..color = colors[i % colors.length].withValues(alpha: 0.70),
          );
        }
      case AgentCompanionAction.bouncing:
        final star = Path()
          ..moveTo(runeCenter.dx, runeCenter.dy - 22 * scale)
          ..lineTo(runeCenter.dx + 6 * scale, runeCenter.dy - 4 * scale)
          ..lineTo(runeCenter.dx + 24 * scale, runeCenter.dy)
          ..lineTo(runeCenter.dx + 6 * scale, runeCenter.dy + 5 * scale)
          ..lineTo(runeCenter.dx, runeCenter.dy + 23 * scale)
          ..lineTo(runeCenter.dx - 6 * scale, runeCenter.dy + 5 * scale)
          ..lineTo(runeCenter.dx - 24 * scale, runeCenter.dy)
          ..lineTo(runeCenter.dx - 6 * scale, runeCenter.dy - 4 * scale)
          ..close();
        canvas.drawPath(star, paint);
      case AgentCompanionAction.standing:
        canvas.drawCircle(runeCenter, 20 * scale, paint);
        canvas.drawLine(
          runeCenter.translate(-14 * scale, 0),
          runeCenter.translate(14 * scale, 0),
          paint,
        );
    }
  }

  List<Color> _paletteFor(String code) {
    final mbti = MBTIType.fromCode(code);
    final base = mbti?.colorHex ?? '#2A9D8F';
    final primary = _colorFromHex(base);
    return [primary, AppTheme.primary, AppTheme.secondary, AppTheme.accent];
  }

  Color _colorFromHex(String hex) {
    final normalized = hex.replaceFirst('#', '');
    final value = int.tryParse('FF$normalized', radix: 16);
    return value == null ? AppTheme.primary : Color(value);
  }

  @override
  bool shouldRepaint(covariant _CompanionArtPainter oldDelegate) {
    return oldDelegate.mbtiCode != mbtiCode ||
        oldDelegate.seed != seed ||
        oldDelegate.name != name ||
        oldDelegate.mood != mood ||
        oldDelegate.action != action;
  }
}
