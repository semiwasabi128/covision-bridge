// semidao_models.dart
// SemiDAO Phase 1: Off-chain 資料模型
//
// 資產確權 + 簽章 + IPFS 存證 + 衍生追蹤 — 全部 off-chain
// Phase 2 再上鏈

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 授權條款類型
enum SemidaoLicenseType {
  ccBy,
  ccBySa,
  mit,
  proprietary,
  commercial;

  String get label {
    switch (this) {
      case SemidaoLicenseType.ccBy:
        return 'CC-BY';
      case SemidaoLicenseType.ccBySa:
        return 'CC-BY-SA';
      case SemidaoLicenseType.mit:
        return 'MIT';
      case SemidaoLicenseType.proprietary:
        return '專有授權';
      case SemidaoLicenseType.commercial:
        return '商業授權';
    }
  }

  static SemidaoLicenseType fromName(String? name) {
    return SemidaoLicenseType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SemidaoLicenseType.ccBySa,
    );
  }
}

/// 資產種類
enum SemidaoAssetKind {
  workflow,
  playbook,
  plugin,
  knowledgePack;

  String get label {
    switch (this) {
      case SemidaoAssetKind.workflow:
        return '工作流';
      case SemidaoAssetKind.playbook:
        return '玩法';
      case SemidaoAssetKind.plugin:
        return '插件';
      case SemidaoAssetKind.knowledgePack:
        return '知識包';
    }
  }

  static SemidaoAssetKind fromName(String? name) {
    return SemidaoAssetKind.values.firstWhere(
      (e) => e.name == name,
      orElse: () => SemidaoAssetKind.workflow,
    );
  }
}

/// 創作者身份 — App 內生成的 keypair 指紋
@immutable
class SemidaoCreator {
  /// 公鑰指紋（SHA-256 of public key，hex）
  final String publicKeyFingerprint;

  /// 顯示名稱
  final String displayName;

  /// 創建時間
  final DateTime createdAt;

