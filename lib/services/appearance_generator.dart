// 橋樑 App — 抽象幾何形象生成器
// 根據 MBTI + 使用者提示詞 + 種子，生成獨一無二的 SVG 形象
// Phase 2: 可 plug-in 替換為其他生成方式

import 'dart:math';
import '../models/companion.dart';

class GeometricAppearanceGenerator implements AppearanceGenerator {
  static final Map<String, List<String>> _shapePresets = {
    'INTJ': ['hexagon', 'sharp_triangle', 'crystal'],
    'INTP': ['circle_network', 'orbital_ring', 'node_mesh'],
    'ENTJ': ['crown_spike', 'arrow_cluster', 'tower'],
    'ENTP': ['spiral', 'lightning_branch', 'fractal_star'],
    'INFJ': ['soft_glow', 'aurora_wave', 'mandala'],
    'INFP': ['flower_petal', 'water_ripple', 'butterfly'],
    'ENFJ': ['sun_rays', 'heart_pulse', 'warm_orb'],
    'ENFP': ['star_burst', 'confetti_orbit', 'sparkle_cluster'],
    'ISTJ': ['square_grid', 'shield', 'brick_pattern'],
    'ISFJ': ['soft_circle', 'nest', 'protective_arc'],
    'ESTJ': ['command_bars', 'hierarchy_pyramid', 'organizer_grid'],
    'ESFJ': ['community_circle', 'linking_chain', 'care_hands'],
    'ISTP': ['tool_gear', 'mechanical_joint', 'puzzle_piece'],
    'ISFP': ['paint_splash', 'color_blend', 'artistic_curve'],
    'ESTP': ['sport_bolt', 'action_arrow', 'energy_ball'],
    'ESFP': ['party_spark', 'music_note', 'dance_wave'],
  };

  static final Map<String, List<String>> _colorPalettes = {
    'INTJ': ['#2C3E50', '#34495E', '#5D6D7E', '#85929E'],
    'INTP': ['#1B2631', '#2E4053', '#5D6D7E', '#AEB6BF'],
    'ENTJ': ['#1A5276', '#2471A3', '#5499C7', '#85C1E9'],
    'ENTP': ['#1F618D', '#2E86C1', '#5DADE2', '#AED6F1'],
    'INFJ': ['#1E8449', '#27AE60', '#52BE80', '#A9DFBF'],
    'INFP': ['#27AE60', '#2ECC71', '#58D68D', '#ABEBC6'],
    'ENFJ': ['#16A085', '#1ABC9C', '#48C9B0', '#A3E4D7'],
    'ENFP': ['#2ECC71', '#58D68D', '#82E0AA', '#ABEBC6'],
    'ISTJ': ['#7F8C8D', '#95A5A6', '#B2BABB', '#D5DBDB'],
    'ISFJ': ['#95A5A6', '#AAB7B8', '#CCD1D1', '#E5E8E8'],
    'ESTJ': ['#566573', '#6E7F8D', '#99A3A4', '#CCD1D1'],
    'ESFJ': ['#5D6D7E', '#7F8C8D', '#AEB6BF', '#D5DBDB'],
    'ISTP': ['#D35400', '#E67E22', '#F39C12', '#F5B041'],
    'ISFP': ['#E67E22', '#F39C12', '#F5B041', '#F8C471'],
    'ESTP': ['#CA6F1E', '#D35400', '#E67E22', '#F39C12'],
    'ESFP': ['#F39C12', '#F5B041', '#F8C471', '#FAD7A0'],
  };

  @override
  String generateDescription(MBTIType mbti, String userPrompt, int seed) {
    final shapes = _shapePresets[mbti.code] ?? ['abstract_form'];
    final palette = _colorPalettes[mbti.code] ?? ['#6B8E6B', '#8FBC8F'];
    final rng = Random(seed);
    final mainShape = shapes[rng.nextInt(shapes.length)];
    final mainColor = palette[rng.nextInt(palette.length)];

    if (userPrompt.isEmpty) {
      return '${mbti.name}型的抽象$mainShape，以$mainColor為主色調，散發著${mbti.traits[rng.nextInt(mbti.traits.length)]}的氣質。';
    }
    return '${mbti.name}型的$mainShape形象，融合了「$userPrompt」的特質，以$mainColor為核心色調。';
  }

  @override
  String generatePreview(MBTIType mbti, String userPrompt, int seed) {
    final rng = Random(seed);
    final palette =
        _colorPalettes[mbti.code] ?? ['#6B8E6B', '#8FBC8F', '#A8D5A2'];
    final shapeType = rng.nextInt(5); // 0-4 different shape families

    // Generate SVG based on shape type
    return _generateSVG(mbti.code, palette, shapeType, rng, userPrompt);
  }

  String _generateSVG(
    String mbtiCode,
    List<String> palette,
    int shapeType,
    Random rng,
    String userPrompt,
  ) {
    final size = 256;
    final center = size / 2;
    final color1 = palette[rng.nextInt(palette.length)];
    final color2 = palette[rng.nextInt(palette.length)];
    final color3 = palette[rng.nextInt(palette.length)];

    // Add user prompt influence
    final influence = userPrompt.isNotEmpty ? rng.nextInt(30) + 10 : 0;

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
      '<svg width="$size" height="$size" viewBox="0 0 $size $size" xmlns="http://www.w3.org/2000/svg">',
    );
    buffer.writeln('  <defs>');
    buffer.writeln('    <radialGradient id="bg" cx="50%" cy="50%" r="50%">');
    buffer.writeln(
      '      <stop offset="0%" stop-color="$color1" stop-opacity="0.3"/>',
    );
    buffer.writeln(
      '      <stop offset="100%" stop-color="$color2" stop-opacity="0.05"/>',
    );
    buffer.writeln('    </radialGradient>');
    buffer.writeln(
      '    <linearGradient id="core" x1="0%" y1="0%" x2="100%" y2="100%">',
    );
    buffer.writeln('      <stop offset="0%" stop-color="$color1"/>');
    buffer.writeln('      <stop offset="100%" stop-color="$color3"/>');
    buffer.writeln('    </linearGradient>');
    buffer.writeln('  </defs>');

