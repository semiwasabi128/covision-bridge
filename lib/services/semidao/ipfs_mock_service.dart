// ipfs_mock_service.dart
// SemiDAO Phase 1: IPFS 存證模擬
//
// Phase 1 用本地檔案系統模擬 IPFS pinning：
// - 將 content 寫入 app documents 目錄
// - 產生 fake CID（SHA-256 of content → base32 編碼前 46 chars）
// - 回傳 SemidaoIpfsRecord
//
// Phase 2 替換為真正的 Pinata API 或自建 IPFS node

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'semidao_models.dart';

class IpfsMockService {
  /// 將 content 存證到「IPFS」（本地模擬）
  Future<SemidaoIpfsRecord> pin(String content) async {
    final bytes = utf8.encode(content);
    final digest = sha256.convert(bytes);

    // 模擬 CID v0: "Qm" + base58 of hash（簡化版用 hex prefix）
    final cid = 'Qm${digest.toString().substring(0, 44)}';

    // 寫入本地檔案
    final dir = await getApplicationDocumentsDirectory();
    final ipfsDir = Directory('${dir.path}/semidao_ipfs');
    if (!await ipfsDir.exists()) {
      await ipfsDir.create(recursive: true);
    }
    final file = File('${ipfsDir.path}/$cid.json');
    await file.writeAsString(content);

    return SemidaoIpfsRecord(
      cid: cid,
      localPath: file.path,
      pinnedAt: DateTime.now(),
      sizeBytes: bytes.length,
    );
  }

  /// 從「IPFS」讀取內容
  Future<String?> retrieve(String cid) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/semidao_ipfs/$cid.json');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// 檢查 CID 是否已 pin
  Future<bool> isPinned(String cid) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/semidao_ipfs/$cid.json');
    return file.exists();
  }
}