  const SemidaoCreator({
    required this.publicKeyFingerprint,
    required this.displayName,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'publicKeyFingerprint': publicKeyFingerprint,
        'displayName': displayName,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SemidaoCreator.fromJson(Map<String, dynamic> json) {
    return SemidaoCreator(
      publicKeyFingerprint: json['publicKeyFingerprint'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '匿名',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// 授權條款
@immutable
class SemidaoLicense {
  final SemidaoLicenseType licenseType;
  final int price; // 商業授權價格（0 = 免費）
  final int commercialSplit; // 商業使用創作者抽成（basis points, 0-10000）
  final bool derivativeAllowed;
  final int derivativeSplit; // 衍生作品收入分給原始創作者（basis points）

  const SemidaoLicense({
    this.licenseType = SemidaoLicenseType.ccBySa,
    this.price = 0,
    this.commercialSplit = 9000,
    this.derivativeAllowed = true,
    this.derivativeSplit = 1000,
  });

  Map<String, dynamic> toJson() => {
        'licenseType': licenseType.name,
        'price': price,
        'commercialSplit': commercialSplit,
        'derivativeAllowed': derivativeAllowed,
        'derivativeSplit': derivativeSplit,
      };

  factory SemidaoLicense.fromJson(Map<String, dynamic> json) {
    return SemidaoLicense(
      licenseType: SemidaoLicenseType.fromName(json['licenseType']?.toString()),
      price: (json['price'] as num?)?.toInt() ?? 0,
      commercialSplit: (json['commercialSplit'] as num?)?.toInt() ?? 9000,
      derivativeAllowed: json['derivativeAllowed'] != false,
      derivativeSplit: (json['derivativeSplit'] as num?)?.toInt() ?? 1000,
    );
  }
}

/// 數位簽章 — App 內 HMAC-SHA256 模擬
@immutable
class SemidaoSignature {
  /// 簽章內容（HMAC-SHA256 hex）
  final String signature;

  /// 被簽章的 content hash（SHA-256 hex）
  final String contentHash;

  /// 簽章時間
  final DateTime signedAt;

  /// 簽章者公鑰指紋
  final String signerFingerprint;

  const SemidaoSignature({
    required this.signature,
    required this.contentHash,
    required this.signedAt,
    required this.signerFingerprint,
  });

  Map<String, dynamic> toJson() => {
        'signature': signature,
        'contentHash': contentHash,
        'signedAt': signedAt.toIso8601String(),
        'signerFingerprint': signerFingerprint,
      };

  factory SemidaoSignature.fromJson(Map<String, dynamic> json) {
    return SemidaoSignature(
      signature: json['signature'] as String? ?? '',
      contentHash: json['contentHash'] as String? ?? '',
      signedAt: DateTime.tryParse(json['signedAt']?.toString() ?? '') ??
          DateTime.now(),
      signerFingerprint: json['signerFingerprint'] as String? ?? '',
    );
  }
}

/// IPFS 存證記錄 — Phase 1 用本地模擬
@immutable
class SemidaoIpfsRecord {
  /// 模擬 CID（Phase 1 用本地 hash 代替）
  final String cid;

  /// 本地存檔路徑
  final String localPath;

  /// 存證時間
  final DateTime pinnedAt;

  /// 存證大小（bytes）
  final int sizeBytes;

  const SemidaoIpfsRecord({
    required this.cid,
    required this.localPath,
    required this.pinnedAt,
    required this.sizeBytes,
  });

  Map<String, dynamic> toJson() => {
        'cid': cid,
        'localPath': localPath,
        'pinnedAt': pinnedAt.toIso8601String(),
        'sizeBytes': sizeBytes,
      };

  factory SemidaoIpfsRecord.fromJson(Map<String, dynamic> json) {
    return SemidaoIpfsRecord(
      cid: json['cid'] as String? ?? '',
      localPath: json['localPath'] as String? ?? '',
      pinnedAt: DateTime.tryParse(json['pinnedAt']?.toString() ?? '') ??
          DateTime.now(),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Off-chain 資產 — Phase 1 完整資料模型
@immutable
class OffChainAsset {
  /// 唯一 ID（UUID）
  final String id;

  /// 資產名稱
  final String name;

  /// 資產種類
  final SemidaoAssetKind kind;

  /// 創作者
  final SemidaoCreator creator;

  /// Content hash（SHA-256 of workflow JSON）
  final String contentHash;

  /// IPFS 存證
  final SemidaoIpfsRecord? ipfsRecord;

  /// 數位簽章
  final SemidaoSignature? signature;

  /// 授權條款
  final SemidaoLicense license;

  /// 衍生來源 asset ID（null = 原創）
  final String? derivedFromAssetId;

  /// 衍生資產 ID 列表
  final List<String> derivativeAssetIds;

  /// 創建時間
  final DateTime createdAt;

  /// 更新時間
  final DateTime updatedAt;

  /// 資產描述
  final String description;

  const OffChainAsset({
    required this.id,
    required this.name,
    required this.kind,
    required this.creator,
    required this.contentHash,
    this.ipfsRecord,
    this.signature,
    this.license = const SemidaoLicense(),
    this.derivedFromAssetId,
    this.derivativeAssetIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
  });

  /// 是否為原創（非衍生）
  bool get isOriginal => derivedFromAssetId == null;

  /// 是否已簽章
  bool get isSigned => signature != null;

  /// 是否已存證
  bool get isPinned => ipfsRecord != null;

  OffChainAsset copyWith({
    SemidaoIpfsRecord? ipfsRecord,
    SemidaoSignature? signature,
    SemidaoLicense? license,
    String? derivedFromAssetId,
    List<String>? derivativeAssetIds,
    DateTime? updatedAt,
    String? description,
  }) {
    return OffChainAsset(
      id: id,
      name: name,
      kind: kind,
      creator: creator,
      contentHash: contentHash,
      ipfsRecord: ipfsRecord ?? this.ipfsRecord,
      signature: signature ?? this.signature,
      license: license ?? this.license,
      derivedFromAssetId: derivedFromAssetId ?? this.derivedFromAssetId,
      derivativeAssetIds: derivativeAssetIds ?? this.derivativeAssetIds,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'creator': creator.toJson(),
        'contentHash': contentHash,
        'ipfsRecord': ipfsRecord?.toJson(),
        'signature': signature?.toJson(),
        'license': license.toJson(),
        'derivedFromAssetId': derivedFromAssetId,
        'derivativeAssetIds': derivativeAssetIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'description': description,
      };

  factory OffChainAsset.fromJson(Map<String, dynamic> json) {
    return OffChainAsset(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '未命名',
      kind: SemidaoAssetKind.fromName(json['kind']?.toString()),
      creator: SemidaoCreator.fromJson(
          json['creator'] as Map<String, dynamic>? ?? {}),
      contentHash: json['contentHash'] as String? ?? '',
      ipfsRecord: json['ipfsRecord'] != null
          ? SemidaoIpfsRecord.fromJson(
              json['ipfsRecord'] as Map<String, dynamic>)
          : null,
      signature: json['signature'] != null
          ? SemidaoSignature.fromJson(
              json['signature'] as Map<String, dynamic>)
          : null,
      license: SemidaoLicense.fromJson(
          json['license'] as Map<String, dynamic>? ?? {}),
      derivedFromAssetId: json['derivedFromAssetId'] as String?,
      derivativeAssetIds: (json['derivativeAssetIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      description: json['description'] as String? ?? '',
    );
  }

  String toJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  static OffChainAsset fromJsonString(String jsonStr) {
    return OffChainAsset.fromJson(
        jsonDecode(jsonStr) as Map<String, dynamic>);
  }
}
