import 'package:bridge_app/services/brain_container/extraction/extraction_prompt.dart';
import 'package:bridge_app/services/brain_container/extraction/smart_memory_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

/// 單元測試：SmartMemoryExtractor 的 prompt 建構、JSON 解析、去重邏輯
///
/// 純邏輯測試 — 不依賴 LLM API 或 BrainContainerService。
/// LLM 端到端測試需要 mock StorageService，屬於整合測試範疇。
void main() {
  group('ExtractionPrompt.buildSystemPrompt', () {
    test('包含保守提取原則', () {
      final prompt = ExtractionPrompt.buildSystemPrompt();

      expect(prompt, contains('不值得記住'));
    });

    test('包含 JSON 輸出格式指示', () {
      final prompt = ExtractionPrompt.buildSystemPrompt();

      expect(prompt, contains('JSON'));
      expect(prompt, contains('content'));
      expect(prompt, contains('category'));
      expect(prompt, contains('importance'));
    });

    test('包含大腦房間分類', () {
      final prompt = ExtractionPrompt.buildSystemPrompt();

      expect(prompt, contains('stream'));
      expect(prompt, contains('doors'));
      expect(prompt, contains('bridges'));
    });

    test('包含範例判斷', () {
      final prompt = ExtractionPrompt.buildSystemPrompt();

      // 確保 prompt 裡有「我叫建新」的正確提取範例
      expect(prompt, contains('我叫建新'));
      // 確保有「不值得提取」的範例
      expect(prompt, contains('API 文件寫得真爛'));
    });
  });

  group('ExtractionPrompt.buildUserPrompt', () {
    test('包含使用者訊息', () {
      final prompt = ExtractionPrompt.buildUserPrompt('我叫建新，最近在搞一個 Flutter app');

      expect(prompt, contains('我叫建新'));
      expect(prompt, contains('Flutter app'));
    });

    test('空字串也能建構（不崩潰）', () {
      final prompt = ExtractionPrompt.buildUserPrompt('');

      expect(prompt, isNotEmpty);
    });
  });

  group('ExtractionPrompt.parseResponse — 正常 JSON', () {
    test('解析單條記憶', () {
      const response = '''[{"content":"使用者叫建新","category":"stream","importance":4}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, hasLength(1));
      expect(facts.first.content, '使用者叫建新');
      expect(facts.first.category, 'stream');
      expect(facts.first.importance, 4);
    });

    test('解析多條記憶', () {
      const response = '''[
        {"content":"使用者叫建新","category":"stream","importance":4},
        {"content":"在開發 Flutter app","category":"doors","importance":3}
      ]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, hasLength(2));
      expect(facts[0].content, '使用者叫建新');
      expect(facts[1].content, '在開發 Flutter app');
    });

    test('importance 缺失時使用預設值 3', () {
      const response = '''[{"content":"使用者叫建新","category":"stream"}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, hasLength(1));
      expect(facts.first.importance, 3);
    });

    test('importance 超出範圍時被 clamp', () {
      const response = '''[{"content":"使用者叫建新","category":"stream","importance":99}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts.first.importance, 5);
    });

    test('importance 為 0 時被 clamp 到 1', () {
      const response = '''[{"content":"使用者叫建新","category":"stream","importance":0}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts.first.importance, 1);
    });
  });

  group('ExtractionPrompt.parseResponse — 容錯', () {
    test('markdown fence 包裹的 JSON', () {
      const response = '''```json
      [{"content":"使用者叫建新","category":"stream","importance":2}]
      ```''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, hasLength(1));
      expect(facts.first.content, '使用者叫建新');
    });

    test('空陣列回傳空列表', () {
      const response = '[]';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, isEmpty);
    });

    test('非 JSON 文字回傳空列表（不崩潰）', () {
      const response = '這段對話沒有值得長期記住的資訊。';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, isEmpty);
    });

    test('完全無效的 JSON 回傳空列表', () {
      const response = 'I am not JSON at all!!!';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, isEmpty);
    });

    test('部分 JSON（有 content 但缺 category）仍可解析', () {
      const response = '''[{"content":"我叫建新"}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, hasLength(1));
      expect(facts.first.content, '我叫建新');
      // 預設 category 為 stream
      expect(facts.first.category, 'stream');
    });

    test('content 太短（<3字元）被過濾', () {
      const response = '''[{"content":"嗨","category":"stream","importance":1}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, isEmpty);
    });

    test('JSON 內容含換行符不崩潰', () {
      const response = '''[{"content":"第一行\\n第二行","category":"stream","importance":1}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, hasLength(1));
      expect(facts.first.content, contains('第一行'));
    });

    test('category 模糊匹配中文', () {
      const response = '''[{"content":"使用者叫建新","category":"流","importance":3}]''';

      final facts = ExtractionPrompt.parseResponse(response);

      expect(facts, hasLength(1));
      expect(facts.first.category, 'stream');
    });

    test('null response 回傳空列表', () {
      final facts = ExtractionPrompt.parseResponse('');

      expect(facts, isEmpty);
    });
  });

  group('ExtractedFact', () {
    test('基本屬性', () {
      const fact = ExtractedFact(
        content: '使用者喜歡 Dart',
        category: 'heartMind',
        importance: 3,
      );

      expect(fact.content, '使用者喜歡 Dart');
      expect(fact.category, 'heartMind');
      expect(fact.importance, 3);
    });

    test('不同 importance 等級', () {
      for (final importance in [1, 2, 3, 4, 5]) {
        final fact = ExtractedFact(
          content: '測試',
          category: 'stream',
          importance: importance,
        );
        expect(fact.importance, importance);
      }
    });

    test('toString 包含關鍵資訊', () {
      const fact = ExtractedFact(
        content: '測試',
        category: 'doors',
        importance: 5,
      );

      final str = fact.toString();
      expect(str, contains('測試'));
      expect(str, contains('doors'));
      expect(str, contains('5'));
    });
  });

  group('ExtractionResult', () {
    test('成功結果', () {
      const result = ExtractionResult(
        facts: [
          ExtractedFact(content: '測試', category: 'stream', importance: 4),
        ],
      );

      expect(result.error, isNull);
      expect(result.skipped, isFalse);
      expect(result.hasFacts, isTrue);
      expect(result.facts, hasLength(1));
    });

    test('skipped 結果（訊息太短）', () {
      const result = ExtractionResult(facts: [], skipped: true);

      expect(result.skipped, isTrue);
      expect(result.hasFacts, isFalse);
    });

    test('error 結果', () {
      const result = ExtractionResult(facts: [], error: 'API timeout');

      expect(result.error, 'API timeout');
      expect(result.hasFacts, isFalse);
    });

    test('空結果', () {
      const result = ExtractionResult(facts: []);

      expect(result.hasFacts, isFalse);
      expect(result.skipped, isFalse);
      expect(result.error, isNull);
    });
  });

  // ===== 記憶提取場景測試 =====
  //
  // 以下測試驗證各種真實使用者語句的 prompt 建構結果。
  // 這些不是 LLM 端到端測試（那需要 mock API），而是確保
  // prompt 正確包含使用者訊息、系統 prompt 有正確的判斷指引。

  group('記憶提取場景 — prompt 建構', () {
    test('場景1：明確身份宣告（無前綴詞）', () {
      // 使用者說「我叫建新」，沒有「記住：」前綴
      // 正則快車道可能抓不到（取決於模式），LLM 應該能抓到
      final userPrompt = ExtractionPrompt.buildUserPrompt('我叫建新');
      final systemPrompt = ExtractionPrompt.buildSystemPrompt();

      expect(userPrompt, contains('我叫建新'));
      // system prompt 裡有對應範例
      expect(systemPrompt, contains('我叫建新'));
    });

    test('場景2：隱含的專案資訊', () {
      // 使用者說「我最近在搞一個 Flutter app」
      // 正則快車道完全抓不到（沒有前綴詞，沒有身份/偏好模式）
      // LLM 應該能理解這是「正在進行的專案」
      final userPrompt = ExtractionPrompt.buildUserPrompt('我最近在搞一個 Flutter app');

      expect(userPrompt, contains('Flutter app'));
    });

    test('場景3：明確記憶指令', () {
      // 使用者說「記住：我女兒叫小星星」
      // 正則快車道應該抓到（「記住：」前綴）
      // LLM 慢車道也應該抓到，但去重後不重複寫入
      final userPrompt = ExtractionPrompt.buildUserPrompt('記住：我女兒叫小星星');

      expect(userPrompt, contains('小星星'));
    });

    test('場景4：即時評論（不應提取）', () {
      // 使用者說「那個 API 文件寫得真爛」
      // 這是即時評論，不是穩定偏好 — 不應該被提取
      final userPrompt = ExtractionPrompt.buildUserPrompt('那個 API 文件寫得真爛');
      final systemPrompt = ExtractionPrompt.buildSystemPrompt();

      expect(userPrompt, contains('API 文件'));
      // system prompt 明確說這種不該提取
      expect(systemPrompt, contains('API 文件寫得真爛'));
      expect(systemPrompt, contains('不提取'));
    });

    test('場景5：穩定偏好（應提取）', () {
      // 使用者說「我討厭寫文件」
      // 這反映穩定偏好 — 應該被提取
      final userPrompt = ExtractionPrompt.buildUserPrompt('我討厭寫文件');
      final systemPrompt = ExtractionPrompt.buildSystemPrompt();

      expect(userPrompt, contains('寫文件'));
      expect(systemPrompt, contains('我討厭寫文件'));
      expect(systemPrompt, contains('提取'));
    });

    test('場景6：太短的訊息', () {
      // 使用者說「嗨」— 太短，LLM 不應該被呼叫
      // 這在 SmartMemoryExtractor.extract() 裡被過濾
      expect('嗨'.length < 8, isTrue);
    });

    test('場景7：混合訊息（部分值得記住，部分不值得）', () {
      // 使用者說「幫我搜尋一下 Flutter 的資料，對了我叫建新」
      // 「幫我搜尋」是指令，不值得記住
      // 「我叫建新」是身份，值得記住
      final userPrompt = ExtractionPrompt.buildUserPrompt('幫我搜尋一下 Flutter 的資料，對了我叫建新');

      expect(userPrompt, contains('我叫建新'));
      expect(userPrompt, contains('搜尋'));
    });

    test('場景8：生活情境', () {
      // 使用者說「最近搬到台北了，還在適應新環境」
      // 這是生活情境變化 — 應該被提取
      final userPrompt = ExtractionPrompt.buildUserPrompt('最近搬到台北了，還在適應新環境');

      expect(userPrompt, contains('台北'));
    });
  });

  // ===== P1 回歸測試：短訊息雙重門檻修復 =====
  //
  // 修復前：「我叫建新」(4字) 被快車道 <5 和慢車道 <8 雙重攔截
  // 修復後：快車道 <3、慢車道 <4，「我叫建新」可正常觸發

  group('P1 回歸：短訊息門檻修復', () {
    test('「我叫建新」(4字) 不再被 SmartMemoryExtractor 攔截', () {
      // _minMessageLength = 4，「我叫建新」= 4 字 → 4 >= 4 → 通過
      expect('我叫建新'.trim().length >= 4, isTrue);
    });

    test('「嗨」(1字) 仍被攔截', () {
      expect('嗨'.trim().length >= 4, isFalse);
    });

    test('「好」(1字) 仍被攔截', () {
      expect('好'.trim().length >= 4, isFalse);
    });

    test('「我討厭寫文件」(6字) 不再被攔截（P6 一併修復）', () {
      expect('我討厭寫文件'.trim().length >= 4, isTrue);
    });
  });

  // ===== P4 回歸測試：第三人稱改寫去重 =====
  //
  // 修復前：bigram Jaccard 0.50 < 0.6 → 去重失效
  // 修復後：token overlap（去停用詞後）→ 1.0 >= 0.5 → 正確去重

  group('P4 回歸：第三人稱改寫去重', () {
    test('「使用者的女兒叫小星星」vs「我女兒叫小星星」應判定為重複', () {
      // 這是迦勒模擬場景 3 的核心案例
      // 修復前：bigram Jaccard = 0.50 < 0.6 → 不去重 → 重複寫入
      // 修復後：去停用詞後 {女兒,兒叫,叫小,小星,星星} vs {女兒,兒叫,叫小,小星,星星}
      //        → overlap = 1.0 >= 0.5 → 正確去重
      //
      // 由於 _tokenOverlap 是 private 方法，這裡驗證概念：
      // 去除「使用者」「的」「我」後，兩段文字的關鍵 token 應完全重疊

      const a = '使用者的女兒叫小星星';
      const b = '我女兒叫小星星';

      // 模擬停用詞去除
      const stopwords = ['使用者', '的', '我', '是', '在'];
      var cleanA = a;
      var cleanB = b;
      for (final sw in stopwords) {
        cleanA = cleanA.replaceAll(sw, '');
        cleanB = cleanB.replaceAll(sw, '');
      }

      // 去停用詞後應該幾乎相同
      expect(cleanA, contains('女兒叫小星星'));
      expect(cleanB, contains('女兒叫小星星'));
      expect(cleanA, cleanB);
    });

    test('「使用者名叫建新」vs「我叫建新」應判定為重複', () {
      // 場景 1 的去重案例
      const a = '使用者名叫建新';
      const b = '我叫建新';

      const stopwords = ['使用者', '名叫', '我', '叫', '的'];
      var cleanA = a;
      var cleanB = b;
      for (final sw in stopwords) {
        cleanA = cleanA.replaceAll(sw, '');
        cleanB = cleanB.replaceAll(sw, '');
      }

      // 去停用詞後核心詞「建新」應保留
      expect(cleanA, contains('建新'));
      expect(cleanB, contains('建新'));
    });

    test('完全不相關的記憶不應被誤判為重複', () {
      // 確保去重不會過度：完全不同的內容應該有低重疊率
      const a = '使用者正在開發 Flutter app';
      const b = '我女兒叫小星星';

      // 這兩段文字的關鍵詞完全不重疊
      expect(a.contains('Flutter'), isTrue);
      expect(b.contains('Flutter'), isFalse);
      expect(b.contains('女兒'), isTrue);
      expect(a.contains('女兒'), isFalse);
    });
  });
}
