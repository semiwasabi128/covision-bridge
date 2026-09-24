// pinata_ipfs_service.dart
// SemiDAO Phase 2: 真實 IPFS 存證 via Pinata API
//
// 替換 IpfsMockService — 將資產內容 pin 到 IPFS
// 如果 Pinata JWT 未設定，fallback 到 IpfsMockService（本地模擬）
//
// Pinata API:
// - pinJSONToIPFS: POST https://api.pinata.cloud/pinning/pinJSONToIPFS
// - pinFileToIPFS: POST https://api.pinata.cloud/pinning/pinFileToIPFS
//
// 設定方式: App 內 Golden Keys → 新增 'pinata' provider → 貼 JWT token

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'package:bridge_app/services/storage_service.dart';

import 'semidao_models.dart';
import 'ipfs_mock_service.dart';

class PinataIpfsService {
  PinataIpfsService({Dio? dio, IpfsMockService? mockFallback})
      : _dio = dio ?? Dio(),
        _mockFallback = mockFallback ?? IpfsMockService();

  final Dio _dio;
  final IpfsMockService _mockFallback;

  static const _pinataBaseUrl = 'https://api.pinata.cloud/pinning';

  /// 將 content 存證到 IPFS via Pinata
  /// 如果 Pinata JWT 未設定，fallback 到本地 mock
  Future<SemidaoIpfsRecord> pin(String content) async {
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) {
      return _mockFallback.pin(content);
    }

