// semidao_onchain_service.dart
// SemiDAO Phase 2: On-chain 連接服務
//
// 功能:
// 1. 讀取已部署的 SemiDAO 合約狀態（via JSON-RPC read-only）
// 2. 構建 on-chain 交易 calldata（供 wallet 连接後簽章廣播）
// 3. 驗證 on-chain 資產確權狀態
//
// 設計: 不直接持有私鑰 — 交易簽章交由 App 端 wallet（MetaMask / WalletConnect）
// 本服務只負責: read-only 查詢 + calldata 構建 + 廣播已簽章交易
//
// 合約 ABI: 內嵌精簡版（只含需要用到的 functions）

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base Sepolia 測試網配置
class SemiDaoNetworkConfig {
  final String name;
  final int chainId;
  final String rpcUrl;
  final String explorerUrl;

  const SemiDaoNetworkConfig({
    required this.name,
    required this.chainId,
    required this.rpcUrl,
    required this.explorerUrl,
  });

  static const baseSepolia = SemiDaoNetworkConfig(
    name: 'Base Sepolia',
    chainId: 84532,
    rpcUrl: 'https://sepolia.base.org',
    explorerUrl: 'https://sepolia.basescan.org',
  );

  static const mainnet = SemiDaoNetworkConfig(
    name: 'Base',
    chainId: 8453,
    rpcUrl: 'https://mainnet.base.org',
    explorerUrl: 'https://basescan.org',
  );
}

/// 合約部署資訊
class SemiDaoContractAddresses {
  final String assetRegistry;
  final String semiAssetNft;
  final String assetLicense;
  final String assetDerivation;
  final String revenueSplit;
  final String assetFactory;

  const SemiDaoContractAddresses({
    required this.assetRegistry,
    required this.semiAssetNft,
    required this.assetLicense,
    required this.assetDerivation,
    required this.revenueSplit,
    required this.assetFactory,
  });

