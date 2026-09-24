// device_node.dart
// Device Node 抽象 — 統一描述桌面、手機、眼鏡、手錶等裝置的能力。
// 桌面啟動時回報自己的能力（browser.automation, file.read, file.write, long_task.run）。
// 未來手機、眼鏡、手錶都用同一個抽象。
// Sprint 19d by 教練 Agent (CEO)

/// 裝置類型。
enum DeviceNodeType {
  desktop,  // macOS / Windows / Linux 桌面
  phone,    // iOS / Android 手機
  glasses,  // AR 眼鏡（未來）
  watch,    // 智慧手錶（未來）
  tablet,   // 平板（未來）
}

/// 裝置能力狀態。
enum DeviceCapabilityStatus {
  ready,    // 能力可用
  pending,  // 能力即將可用
  blocked,  // 能力被環境阻擋
}

/// 裝置能力描述。
class DeviceCapability {
  /// 能力 ID（如 "browser.automation", "file.read", "long_task.run"）
  final String id;

  /// 人類可讀標籤
  final String label;

  /// 詳細說明
  final String detail;

  /// 狀態
  final DeviceCapabilityStatus status;

  const DeviceCapability({
    required this.id,
    required this.label,
    required this.detail,
    required this.status,
  });

  factory DeviceCapability.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'pending';
    final status = DeviceCapabilityStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => DeviceCapabilityStatus.pending,
    );
    return DeviceCapability(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      status: status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'detail': detail,
      'status': status.name,
    };
  }
}

/// 裝置節點 — 描述一個橋樑生態中的裝置。
///
/// 每個裝置有自己的 ID、名稱、類型、能力列表。
/// 桌面啟動時建立自己的 DeviceNode，手機配對後也建立自己的。
/// 未來所有裝置（眼鏡、手錶）都用同一個抽象。
class DeviceNode {
  /// 裝置唯一 ID（如 "desktop-001", "phone-iphone15"）
  final String deviceId;

  /// 裝置名稱（如 "使用者的 Mac Mini", "iPhone 15 Pro"）
  final String name;

  /// 裝置類型
  final DeviceNodeType type;

  /// 能力列表
  final List<DeviceCapability> capabilities;

  /// 上次心跳時間
  final DateTime? lastSeen;

  /// 是否線上
  final bool online;

  const DeviceNode({
    required this.deviceId,
    required this.name,
    required this.type,
    this.capabilities = const [],
    this.lastSeen,
    this.online = true,
  });

  /// 檢查是否擁有某能力
  bool hasCapability(String capabilityId) {
    return capabilities.any((c) => c.id == capabilityId && c.status == DeviceCapabilityStatus.ready);
  }

  /// 取得所有 ready 的能力
  List<DeviceCapability> get readyCapabilities =>
      capabilities.where((c) => c.status == DeviceCapabilityStatus.ready).toList();

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'name': name,
      'type': type.name,
      'capabilities': [for (final c in capabilities) c.toJson()],
      'lastSeen': lastSeen?.toIso8601String(),
      'online': online,
    };
  }

  /// 建立桌面裝置節點
  factory DeviceNode.desktop({
    required String deviceId,
    required String name,
    bool browserAutomationReady = false,
    bool longTaskReady = false,
    bool fileReadReady = true,
    bool fileWriteReady = true,
  }) {
    return DeviceNode(
      deviceId: deviceId,
      name: name,
      type: DeviceNodeType.desktop,
      capabilities: [
        DeviceCapability(
          id: 'runtime-channel',
          label: 'Runtime Channel',
          detail: '同步夥伴狀態、表情、行為與工作文字。',
          status: DeviceCapabilityStatus.ready,
        ),
        DeviceCapability(
          id: 'browser.automation',
          label: 'Browser Automation',
          detail: browserAutomationReady
              ? '可用 Chrome 自動化操作網頁。'
              : 'Chrome 瀏覽器自動化尚未啟動。',
          status: browserAutomationReady
              ? DeviceCapabilityStatus.ready
              : DeviceCapabilityStatus.pending,
        ),
        DeviceCapability(
          id: 'file.read',
          label: 'File Read',
          detail: '讀取桌面端檔案。',
          status: fileReadReady
              ? DeviceCapabilityStatus.ready
              : DeviceCapabilityStatus.pending,
        ),
        DeviceCapability(
          id: 'file.write',
          label: 'File Write',
          detail: '寫入桌面端檔案。',
          status: fileWriteReady
              ? DeviceCapabilityStatus.ready
              : DeviceCapabilityStatus.pending,
        ),
        DeviceCapability(
          id: 'long_task.run',
          label: 'Long Task Runner',
          detail: longTaskReady
              ? '可在桌面端執行長任務（瀏覽器操作、檔案下載等）。'
              : '長任務佇列尚未啟動。',
          status: longTaskReady
              ? DeviceCapabilityStatus.ready
              : DeviceCapabilityStatus.pending,
        ),
      ],
    );
  }

  /// 建立手機裝置節點
  factory DeviceNode.phone({
    required String deviceId,
    required String name,
  }) {
    return DeviceNode(
      deviceId: deviceId,
      name: name,
      type: DeviceNodeType.phone,
      capabilities: [
        const DeviceCapability(
          id: 'runtime-channel',
          label: 'Runtime Channel',
          detail: '接收夥伴狀態、表情、行為與工作文字。',
          status: DeviceCapabilityStatus.ready,
        ),
        const DeviceCapability(
          id: 'task.control',
          label: 'Task Control',
          detail: '發送任務指令到桌面端，接收進度推播。',
          status: DeviceCapabilityStatus.ready,
        ),
        const DeviceCapability(
          id: 'camera.scan',
          label: 'Camera Scan',
          detail: 'QR 配對掃描。',
          status: DeviceCapabilityStatus.ready,
        ),
      ],
    );
  }
}
