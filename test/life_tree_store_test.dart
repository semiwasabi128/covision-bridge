// [小葵 2026-09-21] R1 生命樹回歸鎖——真 DB 往返測試
// 鎖：雙主幹表存在、dream 結論卡寫入讀回、thought_branch 寫入+重評、
// snapshot 計數正確。用臨時 DB（不碰真 causal_ledger）。
//
// 注意：LifeTreeStore._open() 開的是固定路徑——測試透過 HOME 環境
// 變數導到暫存目錄，讓路徑解析落到 fallback 前的暫存位置。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/life_tree/life_tree_store.dart';

void main() {
  late Directory tmpHome;
  late Directory targetDir;

  setUp(() {
    tmpHome = Directory.systemTemp.createTempSync('life_tree_test');
    targetDir = tmpHome;
    // [小葵 2026-09-21 抓包修正] 路徑注入——測試絕不碰真 causal_ledger.db
    LifeTreeStore.dbPathOverride = '${tmpHome.path}/causal_ledger.db';
  });

  tearDown(() {
    LifeTreeStore.instance.dispose();
    try {
      tmpHome.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('dream 結論卡寫入→讀回（夢境主幹往返）', () {
    final store = LifeTreeStore.instance;
    final id = store.addDream(LifeTreeDream(
      dreamSessionId: 'dream_20260921_test',
      branchType: 'human_consensus',
      conclusion: '維持 escalate 閾值 0.7（Blue 拍板）',
      decision: 'maintain',
      sourceClues: ['K1 錯題本週 2 筆', '儀表紅燈：漏查率 3%'],
      companionIds: ['cmp_semiwasabi', 'cmp_xiaoqiao'],
      modelUsed: 'glm-5.3',
      createdAt: DateTime(2026, 9, 21, 20, 0),
    ));
    expect(id, greaterThan(0), reason: '寫入應回傳新 id');

    final dreams = store.recentDreams(limit: 5);
    expect(dreams, isNotEmpty);
    final d = dreams.firstWhere((x) => x.id == id);
    expect(d.branchType, 'human_consensus');
    expect(d.conclusion, contains('0.7'));
    expect(d.sourceClues.length, 2);
    expect(d.companionIds, contains('cmp_xiaoqiao'));
    expect(d.modelUsed, 'glm-5.3');
  });

  test('thought_branch 寫入→遺憾清單→夢境重評（歷史主幹子枝幹全流程）', () {
    final store = LifeTreeStore.instance;
    final bid = store.addThoughtBranch(LifeTreeThoughtBranch(
      ledgerId: 1498, // 掛在既有執行記錄上
      thought: '當時想過改用 Qwen-RLCD 當底座，但選了 EmbeddingGemma',
      whyNotTaken: 'benchmark 未跑，不確定中文能力',
      createdAt: DateTime(2026, 9, 21, 21, 0),
    ));
    expect(bid, greaterThan(0));

    // 遺憾清單看得到
    final pending = store.unrevisitedBranches();
    expect(pending.any((b) => b.id == bid), isTrue,
        reason: '未重評的分支應出現在 K5 議程素材');

    // 夢境重評：superseded（EmbeddingGemma 97% 已實證，不需要換）
    final n = store.markRevisited(bid, 'superseded');
    expect(n, 1);

    // 重評後離開遺憾清單
    final pending2 = store.unrevisitedBranches();
    expect(pending2.any((b) => b.id == bid), isFalse);
  });

  test('snapshot 計數（R4 儀表地基）', () {
    final store = LifeTreeStore.instance;
    final before = store.snapshot();
    store.addDream(LifeTreeDream(
      branchType: 'agent_consensus',
      conclusion: '測試卡',
      decision: 'maintain',
      createdAt: DateTime(2026, 9, 21, 22, 0),
    ));
    final after = store.snapshot();
    expect(after['dreams'], before['dreams']! + 1);
    expect(after['unrevisited'], greaterThanOrEqualTo(0));
  });
}
