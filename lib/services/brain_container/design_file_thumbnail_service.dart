// design_file_thumbnail_service.dart
// [小葵 2026-08-28] Blue 專業製圖檔嵌入工程
//
// 專業製圖檔（.skp SketchUp / .dwg AutoCAD / .psd Photoshop / .ai Illustrator）
// 是特定使用者群的主力格式。本服務從二進位抽出內嵌縮圖 → 本地 Vision
// 描述 → EmbeddingGemma 嵌入。
//
// 抽取技術（2026-08-28 實測驗證）：
// - .skp：檔頭內嵌 PNG（meta/model_thumbnail.png 區塊，PNG magic 直抽）
// - .dwg：AcDb:Preview 的 BITMAPINFOHEADER（DIB 無 BM header，自造 14-byte
//   BITMAPFILEHEADER 包成完整 BMP）
// - .psd：Photoshop 檔頭 image data 區（本服務先試 PNG/JP2 內嵌，不行標 unsupported）
// - .ai：新版=PDF 容器（走 PDF 文字抽取）；舊版=EPS 文字檔
// - .avif：macOS QL 可渲染（qlmanage -t）——由呼叫端先轉 PNG 再進來
//
// 誠實標記：抽不到縮圖 → 'no_thumbnail'；Vision 失敗 → 維持 metadata。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import 'brain_database.dart';
import 'embedding/embedding_service.dart';

class DesignFileThumbnailService {
  DesignFileThumbnailService._();
  static final DesignFileThumbnailService instance =
      DesignFileThumbnailService._();

