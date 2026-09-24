// workflow_templates_test.dart
// [小葵 2026-08-15 Blue 指示] 示範工作流是門面——全部範本必須：
// 1. 每條連線的 port 存在於 NodeTypePorts（防「匯入時靜默丟線」：
//    port 不存在 → loadFromStore typeOk 驗證失敗 → 連線直接消失）
// 2. 靜態分析零錯誤（analyzer = 「測試」按鈕同款引擎）
//
// 跑法：flutter test test/workflow_templates_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/vault/vault_templates.dart';
import 'package:bridge_app/widgets/canvas/v2/canvas_controller.dart' show NodeTypePorts;
import 'package:bridge_app/models/entity_graph/entity.dart';
import 'package:bridge_app/widgets/canvas/v2/node_connection.dart';
import 'package:bridge_app/widgets/canvas/v2/workflow_static_analyzer.dart';

void main() {
  final templates = VaultTemplateService.instance.getBuiltinTemplates();

  test('範本清單非空（8 個門面）', () {
    expect(templates.length, greaterThanOrEqualTo(8),
        reason: '內建範本應有 8 個以上');
  });

  for (final template in templates) {
    group('範本「${template.name}」（${template.id}）', () {
      test('連線 port 全部存在（不會被匯入靜默丟線）', () {
        final errors = <String>[];
        for (var i = 0; i < template.connections.length; i++) {
          final conn = template.connections[i];
          final fromIdx = conn['from'] as int;
          final toIdx = conn['to'] as int;

          if (fromIdx < 0 || fromIdx >= template.nodes.length) {
            errors.add('連線 #$i: from 索引 $fromIdx 超出節點範圍');
            continue;
          }
          if (toIdx < 0 || toIdx >= template.nodes.length) {
            errors.add('連線 #$i: to 索引 $toIdx 超出節點範圍');
            continue;
          }

          final fromTypeStr = template.nodes[fromIdx]['type'] as String? ?? '';
          final toTypeStr = template.nodes[toIdx]['type'] as String? ?? '';
          final fromPort = conn['fromPort'] as String? ?? 'output';
          final toPort = conn['toPort'] as String? ?? 'input';

          final fromType = WorkflowNodeType.values
              .where((t) => t.name == fromTypeStr)
              .firstOrNull;
          final toType = WorkflowNodeType.values
              .where((t) => t.name == toTypeStr)
              .firstOrNull;
          if (fromType == null || toType == null) {
            errors.add('連線 #$i: 未知節點型別 $fromTypeStr→$toTypeStr');
            continue;
          }

          final fromPorts = NodeTypePorts.portsFor(fromType);
          final toPorts = NodeTypePorts.portsFor(toType);
          if (!fromPorts.any((p) => p.name == fromPort && p.isOutput)) {
            errors.add(
                '連線 #$i: $fromTypeStr 沒有輸出 port「$fromPort」（實有：'
                '${fromPorts.where((p) => p.isOutput).map((p) => p.name).join(',')}）');
          }
          if (!toPorts.any((p) => p.name == toPort && !p.isOutput)) {
            errors.add(
                '連線 #$i: $toTypeStr 沒有輸入 port「$toPort」（實有：'
                '${toPorts.where((p) => !p.isOutput).map((p) => p.name).join(',')}）');
          }
        }
        expect(errors, isEmpty,
            reason: '這些連線會在匯入時被靜默丟棄（畫布看不到線）:\n'
                '${errors.join('\n')}');
      });

      test('靜態分析零錯誤（測試按鈕同款引擎）', () {
        // 組 nodesData / connections——與 canvas_v2_workspace._runStaticTest 同構
        final nodesData = <String, dynamic>{};
        final idByIndex = <int, String>{};
        for (var i = 0; i < template.nodes.length; i++) {
          final def = template.nodes[i];
          idByIndex[i] = 'n$i';
          final params = (def['params'] as Map<String, dynamic>? ?? {})
              .cast<String, dynamic>();
          nodesData['n$i'] = {
            'nodeType': def['type'],
            'params': params,
            'label': params['label']?.toString() ?? def['type'].toString(),
          };
        }
        final conns = <NodeConnection>[];
        for (var i = 0; i < template.connections.length; i++) {
          final c = template.connections[i];
          conns.add(NodeConnection(
            id: 'c$i',
            fromNodeId: idByIndex[c['from'] as int]!,
            fromPortId: c['fromPort'] as String? ?? 'output',
            toNodeId: idByIndex[c['to'] as int]!,
            toPortId: c['toPort'] as String? ?? 'input',
          ));
        }

        final report = WorkflowStaticAnalyzer.analyze(
          nodesData: nodesData,
          connections: conns,
          allNodeIds: nodesData.keys.toSet(),
        );
        final errors =
            report.issues.where((issue) => issue.isError).map((i) => i.message).toList();
        expect(errors, isEmpty,
            reason: '範本是門面，測試按鈕不能報錯:\n${errors.join('\n')}');
      });
    });
  }
}
