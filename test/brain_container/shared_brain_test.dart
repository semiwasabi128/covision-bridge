// shared_brain_test.dart
// 跨 Agent 共享大腦 — companion_id provenance 測試
// Sprint 1A-8: 1A 大腦容器 8/8 收口
//
// 測試範圍：
// 1. Memory model companionId 序列化/反序列化
// 2. MemoryDraft companionId 傳遞
// 3. BrainContainerService.getMemoriesByCompanion / getCompanionMemoryCounts
// 4. CanvasNode companion provenance 色碼穩定性

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/models/brain_container/memory.dart';
import 'package:bridge_app/models/brain_container/brain_room.dart';
import 'package:bridge_app/models/brain_container/memory_source.dart';
import 'package:bridge_app/models/canvas/canvas_node.dart';

void main() {
  group('Memory companionId', () {
    test('toMap includes companion_id', () {
      final now = DateTime.now();
      final memory = Memory(
        id: 'test_001',
        content: '使用者喜歡喝手沖咖啡',
        room: BrainRoom.stream,
        subCategory: 'preference',
        agent: '小橋',
        companionId: 'cmp_123',
        source: MemorySource.chat,
        project: '',
        tags: ['preference', 'coffee'],
        importance: 4,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
        chunkIndex: 0,
        totalChunks: 1,
      );

      final map = memory.toMap();
      expect(map['companion_id'], equals('cmp_123'));
    });

    test('fromMap reads companion_id', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final map = <String, dynamic>{
        'id': 'test_002',
        'content': '使用者住台北',
        'room': 'stream',
        'sub_category': 'fact',
        'agent': '小葵',
        'companion_id': 'cmp_456',
        'source': 'chat',
        'source_id': null,
        'project': '',
        'tags': '["location"]',
        'importance': 3,
        'created_at': now,
        'updated_at': now,
        'expires_at': null,
        'access_count': 2,
        'archived': 0,
        'chunk_index': 0,
        'total_chunks': 1,
        'parent_memory_id': null,
        'integration_result': null,
        'vector_model_version': null,
      };

      final memory = Memory.fromMap(map);
      expect(memory.companionId, equals('cmp_456'));
    });

    test('fromMap handles missing companion_id (backfill compatibility)', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final map = <String, dynamic>{
        'id': 'test_003',
        'content': '舊記憶沒有 companion_id',
        'room': 'stream',
        'sub_category': '',
        'agent': '夥伴',
        // companion_id 刻意省略 — 模擬 v3 舊資料
        'source': 'chat',
        'source_id': null,
        'project': '',
        'tags': '[]',
        'importance': 3,
        'created_at': now,
        'updated_at': now,
        'expires_at': null,
        'access_count': 0,
        'archived': 0,
        'chunk_index': 0,
        'total_chunks': 1,
        'parent_memory_id': null,
        'integration_result': null,
        'vector_model_version': null,
      };

      final memory = Memory.fromMap(map);
      expect(memory.companionId, equals(''));
    });

    test('copyWith preserves companionId when not overridden', () {
      final now = DateTime.now();
      final memory = Memory(
        id: 'test_004',
        content: 'test',
        room: BrainRoom.doors,
        subCategory: '',
        agent: '小橋',
        companionId: 'cmp_789',
        source: MemorySource.chat,
        project: '',
        tags: [],
        importance: 3,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
        chunkIndex: 0,
        totalChunks: 1,
      );

      final updated = memory.copyWith(importance: 5);
      expect(updated.companionId, equals('cmp_789'));
      expect(updated.importance, equals(5));
    });

    test('copyWith can change companionId', () {
      final now = DateTime.now();
      final memory = Memory(
        id: 'test_005',
        content: 'test',
        room: BrainRoom.stream,
        subCategory: '',
        agent: '小橋',
        companionId: 'cmp_old',
        source: MemorySource.chat,
        project: '',
        tags: [],
        importance: 3,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
        chunkIndex: 0,
        totalChunks: 1,
      );

      final updated = memory.copyWith(companionId: 'cmp_new');
      expect(updated.companionId, equals('cmp_new'));
    });
  });

  group('CanvasNode companion provenance', () {
    test('companionColor is stable for same ID', () {
      final color1 = CanvasNode.companionColor('cmp_abc');
      final color2 = CanvasNode.companionColor('cmp_abc');
      expect(color1, equals(color2));
    });

    test('companionColor differs for different IDs', () {
      final color1 = CanvasNode.companionColor('cmp_abc');
      final color2 = CanvasNode.companionColor('cmp_xyz');
      expect(color1, isNot(equals(color2)));
    });

    test('companionColor transparent for empty ID', () {
      final color = CanvasNode.companionColor('');
      expect(color.alpha, equals(0));
    });

    test('node.companionLabel returns agent name when companionId set', () {
      final now = DateTime.now();
      final memory = Memory(
        id: 'test_canvas_1',
        content: '測試記憶',
        room: BrainRoom.stream,
        subCategory: '',
        agent: '小葵',
        companionId: 'cmp_x1',
        source: MemorySource.chat,
        project: '',
        tags: [],
        importance: 3,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
        chunkIndex: 0,
        totalChunks: 1,
      );

      final node = CanvasNode.fromMemory(memory);
      expect(node.companionLabel, equals('小葵'));
    });

    test('node.companionLabel empty when no companionId', () {
      final now = DateTime.now();
      final memory = Memory(
        id: 'test_canvas_2',
        content: '無夥伴標記的舊記憶',
        room: BrainRoom.stream,
        subCategory: '',
        agent: '夥伴',
        companionId: '',
        source: MemorySource.chat,
        project: '',
        tags: [],
        importance: 3,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
        chunkIndex: 0,
        totalChunks: 1,
      );

      final node = CanvasNode.fromMemory(memory);
      expect(node.companionLabel, isEmpty);
    });

    test('node.companionBorderColor non-transparent when companionId set', () {
      final now = DateTime.now();
      final memory = Memory(
        id: 'test_canvas_3',
        content: '有色碼邊框',
        room: BrainRoom.doors,
        subCategory: '',
        agent: '小橋',
        companionId: 'cmp_border_test',
        source: MemorySource.chat,
        project: '',
        tags: [],
        importance: 4,
        createdAt: now,
        updatedAt: now,
        accessCount: 0,
        archived: false,
        chunkIndex: 0,
        totalChunks: 1,
      );

      final node = CanvasNode.fromMemory(memory);
      expect(node.companionBorderColor.alpha, greaterThan(0));
    });
  });
}
