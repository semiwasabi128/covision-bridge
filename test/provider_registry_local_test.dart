// provider_registry_local_test.dart
// [小葵 2026-08-21] Ollama 本地 runtime 探測——真 HTTP 驗證
// 用本測試檔內起的假 OpenAI 相容 server（:11434）驗證 discoverLocalRuntimes

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bridge_app/services/provider_registry.dart';

/// 繞過 flutter_test 的 HTTP 沙盒（所有外部請求被假 400）
class _NoSandboxOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _NoSandboxOverrides();

  late HttpServer fakeOllama;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // 假 Ollama——OpenAI 相容 /v1/models
    fakeOllama = await HttpServer.bind(InternetAddress.loopbackIPv4, 11434);
    unawaited(() async {
      await for (final req in fakeOllama) {
        // ignore: avoid_print
        print('=== fake server 收到: ${req.method} ${req.uri.path}');
        if (req.uri.path.endsWith('/models')) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(
              '{"data":[{"id":"qwen3:32b"},{"id":"llama3.3:70b"}]}');
          await req.response.close();
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      }
    }());
  });

  tearDownAll(() async {
    await fakeOllama.close(force: true);
  });

  test('Ollama meta 註冊——baseUrlOf / metaOf', () async {
    expect(ProviderRegistry.baseUrlOf('ollama'), 'http://127.0.0.1:11434');
    expect(ProviderRegistry.metaOf('ollama')?.displayName, 'Ollama');
    // local 相容不破
    expect(ProviderRegistry.baseUrlOf('local'), 'http://127.0.0.1:18789');
    expect(ProviderRegistry.metaOf('local')?.displayName, '本地模型');
  });

  test('discoverLocalRuntimes——真探測假 Ollama 命中', () async {
    final runtimes = await ProviderRegistry.instance.discoverLocalRuntimes();
    final ollama =
        runtimes.where((r) => r.providerId == 'ollama').toList();
    expect(ollama, isNotEmpty, reason: '假 Ollama 在 11434 應被探測到');
    expect(ollama.first.availableModels,
        containsAll(['qwen3:32b', 'llama3.3:70b']));
    expect(ollama.first.reachable, isTrue);
    // LM Studio (18789) 在測試環境不會有——靜默跳過是正確行為
  });

  test('自訂 runtime URL——DGX Spark 場景', () async {
    await ProviderRegistry.setLocalRuntimeUrl(
        'ollama', 'http://192.168.1.50:11434');
    final runtimes = await ProviderRegistry.instance.discoverLocalRuntimes();
    final ollama =
        runtimes.where((r) => r.providerId == 'ollama').toList();
    // 192.168.1.50 不存在——探測應失敗（不在結果中），證明 URL 真的被覆寫
    expect(ollama, isEmpty,
        reason: '自訂 URL 覆寫後不應再打到本機 11434');
  });
}
