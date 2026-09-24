import 'package:bridge_app/models/task_evidence.dart';
import 'package:flutter_test/flutter_test.dart';

class _Turn {
  final dynamic toolCall;
  final dynamic toolResult;
  _Turn({required this.toolCall, this.toolResult});
}

class _Call {
  final String name;
  final Map<String, dynamic> args;
  _Call(this.name, [Map<String, dynamic> args = const {}]) : args = args;
}

class _Result {
  final bool success;
  final String? mediaUrl;
  final Map<String, dynamic>? metadata;
  _Result({required this.success, this.mediaUrl, this.metadata});
}

void main() {
  test('generate_image 成功會產生 image task，raw 欄位不洩漏', () {
    final tasks = TaskEvidenceBuilder.build([
      _Turn(
        toolCall: _Call('generate_image'),
        toolResult: _Result(
          success: true,
          mediaUrl: '/tmp/foo.png',
          metadata: const {'prompt': 'secret prompt', 'title': 'safe title'},
        ),
      ),
    ]);
    expect(tasks, hasLength(1));
    expect(tasks.single['kind'], 'image');
    expect(tasks.single['outcome'], 'completed');
    expect(tasks.single['headline'], '已生成 1 張圖片');
    expect(tasks.single['safeMetadata'], {'title': 'safe title'});
    expect(tasks.single.toString(), isNot(contains('secret prompt')));
  });

  test('空 turns 回傳空 list，不會 throw', () {
    final tasks = TaskEvidenceBuilder.build(<_Turn>[]);
    expect(tasks, isEmpty);
  });

  test('不支援工具完全不出現在 tasks', () {
    final tasks = TaskEvidenceBuilder.build([
      _Turn(
        toolCall: _Call('reverse_shell'),
        toolResult: _Result(success: true, mediaUrl: '/tmp/x'),
      ),
    ]);
    expect(tasks, isEmpty);
  });

  test('fromMetadata 讀回 UI 會看到的 List<TaskEvidence>', () {
    final raw = {
      'tasks': [
        {
          'kind': 'image',
          'outcome': 'completed',
          'headline': '已生成 1 張圖片',
          'summary': '',
          'actions': [
            {'label': '開啟', 'view': 'media'},
          ],
          'mediaUrl': '/tmp/foo.png',
        },
      ],
    };
    final list = TaskEvidence.fromMetadata(raw);
    expect(list, hasLength(1));
    expect(list.first.kind, TaskEvidenceKind.image);
    expect(list.first.actions.single.label, '開啟');
    expect(list.first.mediaUrl, '/tmp/foo.png');
  });

  test('連續 canvas 變更會被合併成一張卡', () {
    final tasks = TaskEvidenceBuilder.build([
      _Turn(
        toolCall: _Call('canvas_place'),
        toolResult: _Result(success: true),
      ),
      _Turn(
        toolCall: _Call('canvas_connect'),
        toolResult: _Result(success: true),
      ),
    ]);
    expect(tasks, hasLength(1));
    expect(tasks.single['kind'], 'canvas');
    expect(tasks.single['summary'], '2 個 Canvas 變更已生效');
  });
}