    // Background glow
    buffer.writeln(
      '  <circle cx="$center" cy="$center" r="${80 + influence}" fill="url(#bg)"/>',
    );

    // Generate shapes based on type
    switch (shapeType) {
      case 0: // Orbital rings
        _generateOrbitalRings(buffer, center, color1, color2, rng);
        break;
      case 1: // Geometric crystal
        _generateCrystal(buffer, center, color1, color3, rng);
        break;
      case 2: // Pulse rings
        _generatePulseRings(buffer, center, color1, color2, color3, rng);
        break;
      case 3: // Node network
        _generateNodeNetwork(buffer, center, color1, color2, rng);
        break;
      case 4: // Geometric mandala
        _generateMandala(buffer, center, color1, color3, rng);
        break;
    }

    // Center core
    buffer.writeln(
      '  <circle cx="$center" cy="$center" r="${20 + rng.nextInt(15)}" fill="url(#core)" opacity="0.9"/>',
    );

    buffer.writeln('</svg>');
    return buffer.toString();
  }

  void _generateOrbitalRings(
    StringBuffer buf,
    double center,
    String c1,
    String c2,
    Random rng,
  ) {
    for (int i = 0; i < 3; i++) {
      final r = 40 + i * 25;
      final strokeW = 2.0 + rng.nextDouble() * 3;
      buf.writeln(
        '  <ellipse cx="$center" cy="$center" rx="$r" ry="${r * 0.7}" '
        'fill="none" stroke="$c1" stroke-width="$strokeW" opacity="${0.3 + i * 0.2}" '
        'transform="rotate(${rng.nextInt(60) - 30} $center $center)"/>',
      );
    }
  }

  void _generateCrystal(
    StringBuffer buf,
    double center,
    String c1,
    String c2,
    Random rng,
  ) {
    final points = <String>[];
    final sides = 5 + rng.nextInt(4); // 5-8 sides
    for (int i = 0; i < sides; i++) {
      final angle = (2 * pi * i / sides) - pi / 2;
      final r = 50 + rng.nextInt(20);
      final x = center + r * cos(angle);
      final y = center + r * sin(angle);
      points.add('$x,$y');
    }
    buf.writeln(
      '  <polygon points="${points.join(' ')}" fill="$c1" opacity="0.6"/>',
    );
    buf.writeln(
      '  <polygon points="${points.join(' ')}" fill="none" stroke="$c2" stroke-width="2"/>',
    );
  }

  void _generatePulseRings(
    StringBuffer buf,
    double center,
    String c1,
    String c2,
    String c3,
    Random rng,
  ) {
    for (int i = 0; i < 4; i++) {
      final r = 25 + i * 20;
      final opacity = 0.6 - i * 0.12;
      buf.writeln(
        '  <circle cx="$center" cy="$center" r="$r" fill="none" '
        'stroke="${i % 2 == 0 ? c1 : c2}" stroke-width="${3 - i * 0.5}" opacity="$opacity"/>',
      );
    }
  }

  void _generateNodeNetwork(
    StringBuffer buf,
    double center,
    String c1,
    String c2,
    Random rng,
  ) {
    final nodes = <Map<String, double>>[];
    for (int i = 0; i < 5; i++) {
      final angle = rng.nextDouble() * 2 * pi;
      final r = 30 + rng.nextInt(40);
      nodes.add({'x': center + r * cos(angle), 'y': center + r * sin(angle)});
    }
    // Draw connections
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        buf.writeln(
          '  <line x1="${nodes[i]['x']}" y1="${nodes[i]['y']}" '
          'x2="${nodes[j]['x']}" y2="${nodes[j]['y']}" '
          'stroke="$c2" stroke-width="1" opacity="0.4"/>',
        );
      }
    }
    // Draw nodes
    for (final node in nodes) {
      final r = 5 + rng.nextInt(8);
      buf.writeln(
        '  <circle cx="${node['x']}" cy="${node['y']}" r="$r" fill="$c1" opacity="0.8"/>',
      );
    }
  }

  void _generateMandala(
    StringBuffer buf,
    double center,
    String c1,
    String c2,
    Random rng,
  ) {
    final petals = 6 + rng.nextInt(6);
    for (int i = 0; i < petals; i++) {
      final angle = (2 * pi * i / petals) - pi / 2;
      final x = center + 45 * cos(angle);
      final y = center + 45 * sin(angle);
      buf.writeln(
        '  <ellipse cx="$x" cy="$y" rx="15" ry="25" '
        'fill="$c1" opacity="0.5" transform="rotate(${angle * 180 / pi + 90} $x $y)"/>',
      );
    }
    buf.writeln(
      '  <circle cx="$center" cy="$center" r="25" fill="$c2" opacity="0.7"/>',
    );
  }

  /// 生成 Base64 SVG 用於圖片顯示
  static String svgToBase64(String svg) {
    final bytes = Uri.encodeComponent(svg);
    return 'data:image/svg+xml;charset=utf-8,$bytes';
  }
}

/// 工廠：取得預設生成器
AppearanceGenerator getDefaultAppearanceGenerator() {
  return GeometricAppearanceGenerator();
}