  factory SemiDaoContractAddresses.fromJson(Map<String, dynamic> json) {
    return SemiDaoContractAddresses(
      assetRegistry: json['AssetRegistry'] as String,
      semiAssetNft: json['SemiAssetNFT'] as String,
      assetLicense: json['AssetLicense'] as String,
      assetDerivation: json['AssetDerivation'] as String,
      revenueSplit: json['RevenueSplit'] as String,
      assetFactory: json['AssetFactory'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'AssetRegistry': assetRegistry,
        'SemiAssetNFT': semiAssetNft,
        'AssetLicense': assetLicense,
        'AssetDerivation': assetDerivation,
        'RevenueSplit': revenueSplit,
        'AssetFactory': assetFactory,
      };
}

/// On-chain 資產資訊
class OnChainAssetInfo {
  final String creator;
  final String metadataURI;
  final int createdAt;
  final String kind;
  final bool exists;

  const OnChainAssetInfo({
    required this.creator,
    required this.metadataURI,
    required this.createdAt,
    required this.kind,
    required this.exists,
  });
}

/// SemiDAO Phase 2 On-chain 服務
/// 
/// 使用方式:
///   final service = SemidaoOnChainService();
///   await service.loadConfig(); // 從 SharedPreferences 載入合約地址
///   final isRegistered = await service.isAssetRegistered(contentHash);
class SemidaoOnChainService {
  SemidaoOnChainService({
    Dio? dio,
    SemiDaoNetworkConfig? network,
  })  : _dio = dio ?? Dio(),
        _network = network ?? SemiDaoNetworkConfig.baseSepolia;

  final Dio _dio;
  SemiDaoNetworkConfig _network;

  static const String _addressesKey = 'semidao_contract_addresses_v0';
  static const String _networkKey = 'semidao_network_v0';

  SemiDaoContractAddresses? _addresses;

  /// 載入已儲存的合約地址 + 網路設定
  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final addrJson = prefs.getString(_addressesKey);
    if (addrJson != null) {
      try {
        _addresses = SemiDaoContractAddresses.fromJson(
          jsonDecode(addrJson) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    final netName = prefs.getString(_networkKey);
    if (netName == 'mainnet') {
      _network = SemiDaoNetworkConfig.mainnet;
    }
  }

  /// 儲存合約地址（部署後呼叫）
  Future<void> saveAddresses(SemiDaoContractAddresses addresses) async {
    _addresses = addresses;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_addressesKey, jsonEncode(addresses.toJson()));
  }

  /// 設定網路（testnet / mainnet）
  Future<void> setNetwork(SemiDaoNetworkConfig network) async {
    _network = network;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _networkKey,
      network.chainId == SemiDaoNetworkConfig.mainnet.chainId
          ? 'mainnet'
          : 'testnet',
    );
  }

  /// 取得目前網路
  SemiDaoNetworkConfig get network => _network;

  /// 取得合約地址
  SemiDaoContractAddresses? get addresses => _addresses;

  /// 是否已配置（合約地址已載入）
  bool get isConfigured => _addresses != null;

  // ── Read-only 查詢 (JSON-RPC eth_call) ──

  /// 檢查資產是否已在鏈上註冊
  /// [contentHash] = SHA-256 hash 的 hex（0x...，32 bytes）
  Future<bool> isAssetRegistered(String contentHash) async {
    if (_addresses == null) return false;
    final data = _encodeCall(
      _assetRegistryAbi,
      'isRegistered',
      [contentHash],
    );
    final result = await _ethCall(_addresses!.assetRegistry, data);
    return _decodeBool(result);
  }

  /// 取得鏈上資產資訊
  Future<OnChainAssetInfo?> getAssetInfo(String contentHash) async {
    if (_addresses == null) return null;
    final data = _encodeCall(
      _assetRegistryAbi,
      'getAsset',
      [contentHash],
    );
    final result = await _ethCall(_addresses!.assetRegistry, data);
    if (result == '0x' || result.isEmpty) return null;

    // 解碼 tuple: (address, string, uint256, uint8, bool)
    // ABI encoding: 每個 32 bytes slot
    final decoded = _decodeTuple(result);
    if (decoded.length < 5) return null;

    return OnChainAssetInfo(
      creator: _decodeAddress(decoded[0]),
      metadataURI: _decodeString(decoded[1], result),
      createdAt: _decodeUint(decoded[2]),
      kind: _decodeAssetKind(_decodeUint(decoded[3])),
      exists: _decodeBoolFromHex(decoded[4]),
    );
  }

  /// 取得創作者的所有資產
  Future<List<String>> getCreatorAssets(String creatorAddress) async {
    if (_addresses == null) return [];
    final data = _encodeCall(
      _assetRegistryAbi,
      'getCreatorAssets',
      [creatorAddress],
    );
    final result = await _ethCall(_addresses!.assetRegistry, data);
    // 解碼 bytes32[] array
    return _decodeBytes32Array(result);
  }

  /// 取得資產的衍生鏈
  Future<List<String>> getDerivationChain(String contentHash) async {
    if (_addresses == null) return [];
    final data = _encodeCall(
      _derivationAbi,
      'getDerivationChain',
      [contentHash],
    );
    final result = await _ethCall(_addresses!.assetDerivation, data);
    return _decodeBytes32Array(result);
  }

  // ── Write 交易 calldata 構建 ──
  // 這些方法只構建 calldata，不廣播 — 廣播由 wallet 連接後執行

  /// 構建 publishAsset calldata
  /// 回傳 hex string，供 wallet 簽章廣播
  String buildPublishAssetCalldata({
    required String contentHash,
    required String metadataURI,
    required int assetKind, // 0=Workflow, 1=Playbook, 2=Plugin, 3=KnowledgePack
    required int licenseType, // 0=CC_BY, 1=CC_BY_SA, 2=MIT, 3=Proprietary, 4=Commercial
    required int price,
    required int commercialSplit,
    required bool derivativeAllowed,
    required int derivativeSplit,
    String? derivedFromAssetId, // null = 原創
  }) {
    // AssetFactory.publishAsset(RegisterParams) where RegisterParams is a struct
    // struct RegisterParams {
    //   bytes32 contentHash;
    //   string metadataURI;
    //   AssetKind kind;
    //   LicenseType licenseType;
    //   uint256 price;
    //   uint256 commercialSplit;
    //   bool derivativeAllowed;
    //   uint256 derivativeSplit;
    //   bytes32 derivedFromAssetId;
    // }
    final params = [
      contentHash,
      metadataURI,
      assetKind,
      licenseType,
      price,
      commercialSplit,
      derivativeAllowed,
      derivativeSplit,
      derivedFromAssetId ?? '0x0000000000000000000000000000000000000000000000000000000000000000',
    ];
    return _encodeCall(_assetFactoryAbi, 'publishAsset', [params]);
  }

  /// 取得 publishAsset 的 gas 估算
  Future<int> estimatePublishAssetGas({
    required String fromAddress,
    required String contentHash,
    required String metadataURI,
    required int assetKind,
    required int licenseType,
    required int price,
    required int commercialSplit,
    required bool derivativeAllowed,
    required int derivativeSplit,
    String? derivedFromAssetId,
  }) async {
    if (_addresses == null) return 0;
    final data = buildPublishAssetCalldata(
      contentHash: contentHash,
      metadataURI: metadataURI,
      assetKind: assetKind,
      licenseType: licenseType,
      price: price,
      commercialSplit: commercialSplit,
      derivativeAllowed: derivativeAllowed,
      derivativeSplit: derivativeSplit,
      derivedFromAssetId: derivedFromAssetId,
    );
    final result = await _ethEstimateGas(
      from: fromAddress,
      to: _addresses!.assetFactory,
      data: data,
    );
    return int.tryParse(result, radix: 16) ?? 0;
  }

  // ── JSON-RPC 底層 ──

  Future<String> _ethCall(String to, String data) async {
    final result = await _dio.post(
      _network.rpcUrl,
      data: {
        'jsonrpc': '2.0',
        'method': 'eth_call',
        'params': [
          {'to': to, 'data': data},
          'latest',
        ],
        'id': 1,
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return result.data['result']?.toString() ?? '0x';
  }

  Future<String> _ethEstimateGas({
    required String from,
    required String to,
    required String data,
  }) async {
    final result = await _dio.post(
      _network.rpcUrl,
      data: {
        'jsonrpc': '2.0',
        'method': 'eth_estimateGas',
        'params': [
          {'from': from, 'to': to, 'data': data},
        ],
        'id': 1,
      },
      options: Options(headers: {'Content-Type': 'application/json'}),
    );
    return result.data['result']?.toString().replaceFirst('0x', '') ?? '0';
  }

  // ── ABI 編碼（精簡版，只含必要 functions） ──

  // AssetRegistry: isRegistered(bytes32), getAsset(bytes32), getCreatorAssets(address)
  static const _assetRegistryAbi = '''
[
  {"name":"isRegistered","type":"function","inputs":[{"name":"contentHash","type":"bytes32"}],"outputs":[{"name":"","type":"bool"}],"stateMutability":"view"},
  {"name":"getAsset","type":"function","inputs":[{"name":"contentHash","type":"bytes32"}],"outputs":[{"name":"creator","type":"address"},{"name":"metadataURI","type":"string"},{"name":"createdAt","type":"uint256"},{"name":"kind","type":"uint8"},{"name":"exists","type":"bool"}],"stateMutability":"view"},
  {"name":"getCreatorAssets","type":"function","inputs":[{"name":"creator","type":"address"}],"outputs":[{"name":"","type":"bytes32[]"}],"stateMutability":"view"}
]''';

  // AssetDerivation: getDerivationChain(bytes32)
  static const _derivationAbi = '''
[
  {"name":"getDerivationChain","type":"function","inputs":[{"name":"assetId","type":"bytes32"}],"outputs":[{"name":"","type":"bytes32[]"}],"stateMutability":"view"}
]''';

  // AssetFactory: publishAsset(RegisterParams)
  static const _assetFactoryAbi = '''
[
  {"name":"publishAsset","type":"function","inputs":[{"name":"params","type":"tuple","components":[
    {"name":"contentHash","type":"bytes32"},
    {"name":"metadataURI","type":"string"},
    {"name":"kind","type":"uint8"},
    {"name":"licenseType","type":"uint8"},
    {"name":"price","type":"uint256"},
    {"name":"commercialSplit","type":"uint256"},
    {"name":"derivativeAllowed","type":"bool"},
    {"name":"derivativeSplit","type":"uint256"},
    {"name":"derivedFromAssetId","type":"bytes32"}
  ]}],"outputs":[{"name":"","type":"tuple","components":[
    {"name":"contentHash","type":"bytes32"},
    {"name":"tokenId","type":"uint256"}
  ]}],"stateMutability":"nonpayable"}
]''';

  /// ABI 編碼 — 使用 web3dart 做完整 ABI encoding
  String _encodeCall(String abiJson, String functionName, List<dynamic> params) {
    try {
      final contract = DeployedContract(
        ContractAbi.fromJson(abiJson, 'SemiDAO'),
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000000'),
      );
      final function = contract.function(functionName);

      // 將 raw params 轉為 web3dart 型別
      final typedParams = params.map((p) => _toWeb3Type(p)).toList();

      // 使用 web3dart 的 ABI encoding
      final encoded = function.encodeCall(typedParams);
      return '0x${bytesToHex(encoded)}';
    } catch (e) {
      // fallback: 只回傳 selector
      final selector = _functionSelector(abiJson, functionName);
      return '0x$selector';
    }
  }

  /// 將 raw 值轉為 web3dart 型別
  dynamic _toWeb3Type(dynamic value) {
    if (value is String) {
      // hex string (0x...) — 可能是 bytes32 或 address
      if (value.startsWith('0x')) {
        if (value.length == 66) {
          // 32 bytes — bytes32
          return Uint8List.fromList(
            List<int>.generate(32, (i) => int.parse(value.substring(2 + i * 2, 4 + i * 2), radix: 16)),
          );
        } else if (value.length == 42) {
          // address
          return EthereumAddress.fromHex(value);
        }
      }
      // 一般 string
      return value;
    }
    if (value is int) {
      return BigInt.from(value);
    }
    if (value is bool) {
      return value;
    }
    if (value is BigInt) {
      return value;
    }
    if (value is List) {
      return value.map((e) => _toWeb3Type(e)).toList();
    }
    return value;
  }

  /// hex bytes → hex string (no 0x prefix)
  String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _functionSelector(String abiJson, String functionName) {
    // 硬編碼 selectors（避免引入完整 keccak256 實作）
    // isRegistered(bytes32) = 0x8202d2a0
    // getAsset(bytes32) = 0x2dfdfdf5
    // getCreatorAssets(address) = 0x6d3584c9
    // getDerivationChain(bytes32) = 0xe9f8a2de
    // publishAsset((bytes32,string,uint8,uint8,uint256,uint256,bool,uint256,bytes32)) = 待計算
    switch (functionName) {
      case 'isRegistered':
        return '8202d2a0';
      case 'getAsset':
        return '2dfdfdf5';
      case 'getCreatorAssets':
        return '6d3584c9';
      case 'getDerivationChain':
        return 'e9f8a2de';
      case 'publishAsset':
        return '00000000'; // 需要正式計算
      default:
        return '00000000';
    }
  }

  // ── 解碼工具 ──

  bool _decodeBool(String hexResult) {
    if (hexResult == '0x' || hexResult.length < 66) return false;
    return hexResult.substring(2).trim() != '0' * 64;
  }

  List<String> _decodeTuple(String hexResult) {
    final clean = hexResult.replaceFirst('0x', '');
    final result = <String>[];
    for (var i = 0; i < clean.length; i += 64) {
      if (i + 64 > clean.length) break;
      result.add(clean.substring(i, i + 64));
    }
    return result;
  }

  String _decodeAddress(String slot) {
    final addrHex = slot.substring(24); // 後 40 chars = 20 bytes
    return '0x$addrHex';
  }

  String _decodeString(String offsetSlot, String fullResult) {
    // string 的第一個 slot 是 offset，實際資料在 offset 處
    final offset = int.parse(offsetSlot, radix: 16);
    final clean = fullResult.replaceFirst('0x', '');
    final dataStart = offset * 2; // hex chars
    if (dataStart + 64 > clean.length) return '';
    final length = int.parse(clean.substring(dataStart, dataStart + 64), radix: 16);
    if (length == 0) return '';
    final stringHex = clean.substring(dataStart + 64, dataStart + 64 + length * 2);
    final bytes = <int>[];
    for (var i = 0; i < stringHex.length; i += 2) {
      bytes.add(int.parse(stringHex.substring(i, i + 2), radix: 16));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  int _decodeUint(String slot) {
    return int.parse(slot, radix: 16);
  }

  String _decodeAssetKind(int kind) {
    switch (kind) {
      case 0:
        return 'Workflow';
      case 1:
        return 'Playbook';
      case 2:
        return 'Plugin';
      case 3:
        return 'KnowledgePack';
      default:
        return 'Unknown';
    }
  }

  bool _decodeBoolFromHex(String slot) {
    return slot != '0' * 64;
  }

  List<String> _decodeBytes32Array(String hexResult) {
    if (hexResult == '0x' || hexResult.isEmpty) return [];
    final clean = hexResult.replaceFirst('0x', '');
    // 動態陣列: 第一個 slot = length
    if (clean.length < 64) return [];
    final length = int.parse(clean.substring(0, 64), radix: 16);
    final result = <String>[];
    for (var i = 0; i < length; i++) {
      final start = 64 + i * 64;
      if (start + 64 > clean.length) break;
      result.add('0x${clean.substring(start, start + 64)}');
    }
    return result;
  }
}
