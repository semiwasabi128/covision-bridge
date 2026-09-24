class DesktopCompanionShellConfig {
  final bool transparent;
  final bool frameless;
  final bool alwaysOnTop;
  final bool draggable;
  final bool trayEnabled;
  final bool launchAtLogin;
  final double width;
  final double height;
  final String runtimeChannel;

  const DesktopCompanionShellConfig({
    this.transparent = true,
    this.frameless = true,
    this.alwaysOnTop = true,
    this.draggable = true,
    this.trayEnabled = true,
    this.launchAtLogin = false,
    this.width = 228,
    this.height = 286,
    this.runtimeChannel = 'bridge.runtime.v1',
  });

  DesktopCompanionShellConfig copyWith({
    bool? transparent,
    bool? frameless,
    bool? alwaysOnTop,
    bool? draggable,
    bool? trayEnabled,
    bool? launchAtLogin,
    double? width,
    double? height,
    String? runtimeChannel,
  }) {
    return DesktopCompanionShellConfig(
      transparent: transparent ?? this.transparent,
      frameless: frameless ?? this.frameless,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      draggable: draggable ?? this.draggable,
      trayEnabled: trayEnabled ?? this.trayEnabled,
      launchAtLogin: launchAtLogin ?? this.launchAtLogin,
      width: width ?? this.width,
      height: height ?? this.height,
      runtimeChannel: runtimeChannel ?? this.runtimeChannel,
    );
  }

  Map<String, dynamic> toJson() => {
    'transparent': transparent,
    'frameless': frameless,
    'alwaysOnTop': alwaysOnTop,
    'draggable': draggable,
    'trayEnabled': trayEnabled,
    'launchAtLogin': launchAtLogin,
    'width': width,
    'height': height,
    'runtimeChannel': runtimeChannel,
  };

  factory DesktopCompanionShellConfig.fromJson(Map<String, dynamic> json) {
    return DesktopCompanionShellConfig(
      transparent: _readBool(json, 'transparent', true),
      frameless: _readBool(json, 'frameless', true),
      alwaysOnTop: _readBool(json, 'alwaysOnTop', true),
      draggable: _readBool(json, 'draggable', true),
      trayEnabled: _readBool(json, 'trayEnabled', true),
      launchAtLogin: _readBool(json, 'launchAtLogin', false),
      width: _readDouble(json, 'width', 228),
      height: _readDouble(json, 'height', 286),
      runtimeChannel: json['runtimeChannel'] is String
          ? json['runtimeChannel'] as String
          : 'bridge.runtime.v1',
    );
  }

  static bool _readBool(Map<String, dynamic> json, String key, bool fallback) {
    return json[key] is bool ? json[key] as bool : fallback;
  }

  static double _readDouble(
    Map<String, dynamic> json,
    String key,
    double fallback,
  ) {
    final value = json[key];
    return value is num ? value.toDouble() : fallback;
  }
}

enum DesktopShellCapabilityStatus { simulated, ready, nativeRequired }

class DesktopShellCapability {
  final String id;
  final String label;
  final String detail;
  final DesktopShellCapabilityStatus status;

  const DesktopShellCapability({
    required this.id,
    required this.label,
    required this.detail,
    required this.status,
  });

  bool get isAvailable =>
      status == DesktopShellCapabilityStatus.simulated ||
      status == DesktopShellCapabilityStatus.ready;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'detail': detail,
    'status': status.name,
    'available': isAvailable,
  };
}

class DesktopCompanionShellPlan {
  final DesktopCompanionShellConfig config;
  final List<DesktopShellCapability> capabilities;

  const DesktopCompanionShellPlan({
    required this.config,
    required this.capabilities,
  });

  int get simulatedCount => capabilities
      .where((item) => item.status == DesktopShellCapabilityStatus.simulated)
      .length;

  int get nativeRequiredCount => capabilities
      .where(
        (item) => item.status == DesktopShellCapabilityStatus.nativeRequired,
      )
      .length;

  Map<String, dynamic> toJson() => {
    'config': config.toJson(),
    'summary': {
      'capabilities': capabilities.length,
      'simulated': simulatedCount,
      'nativeRequired': nativeRequiredCount,
    },
    'capabilities': capabilities.map((item) => item.toJson()).toList(),
  };
}

class DesktopCompanionShellService {
  const DesktopCompanionShellService();

  DesktopCompanionShellPlan buildPlan([
    DesktopCompanionShellConfig config = const DesktopCompanionShellConfig(),
  ]) {
    return DesktopCompanionShellPlan(
      config: config,
      capabilities: [
        DesktopShellCapability(
          id: 'runtime-channel',
          label: 'Runtime Channel',
          detail: '讀取 ${config.runtimeChannel}，同步夥伴狀態、動作與工作文字。',
          status: DesktopShellCapabilityStatus.ready,
        ),
        const DesktopShellCapability(
          id: 'floating-window',
          label: '透明小窗',
          detail: '目前已在 Flutter 頁面內模擬透明浮層，之後搬到桌面無邊框視窗。',
          status: DesktopShellCapabilityStatus.simulated,
        ),
        const DesktopShellCapability(
          id: 'drag-anchor',
          label: '拖曳停靠',
          detail: '拖曳後進入停靠模式，未來可儲存到桌面端本機偏好。',
          status: DesktopShellCapabilityStatus.simulated,
        ),
        const DesktopShellCapability(
          id: 'wander-loop',
          label: '桌面漫遊',
          detail: '依 runtime tick 與 action 產生漫遊位移，可接入桌面座標系。',
          status: DesktopShellCapabilityStatus.simulated,
        ),
        const DesktopShellCapability(
          id: 'always-on-top',
          label: '置頂視窗',
          detail: '需要 macOS/Windows 原生視窗插件接入 always-on-top。',
          status: DesktopShellCapabilityStatus.nativeRequired,
        ),
        const DesktopShellCapability(
          id: 'system-tray',
          label: '托盤選單',
          detail: '需要桌面端原生托盤能力，提供顯示/隱藏、暫停、切換夥伴。',
          status: DesktopShellCapabilityStatus.nativeRequired,
        ),
        const DesktopShellCapability(
          id: 'launch-login',
          label: '開機啟動',
          detail: '需要平台權限與使用者確認，用於常駐桌面夥伴。',
          status: DesktopShellCapabilityStatus.nativeRequired,
        ),
      ],
    );
  }
}