  static const _designExts = ['.skp', '.dwg', '.skb', '.psd', '.ai'];

  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      await _run(BrainDatabase.instance.db);
    } catch (e, st) {
      debugPrint('[DesignThumb] ❌ $e\n$st');
      _mark('error:$e');
    } finally {
      _running = false;
    }
  }

  Future<void> _run(Database db) async {
    final embedder = EmbeddingService.instance;
    if (!embedder.isModelAvailable) {
      _mark('model_unavailable');
      return;
    }

    final extList = _designExts.map((e) => "'$e'").join(',');
    final rows = db.select('''
      SELECT id, folder_root, file_path, file_name, file_ext, display_title
      FROM asset_index
      WHERE COALESCE(embed_source,'') = 'metadata'
        AND LOWER(COALESCE(file_ext,'')) IN ($extList)
    ''');

    if (rows.isEmpty) {
      _mark('idle');
      return;
    }
    debugPrint('[DesignThumb] 專業製圖檔待處理: ${rows.length} 筆');
    _markProgress(0, rows.length);

    var done = 0;
    var ok = 0;

    for (final r in rows) {
      final id = r['id'] as String;
      final fullPath = '${r['folder_root']}/${r['file_path']}';
      final ext = (r['file_ext'] as String? ?? '').toLowerCase();
      final title = (r['display_title'] as String? ?? r['file_name']) as String;

      try {
        final f = File(fullPath);
        if (!f.existsSync()) {
          db.execute(
              "UPDATE asset_index SET embed_source='no_thumbnail' WHERE id=?",
              [id]);
          done++;
          continue;
        }

        // ① 抽縮圖 bytes（BMP 會先經 sips 轉 PNG——Vision 只吃 PNG/JPEG）
        var thumbBytes = _extractThumb(f, ext);
        if (thumbBytes != null && ext == '.dwg') {
          thumbBytes = await _bmpToPng(thumbBytes);
        }
        if (thumbBytes == null) {
          db.execute(
              "UPDATE asset_index SET embed_source='no_thumbnail' WHERE id=?",
              [id]);
          done++;
          _markProgress(done, rows.length);
          continue;
        }

        // ② 直接 data URI → 本地 Vision（繞過 /tmp 檔案——沙盒環境可靠性）
        final b64 = base64Encode(thumbBytes);
        try {
          BrainDatabase.instance.db.execute(
            "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('design_thumb_dbg', ?)",
            ['b64len=' + b64.length.toString() + ' head=' + b64.substring(0, 40) + ' pngLen=' + thumbBytes.length.toString() + ' pngHead=' + thumbBytes.take(8).join(',')],
          );
        } catch (_) {}
                // [診斷 2026-08-28] 繞過 Dio：直接 HttpClient 對 llama-server（Dio 400 之謎）
        String visionDesc = '';
        try {
          final httpClient = HttpClient();
          final req = await httpClient.postUrl(Uri.parse('http://127.0.0.1:18789/v1/chat/completions'));
          req.headers.set('Content-Type', 'application/json');
          final body = jsonEncode({
            'messages': [
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': '這是「\$title」的設計圖縮圖。描述圖面內容：圖面類型、主要元素、材質或配色。繁體中文，120字內。'},
                  {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,' + b64}},
                ],
              },
            ],
            'max_tokens': 1024,
            'temperature': 0.4,
          });
          req.write(body);
          final resp = await req.close();
          final respBody = await resp.transform(utf8.decoder).join();
          httpClient.close();
          try {
            BrainDatabase.instance.db.execute(
              "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('design_thumb_http', ?)",
              ['status=' + resp.statusCode.toString() + ' body220=' + (respBody.length > 220 ? respBody.substring(0, 220) : respBody)],
            );
          } catch (_) {}
          if (resp.statusCode == 200) {
            final j = jsonDecode(respBody) as Map<String, dynamic>;
            final msg = (j['choices'] as List)[0]['message'] as Map<String, dynamic>;
            visionDesc = (msg['content'] as String? ?? '').trim();
            if (visionDesc.isEmpty) {
              visionDesc = (msg['reasoning_content'] as String? ?? '').trim();
            }
          }
        } catch (_) {}
        final vr = _fakeResult(visionDesc);

        String description;
        if (vr.success) {
          description = vr.content.trim();
        } else {
          description = '';
        }

        if (description.isEmpty) {
          debugPrint('[DesignThumb] ⚠ Vision 無描述 ($title)，維持 metadata');
          try {
            BrainDatabase.instance.db.execute(
              "INSERT OR REPLACE INTO brain_meta (key, value) "
              "VALUES ('design_thumb_empty_desc', ?)",
              ['$title | vr.success=${vr.success} | content=${vr.content}'],
            );
          } catch (_) {}
          done++;
          _markProgress(done, rows.length);
          continue;
        }

        // ③ 嵌入：描述 + metadata 加權
        final embedText = '$title。設計圖：$description';
        final result = await embedder.embedOne(embedText);
        if (result.modelVersion == 'mock-fallback') {
          _mark('fallback_stop');
          return;
        }
        db.execute(
          "UPDATE asset_index SET embedding=?, content_text=?, summary=?, "
          "embed_source='content', index_status='indexed', indexed_at=? "
          "WHERE id=?",
          [
            _vecToBlob(result.vector),
            embedText,
            description.length > 200
                ? '${description.substring(0, 200)}...'
                : description,
            DateTime.now().millisecondsSinceEpoch,
            id,
          ],
        );
        ok++;
      } catch (e, st) {
        debugPrint('[DesignThumb] ❌ ${r['file_name']}: $e');
        try {
          BrainDatabase.instance.db.execute(
            "INSERT OR REPLACE INTO brain_meta (key, value) "
            "VALUES ('design_thumb_last_error', ?)",
            ['${r['file_name']}: $e\n${st.toString().split("\n").take(3).join(" | ")}'],
          );
        } catch (_) {}
      }
      done++;
      if (done % 5 == 0) _markProgress(done, rows.length);
      // 讓出 isolate（Vision 每張數秒，不塞 UI）
      await Future.delayed(const Duration(milliseconds: 200));
    }

    _mark('done');
    debugPrint('[DesignThumb] ✅ 完成：$ok/${rows.length} 成功');
  }

  /// 從設計檔二進位抽縮圖（回傳 PNG bytes 或 null）
  Uint8List? _extractThumb(File f, String ext) {
    switch (ext) {
      case '.skp':
      case '.skb':
        return _extractPng(f, maxScan: 3 * 1024 * 1024);
      case '.dwg':
        return _extractDwgBmp(f);
      case '.psd':
        return _extractPsdThumb(f);
      case '.ai':
        return null; // 新版 AI=PDF 走文字抽取（另一管線）
      default:
        return null;
    }
  }

  /// PNG magic 直抽（skp 縮圖在檔頭）
  Uint8List? _extractPng(File f, {int maxScan = 1024 * 1024}) {
    final data = f.openSync();
    try {
      final size = f.lengthSync();
      final readLen = size < maxScan ? size : maxScan;
      // 讀前 maxScan bytes 找 PNG
      final chunk = data.readSync(readLen);
      final pngStart = _indexOf(chunk, [0x89, 0x50, 0x4E, 0x47]);
      if (pngStart < 0) return null;
      // [小葵 2026-08-28] 修雙重偏移 bug：sublist 已是相對座標，from 不可再加 pngStart
      final iend = _indexOf(chunk, [0x49, 0x45, 0x4E, 0x44], from: pngStart);
      if (iend < 0) return null;
      final png = chunk.sublist(pngStart, iend + 8);
      return Uint8List.fromList(png);
    } catch (_) {
      return null;
    } finally {
      data.closeSync();
    }
  }

  /// DWG：找 BITMAPINFOHEADER（28 00 00 00 + 合理 w/h/bpp）→ 自造 BM header
  Uint8List? _extractDwgBmp(File f) {
    try {
      final data = f.readAsBytesSync();
      // 只掃前 2MB（thumbnail 通常在檔頭 image 需求區）
      final scanLen = data.length < 2 * 1024 * 1024 ? data.length : 2 * 1024 * 1024;
      for (var i = 0; i < scanLen - 44; i++) {
        if (data[i] == 0x28 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 0) {
          final w = data.buffer.asByteData().getInt32(i + 4, Endian.little);
          final h = data.buffer.asByteData().getInt32(i + 8, Endian.little);
          final planes = data.buffer.asByteData().getUint16(i + 12, Endian.little);
          final bpp = data.buffer.asByteData().getUint16(i + 14, Endian.little);
          if (w >= 32 && w <= 4096 && h.abs() >= 32 && h.abs() <= 4096 &&
              planes == 1 && (bpp == 8 || bpp == 24 || bpp == 32)) {
            final palSize = bpp == 8 ? 1024 : 0;
            final imgSize = w * h.abs() * (bpp ~/ 8);
            final offBits = 14 + 40 + palSize;
            // 自造 BITMAPFILEHEADER
            final bm = BytesBuilder();
            bm.add([0x42, 0x4D]); // BM
            final fileSize = offBits + imgSize;
            final bd = ByteData(12);
            bd.setUint32(0, fileSize, Endian.little);
            bd.setUint16(4, 0, Endian.little);
            bd.setUint16(6, 0, Endian.little);
            bd.setUint32(8, offBits, Endian.little);
            bm.add(bd.buffer.asUint8List());
            bm.add(data.sublist(i, i + 40 + palSize + imgSize));
            return bm.toBytes();
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// PSD：找內嵌 PNG（合併圖層縮圖）；找不到試 JPEG
  Uint8List? _extractPsdThumb(File f) {
    final png = _extractPng(f, maxScan: 10 * 1024 * 1024);
    if (png != null) return png;
    // JPEG magic 掃描
    try {
      final data = f.readAsBytesSync();
      final scanLen = data.length < 8 * 1024 * 1024 ? data.length : 8 * 1024 * 1024;
      final jStart = _indexOf(data.sublist(0, scanLen), [0xFF, 0xD8, 0xFF]);
      if (jStart < 0) return null;
      final jEnd = _lastIndexOf(data, [0xFF, 0xD9]);
      if (jEnd < jStart) return null;
      return Uint8List.fromList(data.sublist(jStart, jEnd + 2));
    } catch (_) {
      return null;
    }
  }

  /// BMP bytes → PNG（Vision 只吃 PNG/JPEG；BMP 用外部 sips 轉）
  /// （BMP 直接回傳，呼叫端寫 .bmp 檔——QL/多數模型不吃，所以這裡
  ///  轉存時統一走 sips）
  int _indexOf(Uint8List hay, List<int> needle, {int from = 0}) {
    outer:
    for (var i = from; i <= hay.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  int _lastIndexOf(Uint8List hay, List<int> needle) {
    outer:
    for (var i = hay.length - needle.length; i >= 0; i--) {
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }



  /// BMP → PNG（macOS sips 轉檔；失敗回 null）
  Future<Uint8List?> _bmpToPng(Uint8List bmp) async {
    final bmpFile = File('/tmp/bridge_design_${DateTime.now().millisecondsSinceEpoch}.bmp');
    final pngFile = File('\${bmpFile.path}.png');
    try {
      await bmpFile.writeAsBytes(bmp);
      final r = await Process.run(
          'sips', ['-s', 'format', 'png', bmpFile.path, '--out', pngFile.path]);
      if (r.exitCode == 0 && await pngFile.exists()) {
        return await pngFile.readAsBytes();
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try { await bmpFile.delete(); } catch (_) {}
      try { await pngFile.delete(); } catch (_) {}
    }
  }

  static _VR _fakeResult(String desc) => _VR(desc);

  void _mark(String status) {
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('design_thumb_status', ?)",
        [status],
      );
    } catch (_) {}
  }

  void _markProgress(int done, int total) {
    try {
      BrainDatabase.instance.db.execute(
        "INSERT OR REPLACE INTO brain_meta (key, value) VALUES ('design_thumb_progress', '$done/$total')",
      );
    } catch (_) {}
  }

  static Uint8List _vecToBlob(List<double> vec) {
    final bytes = ByteData(vec.length * 4);
    for (var i = 0; i < vec.length; i++) {
      bytes.setFloat32(i * 4, vec[i], Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}


class _VR {
  final String content;
  final bool success;
  _VR(this.content) : success = content.trim().isNotEmpty;
}
