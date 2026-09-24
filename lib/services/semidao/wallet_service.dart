// wallet_service.dart
// SemiDAO Phase 2: 錢包連接服務
//
// 使用 ReownAppKitModal (formerly WalletConnect v2) 連接外部錢包
// App 不持有私鑰 — 只構建交易 calldata，簽章由外部錢包完成
//
// 支援錢包: MetaMask, Trust Wallet, Coinbase Wallet, Phantom 等
//
// Reown AppKit API:
// - ReownAppKitModal(context, projectId, metadata) → 建立實例
// - openModalView() → 顯示 QR code / wallet picker
// - session!.getAddress('eip155') → 取得連接地址
// - request(topic, chainId, request) → 發送 RPC 請求 (personal_sign, eth_sendTransaction)
// - requestWriteContract(...) → 發送合約寫入交易
// - onModalConnect / onModalDisconnect → 事件監聽

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 錢包連接狀態
enum WalletConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// 錢包連接資訊
class WalletConnectionInfo {
  final String address;
  final String? chainId;
  final String? walletName;
  final WalletConnectionState state;

  const WalletConnectionInfo({
    required this.address,
    this.chainId,
    this.walletName,
    this.state = WalletConnectionState.connected,
  });

  bool get isConnected =>
      state == WalletConnectionState.connected && address.isNotEmpty;

  /// 地址縮寫 (0x1234...abcd)
  String get shortAddress {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

/// 錢包服務 — 管理連接生命週期
class WalletService extends ChangeNotifier {
  static const String _sessionKey = 'semidao_wallet_session_v0';
  static const String _projectIdKey = 'semidao_wallet_project_id_v0';

  ReownAppKitModal? _appKitModal;
  WalletConnectionInfo _connection = const WalletConnectionInfo(
    address: '',
    state: WalletConnectionState.disconnected,
  );
  String? _projectId;

  WalletConnectionInfo get connection => _connection;
  bool get isConnected => _connection.isConnected;
  String get address => _connection.address;

  /// 是否已初始化
  bool get isInitialized => _appKitModal != null;

  /// 設定 Reown projectId（從 https://cloud.reown.com 免費取得）
  Future<void> setProjectId(String projectId) async {
    _projectId = projectId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_projectIdKey, projectId);
  }

  /// 取得已儲存的 projectId
  Future<String?> getProjectId() async {
    if (_projectId != null) return _projectId;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_projectIdKey);
  }

  /// 初始化 Reown AppKit Modal
  /// 需要 BuildContext（ReownAppKitModal 需要 context 來顯示 overlay）
  Future<void> initialize({
    required String projectId,
    required dynamic context,
  }) async {
    if (_appKitModal != null) return;
    _projectId = projectId;

    try {
      _appKitModal = ReownAppKitModal(
        context: context,
        projectId: projectId,
        logLevel: LogLevel.nothing,
        metadata: const PairingMetadata(
          name: 'Bridge App — 橋樑計畫',
          description: 'SemiDAO 資產包發佈與管理',
          url: 'https://bridge.app',
          icons: [],
        ),
      );

      // 加入 Base Sepolia 測試網
      ReownAppKitModalNetworks.addSupportedNetworks('eip155', [
        ReownAppKitModalNetworkInfo(
          name: 'Base Sepolia',
          chainId: 'eip155:84532',
          currency: 'ETH',
          explorerUrl: 'https://sepolia.basescan.org',
          rpcUrl: 'https://sepolia.base.org',
          isTestNetwork: true,
        ),
      ]);

      // 監聯連接事件
      _appKitModal!.onModalConnect.subscribe(_onModalConnect);
      _appKitModal!.onModalDisconnect.subscribe(_onModalDisconnect);
      _appKitModal!.onModalError.subscribe(_onModalError);

      await _appKitModal!.init();

      // 如果已有 session，恢復連接狀態
      if (_appKitModal!.session != null) {
        _updateConnectionFromSession();
      }
    } catch (e) {
      debugPrint('[WalletService] initialize error: $e');
      _connection = const WalletConnectionInfo(
        address: '',
        state: WalletConnectionState.error,
      );
      notifyListeners();
    }
  }

  /// 開啟錢包連接 modal（QR 掃碼 / deep link）
  void connect() {
    if (_appKitModal == null) {
      debugPrint('[WalletService] AppKit not initialized');
      return;
    }

    _connection = const WalletConnectionInfo(
      address: '',
      state: WalletConnectionState.connecting,
    );
    notifyListeners();

    _appKitModal!.openModalView();
  }

  void _onModalConnect(ModalConnect? event) {
    _updateConnectionFromSession();
  }

