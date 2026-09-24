// task_intent_classifier_test.dart
// [隊友訊息流 C6 2026-09-08] 白話 10 句驗收（Blue 風格農場題材）
// 設計稿 C6 驗收：任務句觸發率、閒聊句零誤派

import 'package:flutter_test/flutter_test.dart';
import 'package:bridge_app/services/tasks/task_intent_classifier.dart';

void main() {
  group('任務句觸發（應派工）', () {
    final taskSentences = [
      '幫我把這週農場照片整理成週報',
      '請你整理鹿角蕨的照顧筆記做成一份文件',
      '幫我生成三張 IG 圖卡',
      '麻煩你統計這個月的澆水紀錄',
      '幫我規劃下週的農場巡查排程',
      '請你分析這批照片裡的作物健康狀況',
    ];
    for (final s in taskSentences) {
      test('「$s」→ task', () {
        expect(TaskIntentClassifier.classify(s), TaskIntent.task,
            reason: '任務句誤判為對話＝功能失效');
      });
    }
  });

  group('閒聊句零誤派', () {
    final chatSentences = [
      '哈囉',
      '今天天氣真好',
      '謝謝你幫忙',
      '你覺得這張照片拍得如何',
      '鹿角蕨為什麼葉子變黃',
      '這是什麼品種',
      '早安！今天要去農場嗎',
      '我想問一下上次那份筆記放哪了',
      '哈哈這個太好笑了',
      '嗯嗯好',
    ];
    for (final s in chatSentences) {
      test('「$s」→ chat', () {
        expect(TaskIntentClassifier.classify(s), TaskIntent.chat,
            reason: '閒聊句誤派工＝打擾信任，保守原則被違反');
      });
    }
  });

  group('邊界案例', () {
    test('短指令（<6字）不派—— 寧漏不誤', () {
      expect(TaskIntentClassifier.classify('幫我做'), TaskIntent.chat);
    });

    test('有前綴無任務動詞 → 對話（「幫我看看」= 想知道，非產出）', () {
      expect(TaskIntentClassifier.classify('幫我看看這個狀況'), TaskIntent.chat);
    });

    test('問句形式的任務請求 → 對話（保守）', () {
      expect(
          TaskIntentClassifier.classify('幫我整理一下好嗎'), TaskIntent.chat);
    });
  });
}
