// canvas_mcp_server_test.dart
// L1 驗證 — Bridge App Canvas MCP Server (MCP 2026-07-28 標準)
//
// [小葵 2026-08-05] MCP 2026-07-28 升級驗證測試
//
// 測試範圍：
// 1. 舊 REST 端點向後相容：GET /health, GET /state
// 2. 升級後的 tools/list：resultType=complete + ttlMs + cacheScope + _meta.serverInfo
// 3. 升級後的 /mcp/discover：protocolVersion: 2026-07-28
// 4. POST /mcp JSON-RPC 2.0 dispatch：server/discover, tools/list, tools/call
// 5. 標準錯誤碼：-32020 HeaderMismatch、-32022 UnsupportedProtocolVersion、
//                 -32021 MissingRequiredClientCapability
//
// 實作策略：
// 用 `createForTesting(port: 0)` 建立獨立 instance，server 啟動後 shelf 會把 OS 分配的
// 實際 port 寫回 `_server.port`。測試結束後 stop() 釋放。
//
// 為什麼用 E2E (HTTP) 而非直接呼叫 handler？
// BridgeMcpServer 的 handler 都是 library-private (`_` 開頭)，外部無法 import 訪問。
// 透過 HttpClient 打真實 endpoint 是最真實的驗證路徑，且 port=0 確保不撞 8420。

import 'dart:convert';
import 'dart:io';