  void _onModalDisconnect(ModalDisconnect? event) {
    _connection = const WalletConnectionInfo(
      address: '',
      state: WalletConnectionState.disconnected,
    );
    _clearSession();
    notifyListeners();
  }

  void _onModalError(ModalError? event) {
    debugPrint('[WalletService] ModalError: ${event?.toString()}');
    if (!_connection.isConnected) {
      _connection = const WalletConnectionInfo(
        address: '',
        state: WalletConnectionState.error,
      );
      notifyListeners();
    }
  }

  void _updateConnectionFromSession() {
    final session = _appKitModal?.session;
    if (session == null) return;

    final address = session.getAddress('eip155');
    if (address == null || address.isEmpty) return;

    _connection = WalletConnectionInfo(
      address: address,
      chainId: _appKitModal?.selectedChain?.chainId,
      state: WalletConnectionState.connected,
    );
    _saveSession();
    notifyListeners();
  }

  /// 斷開錢包連接
  Future<void> disconnect() async {
    if (_appKitModal == null) return;

    try {
      await _appKitModal!.disconnect();
    } catch (e) {
      debugPrint('[WalletService] disconnect error: $e');
    }

    _connection = const WalletConnectionInfo(
      address: '',
      state: WalletConnectionState.disconnected,
    );
    _clearSession();
    notifyListeners();
  }

  // ── 交易方法 ──

  /// 發送 on-chain 合約寫入交易（資產發佈）
  /// 使用 web3dart 構建正確的 ABI encoding
  /// 回傳 tx hash
  Future<String?> publishAssetOnChain({
    required String contractAddress,
    required String abiJson,
    required String functionName,
    required List<dynamic> parameters,
  }) async {
    final modal = _appKitModal;
    if (modal == null || !_connection.isConnected || modal.session == null) {
      debugPrint('[WalletService] Not connected');
      return null;
    }

    try {
      // 使用 web3dart 構建 DeployedContract
      final contract = DeployedContract(
        ContractAbi.fromJson(abiJson, 'SemiDAO'),
        EthereumAddress.fromHex(contractAddress),
      );

      final result = await modal.requestWriteContract(
        topic: modal.session!.topic,
        chainId: modal.selectedChain!.chainId,
        deployedContract: contract,
        functionName: functionName,
        transaction: Transaction(
          from: EthereumAddress.fromHex(_connection.address),
        ),
        parameters: parameters,
      );

      return result?.toString();
    } catch (e) {
      debugPrint('[WalletService] publishAssetOnChain error: $e');
      return null;
    }
  }

  /// 簽章訊息（用於 off-chain 資產確權）
  Future<String?> signMessage(String message) async {
    final modal = _appKitModal;
    if (modal == null || !_connection.isConnected || modal.session == null) {
      return null;
    }

    try {
      final bytes = utf8.encode(message);
      final encoded = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final result = await modal.request(
        topic: modal.session!.topic,
        chainId: modal.selectedChain!.chainId,
        request: SessionRequestParams(
          method: 'personal_sign',
          params: ['0x$encoded', _connection.address],
        ),
      );

      return result?.toString();
    } catch (e) {
      debugPrint('[WalletService] signMessage error: $e');
      return null;
    }
  }

  /// 發送原始 eth_sendTransaction
  Future<String?> sendTransaction({
    required String to,
    required String data,
    BigInt? value,
  }) async {
    final modal = _appKitModal;
    if (modal == null || !_connection.isConnected || modal.session == null) {
      return null;
    }

    try {
      final tx = Transaction(
        from: EthereumAddress.fromHex(_connection.address),
        to: EthereumAddress.fromHex(to),
        data: Uint8List.fromList(
          // hex string → bytes
          _hexToBytes(data),
        ),
        value: value != null
            ? EtherAmount.fromBigInt(EtherUnit.wei, value)
            : null,
      );

      final result = await modal.request(
        topic: modal.session!.topic,
        chainId: modal.selectedChain!.chainId,
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [tx.toJson()],
        ),
      );

      return result?.toString();
    } catch (e) {
      debugPrint('[WalletService] sendTransaction error: $e');
      return null;
    }
  }

  // ── Session 持久化 ──

  void _saveSession() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool(_sessionKey, true);
    });
  }

  void _clearSession() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_sessionKey);
    });
  }

  // ── 工具方法 ──

  List<int> _hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      if (i + 2 <= clean.length) {
        result.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
    }
    return result;
  }

  @override
  void dispose() {
    _appKitModal?.onModalConnect.unsubscribe(_onModalConnect);
    _appKitModal?.onModalDisconnect.unsubscribe(_onModalDisconnect);
    _appKitModal?.onModalError.unsubscribe(_onModalError);
    _appKitModal?.dispose();
    super.dispose();
  }
}
