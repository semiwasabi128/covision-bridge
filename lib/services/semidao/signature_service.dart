// signature_service.dart
// SemiDAO Phase 1: App 內簽章服務
//
// Phase 1 使用 HMAC-SHA256 模擬 Ed25519 簽章：
// - 生成一組「keypair」（secret = 隨機 bytes，public = SHA-256 of secret）
// - 簽章 = HMAC-SHA256(secret, contentHash)
// - 驗章 = 重新計算 HMAC 比對
//
// Phase 2 上鏈時替換為真正的 Ed25519 + web3dart

import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'semidao_models.dart';

/// App 內簽章服務 — 管理 keypair 並提供簽章/驗章
class SignatureService {
  static const String _secretKey = 'semidao_signing_secret';
  static const String _fingerprintKey = 'semidao_public_fingerprint';
  static const String _creatorNameKey = 'semidao_creator_name';

  final Uuid _uuid = const Uuid();

  /// 確保 keypair 存在（不存在則生成）
  Future<void> ensureKeypair({String displayName = 'Creator'}) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_secretKey);
    if (existing != null && existing.isNotEmpty) return;

    // 生成隨機 secret（32 bytes → hex）
    final random = Random.secure();
    final secretBytes =
        List<int>.generate(32, (_) => random.nextInt(256));
    final secretHex = secretBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    // public = SHA-256 of secret
    final publicKeyDigest = sha256.convert(secretBytes);
    final fingerprint = publicKeyDigest.toString();

    await prefs.setString(_secretKey, secretHex);
    await prefs.setString(_fingerprintKey, fingerprint);
    await prefs.setString(_creatorNameKey, displayName);
  }

  /// 取得創作者身份
  Future<SemidaoCreator> getCreator() async {
    final prefs = await SharedPreferences.getInstance();
    final fingerprint = prefs.getString(_fingerprintKey);
    if (fingerprint == null) {
      await ensureKeypair();
      return getCreator();
    }
    final name = prefs.getString(_creatorNameKey) ?? 'Creator';
    final createdAt = DateTime.now(); // Phase 1 不記錄精確時間
    return SemidaoCreator(
      publicKeyFingerprint: fingerprint,
      displayName: name,
      createdAt: createdAt,
    );
  }

  /// 設定創作者顯示名稱
  Future<void> setDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_creatorNameKey, name);
  }

  /// 計算 content hash（SHA-256 of content）
  String computeContentHash(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  /// 簽章 — HMAC-SHA256(secret, contentHash)
  Future<SemidaoSignature> sign(String contentHash) async {
    final prefs = await SharedPreferences.getInstance();
    final secretHex = prefs.getString(_secretKey);
    final fingerprint = prefs.getString(_fingerprintKey);
    if (secretHex == null || fingerprint == null) {
      await ensureKeypair();
      return sign(contentHash);
    }

    // HMAC-SHA256
    final secretBytes = _hexToBytes(secretHex);
    final hmac = Hmac(sha256, secretBytes);
    final digest = hmac.convert(utf8.encode(contentHash));
    final signatureHex = digest.toString();

    return SemidaoSignature(
      signature: signatureHex,
      contentHash: contentHash,
      signedAt: DateTime.now(),
      signerFingerprint: fingerprint,
    );
  }

  /// 驗章 — 重算 HMAC 比對
  Future<bool> verify(SemidaoSignature sig) async {
    final prefs = await SharedPreferences.getInstance();
    final secretHex = prefs.getString(_secretKey);
    final fingerprint = prefs.getString(_fingerprintKey);
    if (secretHex == null || fingerprint == null) return false;

    // 只能驗自己簽的（Phase 1 限制 — Phase 2 用公鑰驗章）
    if (sig.signerFingerprint != fingerprint) return false;

    final secretBytes = _hexToBytes(secretHex);
    final hmac = Hmac(sha256, secretBytes);
    final expected = hmac.convert(utf8.encode(sig.contentHash)).toString();

    return expected == sig.signature;
  }

  /// 產生新 asset ID
  String newAssetId() => 'asset-${_uuid.v4()}';

  List<int> _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