import 'package:bridge_app/services/bridge_mcp_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('BridgeMcpServer — L1 MCP 2026-07-28 驗證', () {
    late BridgeMcpServer server;
    late int actualPort;

    setUpAll(() async {
      // 用一個短暫 HttpServer 探測 OS 分配的 free port，再關掉
      // 這避免 port 8420（Flutter App 佔用）衝突
      final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final freePort = probe.port;
      await probe.close(force: true);

      server = BridgeMcpServer.createForTesting(port: freePort);
      await server.start();
      actualPort = freePort;
    });

    tearDownAll(() async {
      await server.stop();
    });

    // ── 舊 REST 端點（向後相容）──────────────────────
    test('GET /health → 200 + status: ok', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/health');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['status'], 'ok');
      expect(body['service'], 'bridge-mcp');
    });

    test('GET /state → callback 未接線時 503', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/state');
      expect(res.statusCode, 503);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error'], contains('Canvas controller not connected'));
    });

    test('GET /state → 接線 onGetState callback 後回傳 state', () async {
      server.onGetState = () async => {
            'nodes': [
              {'id': 'n1', 'type': 'llm', 'x': 100, 'y': 200},
            ],
            'connections': <Map<String, dynamic>>[],
            'viewport': {'x': 0, 'y': 0, 'zoom': 1.0},
          };
      final res = await _httpGet('http://127.0.0.1:$actualPort/state');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['nodes'], isA<List<dynamic>>());
      expect((body['nodes'] as List).length, 1);
      expect((body['nodes'] as List).first['id'], 'n1');
      // 清掉 callback 避免污染後續測試
      server.onGetState = null;
    });

    // ── 升級後的 tools/list（CacheableResult）──────────
    test('GET /mcp/tools → 帶 resultType=complete + ttlMs + cacheScope + _meta.serverInfo', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/mcp/tools');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      // MCP 2026-07-28 必填欄位
      expect(body['resultType'], 'complete');
      expect(body['ttlMs'], 60000);
      expect(body['cacheScope'], 'private');

      // _meta.serverInfo（SEP-2549）
      final meta = body['_meta'] as Map<String, dynamic>;
      expect(meta, isNotNull);
      final serverInfo = meta['io.modelcontextprotocol/serverInfo'] as Map<String, dynamic>;
      expect(serverInfo['name'], 'bridge-mcp');
      expect(serverInfo['version'], '2.0.0');
      expect(serverInfo['title'], 'Bridge App Canvas MCP Server');

      // 至少要有 tools 列表（持續新增工具；2026-09-22 實際 14）
      final tools = body['tools'] as List<dynamic>;
      expect(tools.length, greaterThanOrEqualTo(11));
    });

    // ── GET /mcp/discover（MCP 2026-07-28）────────────
    test('GET /mcp/discover → 帶 protocolVersion: 2026-07-28', () async {
      final res = await _httpGet('http://127.0.0.1:$actualPort/mcp/discover');
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['resultType'], 'complete');
      expect(body['protocolVersion'], '2026-07-28');
      expect(body['supportedVersions'], ['2026-07-28']);
      expect(body['capabilities'], isA<Map<String, dynamic>>());
      expect((body['capabilities'] as Map)['tools'], isNotNull);
      expect(body['serverInfo']['name'], 'bridge-mcp');
    });

    // ── POST /mcp JSON-RPC 2.0 dispatch ─────────────
    test('POST /mcp server/discover → 回 protocolVersion + capabilities', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'server/discover',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'server/discover',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['jsonrpc'], '2.0');
      expect(body['id'], 1);
      final result = body['result'] as Map<String, dynamic>;
      expect(result['protocolVersion'], '2026-07-28');
    });

    test('POST /mcp tools/list → 22 tools + 每個有 inputSchema (JSON Schema 2020-12)', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/list',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>;
      expect(result['resultType'], 'complete');
      expect(result['ttlMs'], 60000);
      expect(result['cacheScope'], 'private');
      final tools = result['tools'] as List<dynamic>;
      expect(tools.length, 22);

      // 每個 tool 都必須有 inputSchema（JSON Schema 2020-12 結構）
      for (final t in tools) {
        final tool = t as Map<String, dynamic>;
        expect(tool['name'], isA<String>());
        expect(tool['inputSchema'], isA<Map<String, dynamic>>());
        expect((tool['inputSchema'] as Map)['type'], 'object');
      }
    });

    test('POST /mcp tools/call list_canvases → 接線 callback 後回 canvases', () async {
      server.onListCanvases = () => [
            {'id': 'c1', 'name': '主畫布', 'tabIndex': 0},
            {'id': 'c2', 'name': '測試畫布', 'tabIndex': 1},
          ];
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 3,
          'method': 'tools/call',
          'params': {
            'name': 'list_canvases',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'list_canvases',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>;
      expect(result['resultType'], 'complete');
      final canvases = result['canvases'] as List<dynamic>;
      expect(canvases.length, 2);
      expect(canvases.first['id'], 'c1');
      server.onListCanvases = null;
    });

    test('POST /mcp tools/call navigate_to_canvas → 觸發 callback', () async {
      var triggered = false;
      server.onNavigateToCanvas = () {
        triggered = true;
      };
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 4,
          'method': 'tools/call',
          'params': {
            'name': 'navigate_to_canvas',
            'arguments': <String, dynamic>{},
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call',
          'Mcp-Name': 'navigate_to_canvas',
        },
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['result']['success'], true);
      expect(body['result']['message'], contains('畫布'));
      expect(triggered, isTrue);
    });

    // ── 標準錯誤碼 ──────────────────────────────────
    test('POST /mcp HeaderMismatch (Mcp-Method 跟 body method 不一致) → -32020', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 5,
          'method': 'tools/list', // body 說 tools/list
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/call', // header 說 tools/call → 不一致！
        },
      );
      expect(res.statusCode, 200); // JSON-RPC error 仍回 200
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32020);
      expect(body['error']['message'], contains('Header mismatch'));
    });

    test('POST /mcp UnsupportedProtocolVersion (header 帶 2025-11-25) → -32022', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 6,
          'method': 'tools/list',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2025-11-25', // 不支援的舊版
          'Mcp-Method': 'tools/list',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32022);
      expect(body['error']['message'], contains('Unsupported protocol version'));
    });

    test('POST /mcp MissingRequiredClientCapability (_meta 沒帶 clientCapabilities) → -32021', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 7,
          'method': 'tools/list',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              // 故意不帶 clientCapabilities
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/list',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32021);
      expect(body['error']['message'], contains('Missing required'));
      expect(body['error']['data']['requiredCapabilities'], contains('clientCapabilities'));
    });

    test('POST /mcp 不合法 JSON → -32700 (Parse error)', () async {
      final res = await _httpPostRaw(
        'http://127.0.0.1:$actualPort/mcp',
        '{ not json',
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'tools/list',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32700);
    });

    test('POST /mcp Method not found → -32601', () async {
      final res = await _httpPost(
        'http://127.0.0.1:$actualPort/mcp',
        body: {
          'jsonrpc': '2.0',
          'id': 8,
          'method': 'nonexistent/method',
          'params': {
            '_meta': {
              'io.modelcontextprotocol/protocolVersion': '2026-07-28',
              'io.modelcontextprotocol/clientCapabilities': <String, dynamic>{},
            },
          },
        },
        headers: {
          'MCP-Protocol-Version': '2026-07-28',
          'Mcp-Method': 'nonexistent/method',
        },
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['error']['code'], -32601);
    });
  });
}

// ── HTTP helpers（stdlib dart:io HttpClient）──────────

Future<_HttpResponse> _httpGet(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return _HttpResponse(res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}

Future<_HttpResponse> _httpPost(
  String url, {
  required Map<String, dynamic> body,
  Map<String, String>? headers,
}) async {
  return _httpPostRaw(
    url,
    jsonEncode(body),
    headers: {
      'Content-Type': 'application/json',
      ...?headers,
    },
  );
}

Future<_HttpResponse> _httpPostRaw(
  String url,
  String body, {
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.contentType = ContentType.json;
    headers?.forEach((k, v) => req.headers.set(k, v));
    req.write(body);
    final res = await req.close();
    final resBody = await res.transform(utf8.decoder).join();
    return _HttpResponse(res.statusCode, resBody);
  } finally {
    client.close(force: true);
  }
}

class _HttpResponse {
  final int statusCode;
  final String body;
  _HttpResponse(this.statusCode, this.body);
}

// 確保 shelf import 沒被 lint 抱怨（測試不需要直接用 Response）
// ignore: unused_element
Response _unusedShelfImport() => Response.ok('{}');
