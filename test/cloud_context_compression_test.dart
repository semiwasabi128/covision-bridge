// [小葵 2026-09-21] 雲端 context 壓縮行為鎖——9/21 astra $9 事件修復的回歸測試
// 鐵則（Blue 2026-09-21）：上下文窗口不足 & 窗口太長燒錢，修復後正式走入歷史。
//
// 鎖死的行為：
//  1. 儲存層不動（方法只就地改送出的 messages，本測試驗證無 IO）
//  2. 超過門檻的長對話 → 壓縮（中間→摘要+事實層、最近 8 輪原文保留）
//  3. user 全文逐字保留在事實層A（教練指示=決策攜帶者）
//  4. assistant 的 commit hash / 全大寫檔名 / 決策訊號行逐字保留在事實層B
//  5. 短對話（中間 <12 則）不壓——避免頻繁重壓破壞 cache prefix
//  6. 壓縮後總長大幅縮小

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/agent_loop/production_agent_loop_llm_client.dart';

Map<String, dynamic> _m(String role, String content) =>
    {'role': role, 'content': content};

void main() {
  late ProductionAgentLoopLLMClient client;

  setUp(() {
    client = ProductionAgentLoopLLMClient();
  });

  test('短對話（中間段 <12 則）完全不動', () {
    final msgs = <Map<String, dynamic>>[
      _m('system', '你是小橋'),
      _m('user', '初始任務'),
      ...List.generate(10, (i) => _m(i.isEven ? 'user' : 'assistant', '第 $i 輪')),
    ];
    final before = List.of(msgs);
    client.compressCloudContext(msgs);
    expect(msgs.length, before.length);
    expect(msgs, before); // 一字不動
  });

  test('長對話壓縮：最近 8 輪原文保留 + 摘要標記出現', () {
    final msgs = <Map<String, dynamic>>[
      _m('system', '你是小橋'),
      _m('user', '初始任務：測試排程'),
      ...List.generate(40, (i) {
        if (i.isEven) return _m('user', '教練指示 $i：把咖啡排程改到 10:30');
        return _m('assistant', '夥伴，第 $i 輪回報完成，commit a1b2c3d4 已落地');
      }),
    ];
    final originalLen = msgs.length;
    client.compressCloudContext(msgs);

    // 結構：system + 初始任務 + 1 則摘要 + 最近 8 輪 = 11
    expect(msgs.length, 11);
    expect(msgs.length, lessThan(originalLen));

    // system 釘在前、初始任務第二
    expect(msgs[0]['role'], 'system');
    expect(msgs[1]['content'], contains('初始任務'));

    // 摘要塊存在且帶標記
    expect(msgs[2]['content'].toString().contains('[歷史摘要]'), isTrue);

    // 最近 8 輪原文在尾部（最後一則 = 原第 39 輪 assistant）
    expect(msgs.last['content'].toString().contains('第 39 輪'), isTrue);
  });

  test('事實層A：user 指示全文逐字保留（決策不滅）', () {
    final coachOrder = '新規則上線（d21bed9d）：結構性續跑。沒有 tool call 又沒有 '
        '[[TASK_DONE]] 的回覆會被系統自動催續跑（最多5次）';
    final msgs = <Map<String, dynamic>>[
      _m('system', 'sys'),
      _m('user', '初始任務'),
      _m('user', coachOrder), // 在中間段
      ...List.generate(30, (i) => _m('assistant', '過程回報 $i')),
    ];
    client.compressCloudContext(msgs);
    final all = msgs.map((m) => m['content'].toString()).join('\n');
    expect(all.contains(coachOrder), isTrue,
        reason: 'user 教練指示必須逐字存活在事實層A');
  });

  test('事實層B：commit hash 與決策訊號行逐字保留', () {
    final msgs = <Map<String, dynamic>>[
      _m('system', 'sys'),
      _m('user', '初始任務'),
      ...List.generate(6, (i) => _m('user', '指示 $i')),
      _m('assistant', '收口：commit 03d43e12 兩處修正已落地'),
      _m('assistant', '驗收抓包：commit a8f3d29e 不存在，宣稱不實，撤回'),
      _m('assistant', '這行是純閒聊沒有任何訊號'),
      ...List.generate(20, (i) => _m('assistant', '過程 $i')),
    ];
    client.compressCloudContext(msgs);
    final all = msgs.map((m) => m['content'].toString()).join('\n');
    expect(all.contains('03d43e12'), isTrue);
    expect(all.contains('a8f3d29e'), isTrue);
    expect(all.contains('撤回'), isTrue);
    expect(all.contains('這行是純閒聊沒有任何訊號'), isFalse,
        reason: '無訊號閒聊行可被壓掉（這正是壓縮的意義）');
  });

  test('壓縮率：61K 字元等級的歷史大幅縮小', () {
    final msgs = <Map<String, dynamic>>[
      _m('system', 'sys'),
      _m('user', '初始任務'),
      ...List.generate(90, (i) {
        if (i.isEven) {
          return _m('user', '教練指示 $i ' * 5); // 每則 ~130 字
        }
        // 真實對話樣貌：大部分是過程閒聊，每 5 輪才有一行含 hash 的收口
        final body = List.generate(
            8, (j) => '過程回報 $i-$j：這一行是普通敘述沒有任何訊號').join('\n');
        final withHash = i % 5 == 0 ? '\ncommit ${i.toRadixString(16)}fedcba 已落地' : '';
        return _m('assistant', body + withHash);
      }),
    ];
    var totalBefore = 0;
    for (final m in msgs) {
      totalBefore += m['content'].toString().length;
    }
    client.compressCloudContext(msgs);
    var totalAfter = 0;
    for (final m in msgs) {
      totalAfter += m['content'].toString().length;
    }
    expect(totalAfter, lessThan(totalBefore * 0.7),
        reason: '壓縮後應 <70% 原大小（before=$totalBefore after=$totalAfter）');
  });
}
