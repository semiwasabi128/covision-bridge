// minimax_tts_service.dart — [小葵 2026-09-24 出道令] MiniMax T2A 雲端 TTS
// 使命：全雙工語音用「同一個聲音」——xiaokui_video_voice（H3 克隆）。
// 只有聲音 ID 不在 Kokoro 清單時才走這裡（Kokoro 本地優先，雲端是為了聲音一致性）。
// 金鑰：flutter.api_token_v2_minimax（App 自己的 defaults，不寫死——開源紅牌）。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class MinimaxTtsService {
  static const _endpoint = 'https://api.minimax.io/v1/t2a_v2';

  String? _cachedKey;
  String? _lastError;

  String? get lastError => _lastError;

  /// 該 voice 是否該走 MiniMax（ttv- 克隆/設計音色 or xiaokui_video_voice）
  static bool handles(String voiceId) =>
      voiceId.startsWith('ttv-') || voiceId == 'xiaokui_video_voice';

  Future<String?> _apiKey() async {
    if (_cachedKey != null) return _cachedKey;
    // macOS：直接讀 App 自己的 defaults（與 bridge_mcp_server 的 token 讀法同源）
    try {
      final result = await Process.run('defaults', [
        'read',
        'farm.semiwasabi.bridgeApp',
        'flutter.api_token_v2_minimax',
      ]);
      final v = (result.stdout as String).trim().replaceAll('"', '');
      if (result.exitCode == 0 && v.isNotEmpty) {
        _cachedKey = v;
        return v;
      }
    } catch (e) {
      _lastError = 'defaults read 失敗: $e';
    }
    return null;
  }

  /// 合成語音。回傳 mp3 bytes；失敗回 null（caller fallback Kokoro）。
  Future<Uint8List?> synthesize({
    required String text,
    required String voiceId,
    double speed = 1.0,
    int pitch = 1,
  }) async {
    if (text.trim().isEmpty) return null;
    final key = await _apiKey();
    if (key == null) {
      _lastError = '沒有 MiniMax API key';
      return null;
    }
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      final req = await client.postUrl(Uri.parse(_endpoint));
      req.headers.set('Authorization', 'Bearer $key');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'model': 'speech-02-turbo',
        'text': text,
        'stream': false,
        'language_boost': 'zh',
        'output_format': 'hex', // 直接拿 bytes，免二次下載 url
        'voice_setting': {
          'voice_id': voiceId,
          'speed': speed,
          'vol': 1.0,
          'pitch': pitch,
        },
      }));
      final res = await req.close().timeout(const Duration(seconds: 60));
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final d = jsonDecode(body) as Map<String, dynamic>;
      final status = d['base_resp']?['status_code'] ?? -1;
      if (status != 0) {
        _lastError = 't2a_v2 status=$status ${d['base_resp']?['status_msg']}';
        return null;
      }
      // output_format=hex 時 audio 是 hex 字串；=url 時要再抓
      final audio = d['data']?['audio'];
      if (audio is String && audio.isNotEmpty) {
        if (audio.startsWith('http')) {
          return await _download(audio);
        }
        // hex 解碼
        return Uint8List.fromList(
            audio.replaceAll(RegExp(r'[^0-9a-fA-F]'), '')
                .split('')
                .asMap().entries.isEmpty ? <int>[] : _hexToBytes(audio));
      }
      _lastError = '回應沒有 audio';
      return null;
    } catch (e) {
      _lastError = 'T2A 例外: $e';
      return null;
    }
  }

  static List<int> _hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    final out = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      out.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  Future<Uint8List?> _download(String url) async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      final builder = BytesBuilder();
      await for (final c in res) {
        builder.add(c);
      }
      client.close();
      return builder.takeBytes();
    } catch (e) {
      _lastError = '下載音檔失敗: $e';
      return null;
    }
  }
}
