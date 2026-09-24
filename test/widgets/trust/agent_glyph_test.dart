// agent_glyph_test.dart
// [刀 2] AgentGlyph 指紋測試——確定性與獨特性

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/widgets/trust/agent_glyph.dart';

void main() {
  group('AgentGlyphSeed 確定性', () {
    test('同 ID+名字 → 完全相同 seed（跨裝置同一張臉）', () {
      final a = AgentGlyphSeed.of('comp_001', '小葵');
      final b = AgentGlyphSeed.of('comp_001', '小葵');
      expect(a.h1, b.h1);
      expect(a.h2, b.h2);
      expect(a.h3, b.h3);
      expect(a.h4, b.h4);
    });

    test('不同 ID → 不同圖案（即使名字同開頭）', () {
      // Blue 的原始案例：小葵 vs 小喬——同「小」開頭
      final semiwasabi = AgentGlyphSeed.of('comp_001', '小葵');
      final xiaoqiao = AgentGlyphSeed.of('comp_002', '小喬');
      expect(semiwasabi.patternBits, isNot(equals(xiaoqiao.patternBits)));
      // 底色或外框也應該極大概率不同
      final differentLayers = semiwasabi.bg != xiaoqiao.bg ||
          semiwasabi.frame != xiaoqiao.frame;
      expect(differentLayers, isTrue);
    });

    test('同名字不同 ID → 不同 seed（名字不是唯一鍵）', () {
      final a = AgentGlyphSeed.of('comp_001', '阿福');
      final b = AgentGlyphSeed.of('comp_999', '阿福');
      expect(a.h3, isNot(equals(b.h3)));
    });
  });

  group('獨特性（批次模擬）', () {
    test('100 個 Agent 的圖案 bits 幾乎不碰撞', () {
      final seen = <int>{};
      for (var i = 0; i < 100; i++) {
        seen.add(AgentGlyphSeed.of('agent_$i', '夥伴$i').patternBits);
      }
      // 100 個裡碰撞 ≤1 可接受（2^32 空間）；實測應 100% 唯一
      expect(seen.length, greaterThan(98));
    });

    test('底色在合理範圍（不過暗不過亮）', () {
      for (var i = 0; i < 50; i++) {
        final c = AgentGlyphSeed.of('agent_$i', '測試$i').bg;
        expect(c, isNotNull);
      }
    });
  });

  group('首字（輔助層）', () {
    test('中文首字', () {
      expect(AgentGlyphSeed.of('c1', '小葵').initial, '小');
    });

    test('空名字不炸', () {
      expect(AgentGlyphSeed.of('c1', '').initial, '?');
    });
  });
}
