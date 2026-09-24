// mobile_bridge_pairing_screen.dart
// 手機端 Bridge Desktop 配對畫面。
// 掃 QR 或手動輸入 → 連線 → 顯示狀態
// Sprint 15a by 教練 Agent (CEO)

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/mobile_bridge_client.dart';
import '../services/paired_desktop_store.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

class MobileBridgePairingScreen extends StatefulWidget {
  const MobileBridgePairingScreen({super.key});

  @override
  State<MobileBridgePairingScreen> createState() =>
      _MobileBridgePairingScreenState();
}

class _MobileBridgePairingScreenState extends State<MobileBridgePairingScreen> {
  // Singleton — 連線跟 App 生命週期綁定，離開畫面不斷線
  final MobileBridgeClient _client = MobileBridgeClient.instance;
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController(
    text: '8790',
  );
  final TextEditingController _codeController = TextEditingController();

  bool _showScanner = false;
  bool _connecting = false;
  List<PairedDesktop> _paired = [];

  @override
  void initState() {
    super.initState();
    _client.addListener(_onConnectionChanged);
    _loadPairedDesktops();
  }

  @override
  void dispose() {
    // 只移除 listener，不 dispose client — 連線繼續活著
    _client.removeListener(_onConnectionChanged);
    _hostController.dispose();
    _portController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _onConnectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPairedDesktops() async {
    final desktops = await PairedDesktopStore.getAll();
    if (mounted) setState(() => _paired = desktops);
  }

  Future<void> _connect({
    required String host,
    required int port,
    required String code,
  }) async {
    setState(() => _connecting = true);
    final ok = await _client.connect(host: host, port: port, pairingCode: code);
    if (ok && mounted) {
      // 持久化
      final desktop = PairedDesktop(
        id: PairedDesktop.makeId(host, port),
        host: host,
        port: port,
        pairingCode: code,
        desktopName: 'Bridge Desktop',
        pairedAt: DateTime.now(),
      );
      await PairedDesktopStore.add(desktop);
      await _loadPairedDesktops();
    }
    if (mounted) setState(() => _connecting = false);
  }

  void _onQrDetected(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null) return;

    final parsed = MobileBridgeClient.parseQrPayload(raw);
    if (parsed == null) {
      // 不是 bridge:// QR，忽略
      return;
    }

    // 停止掃描
    setState(() => _showScanner = false);

    // 填入手動輸入欄位（讓使用者看到連了什麼）
    _hostController.text = parsed.host;
    _portController.text = parsed.port.toString();
    _codeController.text = parsed.code;

    // 直接連線
    _connect(host: parsed.host, port: parsed.port, code: parsed.code);
  }

  void _manualConnect() {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 8790;
    final code = _codeController.text.trim();

    if (host.isEmpty || code.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填入 IP 位址和配對碼')));
      return;
    }

    _connect(host: host, port: port, code: code);
  }

  void _disconnect() {
    _client.disconnect();
  }

  void _forgetDesktop(PairedDesktop desktop) async {
    await PairedDesktopStore.remove(desktop.id);
    await _loadPairedDesktops();
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final state = _client.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面配對'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 連線狀態卡
            _buildStatusCard(state),
            const SizedBox(height: 16),

            // QR 掃描區或手動輸入
            if (_showScanner) ...[
              _buildScanner(),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => setState(() => _showScanner = false),
                child: const Text('取消掃描'),
              ),
              const SizedBox(height: 16),
            ] else if (!_client.isConnected) ...[
              // 掃描按鈕
              ElevatedButton.icon(
                onPressed: () => setState(() => _showScanner = true),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('掃描 QR 碼'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),

              // 分隔線
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      '或手動輸入',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary,),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),

              // 手動輸入
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: '桌面 IP 位址',
                  hintText: '192.168.1.5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.computer),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        labelText: '配對碼',
                        hintText: 'BRIDGE-XXXXXX',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _connecting ? null : _manualConnect,
                icon: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(_connecting ? '連線中…' : '連線'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],

            // 已配對桌面清單
            if (_paired.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('已配對的桌面', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._paired.map((d) => _buildPairedDesktopTile(d)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BridgeConnectionState state) {
    final ds = BridgeDSColors.of(context);
    final (color, icon, text) = switch (state) {
      BridgeConnectionState.disconnected => (
        ds.textTertiary,
        Icons.cloud_off,
        '未連線',
      ),
      BridgeConnectionState.connecting => (ds.accentYellow, Icons.sync, '連線中…'),
      BridgeConnectionState.connected => (
        ds.accentBlue,
        Icons.cloud_done,
        '已連線',
      ),
      BridgeConnectionState.handshaking => (
        ds.accentYellow,
        Icons.handshake,
        '握手中…',
      ),
      BridgeConnectionState.ready => (
        ds.accentGreen,
        Icons.check_circle,
        '已連線，就緒',
      ),
      BridgeConnectionState.error => (ds.accentRed, Icons.error, '連線錯誤'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 48),
            const SizedBox(height: 8),
            Text(
              text,
              style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.w600,
                color: color,),
            ),
            if (_client.lastError != null &&
                state == BridgeConnectionState.error) ...[
              const SizedBox(height: 4),
              Text(
                _client.lastError!,
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.accentRed),
                textAlign: TextAlign.center,
              ),
            ],
            if (_client.isConnected) ...[
              const SizedBox(height: 8),
              Text(
                _client.connectedEndpoint ?? '',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.grey600,
                  fontFamily: 'monospace',),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('斷線'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 300,
        child: MobileScanner(onDetect: _onQrDetected),
      ),
    );
  }

  Widget _buildPairedDesktopTile(PairedDesktop desktop) {
    final ds = BridgeDSColors.of(context);
    final isActive = _client.connectedEndpoint == desktop.endpoint;

    return Card(
      child: ListTile(
        leading: Icon(
          isActive ? Icons.desktop_windows : Icons.desktop_access_disabled,
          color: isActive ? ds.accentGreen : ds.textTertiary,
        ),
        title: Text(desktop.desktopName),
        subtitle: Text('${desktop.host}:${desktop.port}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isActive)
              IconButton(
                icon: const Icon(Icons.link),
                onPressed: () => _connect(
                  host: desktop.host,
                  port: desktop.port,
                  code: desktop.pairingCode,
                ),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _forgetDesktop(desktop),
            ),
          ],
        ),
      ),
    );
  }
}
