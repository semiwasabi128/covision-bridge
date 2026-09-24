// semidao_service.dart
// SemiDAO Phase 1: 統一 facade
//
// 整合 SignatureService + IpfsMockService + 資產管理
// 提供 register / sign / pin / derive / verify 完整流程
//
// 使用方式:
//   final service = SemidaoService();
//   final asset = await service.registerAsset(
//     name: 'MV製作工作流',
//     kind: SemidaoAssetKind.workflow,
//     content: workflowJson,
//   );
//   // → asset.isSigned == true, asset.isPinned == true

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'semidao_models.dart';
import 'signature_service.dart';
import 'pinata_ipfs_service.dart';

/// 資產註冊結果
class RegistrationResult {
  final OffChainAsset asset;
  final bool wasDerived;

  const RegistrationResult({
    required this.asset,
    this.wasDerived = false,
  });
}

/// SemiDAO Phase 1+2 統一服務
/// Phase 1: off-chain 簽章 + IPFS 存證（mock 或 Pinata）+ 衍生追蹤
/// Phase 2: on-chain 確權（需搭配 SemidaoOnChainService）
class SemidaoService {
  static const String _storeKey = 'semidao_offchain_assets_v0';

  final SignatureService _signatureService;
  final PinataIpfsService _ipfsService;

  SemidaoService({
    SignatureService? signatureService,
    PinataIpfsService? ipfsService,
  })  : _signatureService = signatureService ?? SignatureService(),
        _ipfsService = ipfsService ?? PinataIpfsService();

  SignatureService get signatureService => _signatureService;
  PinataIpfsService get ipfsService => _ipfsService;

  /// 註冊資產 — 完整流程: hash → sign → pin → store
  Future<RegistrationResult> registerAsset({
    required String name,
    required SemidaoAssetKind kind,
    required String content,
    String description = '',
    SemidaoLicense? license,
    String? derivedFromAssetId,
  }) async {
    // 0. 確保 keypair
    await _signatureService.ensureKeypair();
    final creator = await _signatureService.getCreator();

    // 1. 計算 content hash
    final contentHash = _signatureService.computeContentHash(content);

    // 2. 簽章
    final signature = await _signatureService.sign(contentHash);

    // 3. IPFS 存證
    final ipfsRecord = await _ipfsService.pin(content);

    // 4. 建立資產
    final now = DateTime.now();
    final assetId = _signatureService.newAssetId();
    var asset = OffChainAsset(
      id: assetId,
      name: name,
      kind: kind,
      creator: creator,
      contentHash: contentHash,
      ipfsRecord: ipfsRecord,
      signature: signature,
      license: license ?? const SemidaoLicense(),
      derivedFromAssetId: derivedFromAssetId,
      createdAt: now,
      updatedAt: now,
      description: description,
    );

    // 5. 如果是衍生，更新上游資產的 derivativeAssetIds
    final wasDerived = derivedFromAssetId != null;
    if (wasDerived) {
      await _addDerivativeLink(derivedFromAssetId, assetId);
    }

    // 6. 儲存
    await _storeAsset(asset);

    return RegistrationResult(asset: asset, wasDerived: wasDerived);
  }

  /// 取得所有資產
  Future<List<OffChainAsset>> getAllAssets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storeKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) =>
              OffChainAsset.fromJson(Map<String, dynamic>.from(item)))
          .where((a) => a.id.isNotEmpty)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return const [];
    }
  }

  /// 取得單一資產
  Future<OffChainAsset?> getAsset(String assetId) async {
    final all = await getAllAssets();
    return all.where((a) => a.id == assetId).firstOrNull;
  }

  /// 驗證資產簽章
  Future<bool> verifyAsset(OffChainAsset asset) async {
    if (asset.signature == null) return false;
    return _signatureService.verify(asset.signature!);
  }

  /// 驗證資產內容完整性 — content hash 比對
  Future<bool> verifyContentIntegrity(OffChainAsset asset, String content) async {
    final computed = _signatureService.computeContentHash(content);
    return computed == asset.contentHash;
  }

  /// 取得衍生鏈 — 追蹤上游所有祖先
  Future<List<OffChainAsset>> getDerivationChain(String assetId) async {
    final chain = <OffChainAsset>[];
    var current = await getAsset(assetId);
    while (current != null && current.derivedFromAssetId != null) {
      final parent = await getAsset(current.derivedFromAssetId!);
      if (parent == null) break;
      chain.add(parent);
      current = parent;
      // 防止循環
      if (chain.length > 10) break;
    }
    return chain;
  }

  /// 取得直接衍生資產
  Future<List<OffChainAsset>> getDerivatives(String assetId) async {
    final all = await getAllAssets();
    return all.where((a) => a.derivedFromAssetId == assetId).toList();
  }

  /// 更新授權條款
  Future<OffChainAsset?> updateLicense(
      String assetId, SemidaoLicense license) async {
    final asset = await getAsset(assetId);
    if (asset == null) return null;
    final updated = asset.copyWith(license: license, updatedAt: DateTime.now());
    await _storeAsset(updated);
    return updated;
  }

  /// 從 IPFS 讀回資產內容
  Future<String?> retrieveContent(OffChainAsset asset) async {
    if (asset.ipfsRecord == null) return null;
    return _ipfsService.retrieve(asset.ipfsRecord!.cid);
  }

  /// 清除所有資料（測試用）
  Future<void> clearForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storeKey);
  }

  // ── 內部方法 ──

  Future<void> _storeAsset(OffChainAsset asset) async {
    final all = List<OffChainAsset>.of(await getAllAssets());
    final index = all.indexWhere((a) => a.id == asset.id);
    if (index >= 0) {
      all[index] = asset;
    } else {
      all.add(asset);
    }
    await _saveAll(all);
  }

  Future<void> _addDerivativeLink(String parentId, String childId) async {
    final parent = await getAsset(parentId);
    if (parent == null) return;
    final updatedDerivatives = [...parent.derivativeAssetIds, childId];
    final updated = parent.copyWith(
      derivativeAssetIds: updatedDerivatives,
      updatedAt: DateTime.now(),
    );
    await _storeAsset(updated);
  }

  Future<void> _saveAll(List<OffChainAsset> assets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storeKey,
      jsonEncode(assets.map((a) => a.toJson()).toList()),
    );
  }
}