    try {
      final bytes = utf8.encode(content);
      final digest = sha256.convert(bytes);

      // content 可能不是合法 JSON，先嘗試 parse；失敗就用 pinFileToIPFS
      dynamic jsonContent;
      bool isJson = false;
      try {
        jsonContent = jsonDecode(content);
        isJson = true;
      } catch (_) {
        // 不是 JSON — 用 pinFileToIPFS
      }

      Map<String, dynamic> responseData;

      if (isJson) {
        final response = await _dio.post(
          '$_pinataBaseUrl/pinJSONToIPFS',
          options: Options(
            headers: {
              'Authorization': 'Bearer $jwt',
              'Content-Type': 'application/json',
            },
          ),
          data: {
            'pinataContent': jsonContent,
            'pinataMetadata': {
              'name': 'semidao-asset-${digest.toString().substring(0, 16)}',
              'keyvalues': {
                'app': 'bridge',
                'module': 'semidao',
                'contentHash': digest.toString(),
              },
            },
          },
        );
        responseData = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
      } else {
        // 非 JSON 內容用 pinFileToIPFS
        final form = FormData.fromMap({
          'file': MultipartFile.fromBytes(
            bytes,
            filename: 'asset-${digest.toString().substring(0, 16)}.txt',
          ),
          'pinataMetadata': jsonEncode({
            'name': 'semidao-file-${digest.toString().substring(0, 16)}',
            'keyvalues': {'app': 'bridge', 'module': 'semidao'},
          }),
        });

        final response = await _dio.post(
          '$_pinataBaseUrl/pinFileToIPFS',
          options: Options(
            headers: {'Authorization': 'Bearer $jwt'},
          ),
          data: form,
        );
        responseData = response.data is Map
            ? Map<String, dynamic>.from(response.data as Map)
            : <String, dynamic>{};
      }

      final cid = responseData['IpfsHash']?.toString();
      if (cid == null || cid.isEmpty) {
        return _mockFallback.pin(content);
      }

      final pinSize =
          (responseData['PinSize'] as num?)?.toInt() ?? bytes.length;
      final timestamp = responseData['Timestamp']?.toString();
      final pinnedAt = timestamp != null
          ? DateTime.tryParse(timestamp) ?? DateTime.now()
          : DateTime.now();

      // 同時寫一份到本地快取
      await _cacheLocal(cid, content);

      return SemidaoIpfsRecord(
        cid: cid,
        localPath: await _localPath(cid),
        pinnedAt: pinnedAt,
        sizeBytes: pinSize,
      );
    } catch (e) {
      // Pinata API 失敗，fallback 到 mock
      return _mockFallback.pin(content);
    }
  }

  /// 從 IPFS 讀取內容 — 先查本地快取，再查 Pinata gateway
  Future<String?> retrieve(String cid) async {
    // 1. 先查本地快取
    final localContent = await _readLocalCache(cid);
    if (localContent != null) return localContent;

    // 2. 查 public IPFS gateway
    try {
      final response = await _dio.get(
        'https://gateway.pinata.cloud/ipfs/$cid',
        options: Options(responseType: ResponseType.plain),
      );
      final content = response.data?.toString();
      if (content != null && content.isNotEmpty) {
        await _cacheLocal(cid, content);
      }
      return content;
    } catch (_) {
      // Gateway 也失敗，嘗試 mock
      return _mockFallback.retrieve(cid);
    }
  }

  /// 檢查 CID 是否已 pin
  Future<bool> isPinned(String cid) async {
    // 先查本地快取
    final localExists = await _localCacheExists(cid);
    if (localExists) return true;

    // 查 Pinata
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) {
      return _mockFallback.isPinned(cid);
    }

    try {
      final response = await _dio.get(
        '$_pinataBaseUrl/pinList?hashContains=$cid',
        options: Options(
          headers: {'Authorization': 'Bearer $jwt'},
        ),
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      final count = (data['count'] as num?)?.toInt() ?? 0;
      return count > 0;
    } catch (_) {
      return false;
    }
  }

  /// Pin 檔案 bytes 到 IPFS（適用於非 JSON 內容）
  Future<SemidaoIpfsRecord> pinFile(Uint8List bytes, {String? filename}) async {
    final jwt = await _getJwt();
    if (jwt == null || jwt.isEmpty) {
      return _mockFallback.pin(utf8.decode(bytes, allowMalformed: true));
    }

    try {
      final digest = sha256.convert(bytes);
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename:
              filename ?? 'asset-${digest.toString().substring(0, 16)}.bin',
        ),
        'pinataMetadata': jsonEncode({
          'name': filename ??
              'semidao-file-${digest.toString().substring(0, 16)}',
          'keyvalues': {'app': 'bridge', 'module': 'semidao'},
        }),
      });

      final response = await _dio.post(
        '$_pinataBaseUrl/pinFileToIPFS',
        options: Options(
          headers: {'Authorization': 'Bearer $jwt'},
        ),
        data: form,
      );

      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};

      final cid = data['IpfsHash']?.toString();
      if (cid == null || cid.isEmpty) {
        return _mockFallback.pin(utf8.decode(bytes, allowMalformed: true));
      }

      final pinSize = (data['PinSize'] as num?)?.toInt() ?? bytes.length;

      return SemidaoIpfsRecord(
        cid: cid,
        localPath: await _localPath(cid),
        pinnedAt: DateTime.now(),
        sizeBytes: pinSize,
      );
    } catch (e) {
      return _mockFallback.pin(utf8.decode(bytes, allowMalformed: true));
    }
  }

  // ── 內部方法 ──

  /// 取得 Pinata JWT — 使用 StorageService 統一管理
  /// provider key = 'pinata'
  Future<String?> _getJwt() async {
    try {
      return await StorageService.getToken(provider: 'pinata');
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheLocal(String cid, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    final ipfsDir = Directory('${dir.path}/semidao_ipfs');
    if (!await ipfsDir.exists()) {
      await ipfsDir.create(recursive: true);
    }
    final file = File('${ipfsDir.path}/$cid.json');
    await file.writeAsString(content);
  }

  Future<String?> _readLocalCache(String cid) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/semidao_ipfs/$cid.json');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<bool> _localCacheExists(String cid) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/semidao_ipfs/$cid.json');
    return file.exists();
  }

  Future<String> _localPath(String cid) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/semidao_ipfs/$cid.json';
  }
}
