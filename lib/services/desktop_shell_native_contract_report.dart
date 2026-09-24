enum DesktopShellNativeContractStatus { ready, blocked }

class DesktopShellNativeContractItem {
  final String id;
  final String label;
  final String detail;
  final String token;
  final DesktopShellNativeContractStatus status;

  const DesktopShellNativeContractItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.token,
    required this.status,
  });

  bool get ready => status == DesktopShellNativeContractStatus.ready;

  Map<String, Object> toJson() {
    return {
      'id': id,
      'label': label,
      'detail': detail,
      'token': token,
      'status': status.name,
    };
  }
}

class DesktopShellNativeContractReport {
  final String schema;
  final String sourcePath;
  final String summary;
  final List<DesktopShellNativeContractItem> items;

  const DesktopShellNativeContractReport({
    this.schema = 'bridge.desktop.shell.native_contract.v1',
    required this.sourcePath,
    required this.summary,
    required this.items,
  });

  int get readyCount => items.where((item) => item.ready).length;

  int get blockedCount => items.where((item) => !item.ready).length;

  bool get canRunNativeBridgeContract => blockedCount == 0;

  Map<String, Object> toJson() {
    return {
      'schema': schema,
      'sourcePath': sourcePath,
      'summary': summary,
      'readyCount': readyCount,
      'blockedCount': blockedCount,
      'canRunNativeBridgeContract': canRunNativeBridgeContract,
      'items': [for (final item in items) item.toJson()],
    };
  }
}

class DesktopShellNativeContractReportService {
  const DesktopShellNativeContractReportService();

  DesktopShellNativeContractReport inspectSource(
    String source, {
    String sourcePath = 'macos/Runner/MainFlutterWindow.swift',
  }) {
    final items = <DesktopShellNativeContractItem>[
      _token(
        source,
        id: 'method-channel',
        label: 'MethodChannel 名稱',
        token: 'bridge.desktop_shell.macos.v1',
        detail: 'Swift Runner 必須註冊 Dart 端使用的桌面外殼 channel。',
      ),
      _token(
        source,
        id: 'flutter-method-channel',
        label: 'FlutterMethodChannel',
        token: 'FlutterMethodChannel',
        detail: '原生端必須建立 FlutterMethodChannel 接收 App 命令。',
      ),
      for (final method in _requiredMethods)
        _token(
          source,
          id: 'method-$method',
          label: 'method $method',
          token: 'case "$method"',
          detail: '原生端必須處理 $method 呼叫。',
        ),
      for (final field in _requiredSnapshotFields)
        _token(
          source,
          id: 'snapshot-$field',
          label: 'snapshot $field',
          token: '"$field"',
          detail: '原生 snapshot 必須回傳 $field 狀態。',
        ),
      for (final commandId in _requiredCommandIds)
        _token(
          source,
          id: 'command-$commandId',
          label: 'command $commandId',
          token: 'case "$commandId"',
          detail: '原生端必須映射 $commandId 桌面外殼命令。',
        ),
      _token(
        source,
        id: 'native-panel-controller',
        label: 'NSPanel controller',
        token: 'DesktopCompanionPanelController',
        detail: '桌面伴侶需要常駐面板 controller。',
      ),
      _token(
        source,
        id: 'native-panel',
        label: 'NSPanel',
        token: 'NSPanel',
        detail: '桌面伴侶需要 AppKit NSPanel 作為原生外殼。',
      ),
      _token(
        source,
        id: 'companion-panel-view',
        label: 'Companion panel view',
        token: 'DesktopCompanionPanelView',
        detail: '原生面板需要可顯示夥伴狀態的 view。',
      ),
    ];

    final blocked = items.where((item) => !item.ready).length;
    return DesktopShellNativeContractReport(
      sourcePath: sourcePath,
      summary: blocked == 0
          ? 'macOS Runner 原生橋接契約已對齊 Dart MethodChannel。'
          : 'macOS Runner 原生橋接契約缺少 $blocked 個必要項目。',
      items: items,
    );
  }

  DesktopShellNativeContractItem _token(
    String source, {
    required String id,
    required String label,
    required String token,
    required String detail,
  }) {
    final found = source.contains(token);
    return DesktopShellNativeContractItem(
      id: id,
      label: label,
      token: token,
      detail: found ? detail : '缺少必要片段：$token',
      status: found
          ? DesktopShellNativeContractStatus.ready
          : DesktopShellNativeContractStatus.blocked,
    );
  }
}

const _requiredMethods = [
  'inspect',
  'applyCommands',
  'lastResults',
  'snapshot',
  'syncRuntime',
  'lifecycle',
  'hardwareProfile',
];

const _requiredSnapshotFields = [
  'visible',
  'paused',
  'transparent',
  'frameless',
  'alwaysOnTop',
  'draggable',
  'trayEnabled',
  'launchAtLogin',
  'width',
  'height',
  'commandCount',
  'lastAction',
  'runtimeSynced',
  'companionName',
  'companionRole',
  'statusText',
];

const _requiredCommandIds = [
  'runtime.subscribe',
  'window.shape',
  'window.drag-anchor',
  'window.wander-loop',
  'window.always-on-top',
  'tray.install',
  'login-item.configure',
];
