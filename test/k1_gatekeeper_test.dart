// [小葵 2026-09-21] R3——K1 守門員回歸鎖
// 鎖：規則層命中 need 關鍵詞、訓練頭往返（train→softmax→預測）、
// 單調升級守門、escalate 語意。
// 純邏輯測試（不依賴 embedding 模型——head 用合成向量驗證）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/decision/decision_head.dart';
import 'package:bridge_app/services/decision/k1_gatekeeper.dart';

void main() {
  test('規則層：生日/代碼/再問一次 → need（冷啟動保底）', () async {
    final k1 = K1Gatekeeper.instance;
    for (final msg in ['小葵的生日是哪一天？', 'ZETA-77 的彩虹碼是多少', '再考你一次：上次說的通關碼']) {
      final d = await k1.classify(msg);
      expect(d.needMemory, isTrue, reason: '「$msg」應判 need（寧多查不漏查）');
      expect(d.source, 'rule');
      expect(d.escalated, isFalse);
    }
  });

  test('訓練頭：train→softmax 往返（合成線性可分樣本）', () {
    final dim = 8;
    final samples = <(List<double>, String)>[];
    // 造 4 類可分樣本：每類一個明確方向
    final dirs = <String, List<double>>{
      K1Labels.needMemoryLookup: [1, 0, 0, 0, 0, 0, 0, 0],
      K1Labels.repeatQuery: [0, 1, 0, 0, 0, 0, 0, 0],
      K1Labels.directAction: [0, 0, 1, 0, 0, 0, 0, 0],
      K1Labels.generalChat: [0, 0, 0, 1, 0, 0, 0, 0],
    };
    final rnd = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < 40; i++) {
      for (final e in dirs.entries) {
        final x = [
          for (var d = 0; d < dim; d++)
            e.value[d] + ((rnd + i * 7 + d * 13) % 10) * 0.01,
        ];
        samples.add((x, e.key));
      }
    }
    final head = DecisionHeadTrainer.train(samples);
    expect(head.dim, dim);
    expect(head.sampleCount, 160);

    // 各類方向預測應正確
    for (final e in dirs.entries) {
      final probs = head.softmax(e.value);
      final best = head.labels[probs.indexOf(probs.reduce((a, b) => a > b ? a : b))];
      expect(best, e.key, reason: '${e.key} 方向應被正確分類');
    }
  });

  test('DecisionStore 單調升級：爛頭不能覆蓋好頭', () {
    final dir = Directory.systemTemp.createTempSync('k1_store_test');
    final store = DecisionStore('${dir.path}/head.json');
    final good = DecisionHead(
      labels: K1Labels.all,
      w: [for (var d = 0; d < 4; d++) [0.1, 0.1, 0.1, 0.1]],
      b: [0, 0, 0, 0],
      trainedAtMs: 1,
      sampleCount: 100,
      holdoutAcc: 0.95,
    );
    expect(store.saveMonotonic(good, null), isTrue);
    expect(store.load()!.holdoutAcc, 0.95);

    final bad = DecisionHead(
      labels: K1Labels.all,
      w: [for (var d = 0; d < 4; d++) [0.1, 0.1, 0.1, 0.1]],
      b: [0, 0, 0, 0],
      trainedAtMs: 2,
      sampleCount: 50,
      holdoutAcc: 0.60, // 保留集變差→不得替換
    );
    expect(store.saveMonotonic(bad, good), isFalse,
        reason: '單調升級鐵則：爛樣本污染防護');
    expect(store.load()!.holdoutAcc, 0.95, reason: '仍是好頭');

    final better = DecisionHead(
      labels: K1Labels.all,
      w: [for (var d = 0; d < 4; d++) [0.2, 0.2, 0.2, 0.2]],
      b: [0, 0, 0, 0],
      trainedAtMs: 3,
      sampleCount: 200,
      holdoutAcc: 0.97,
    );
    expect(store.saveMonotonic(better, good), isTrue);
    expect(store.load()!.sampleCount, 200);

    dir.deleteSync(recursive: true);
  });

  test('escalate 語意：沒頭沒模型 → escalated=true（寧升級不自信錯）', () async {
    final k1 = K1Gatekeeper.instance;
    k1.loadHead(null); // 清頭
    final d = await k1.classify('今天天氣如何');
    expect(d.escalated, isTrue);
    expect(d.source, 'escalate');
  });
}
