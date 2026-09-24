import 'desktop_companion_shell_config.dart';

enum DesktopShellCommandStatus { applied, simulated, requiresNative }

class DesktopShellCommand {
  final String id;
  final String label;
  final String detail;
  final bool requiresNative;
  final Map<String, Object?> payload;

  const DesktopShellCommand({
    required this.id,
    required this.label,
    required this.detail,
    required this.requiresNative,
    this.payload = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'detail': detail,
    'requiresNative': requiresNative,
    'payload': payload,
  };
}

class DesktopShellCommandResult {
  final DesktopShellCommand command;
  final DesktopShellCommandStatus status;
  final String message;

  const DesktopShellCommandResult({
    required this.command,
    required this.status,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'command': command.toJson(),
    'status': status.name,
    'message': message,
  };
}

class DesktopShellCommandQueue {
  final List<DesktopShellCommand> commands;

  const DesktopShellCommandQueue(this.commands);

  int get nativeRequiredCount =>
      commands.where((item) => item.requiresNative).length;

  Map<String, dynamic> toJson() => {
    'commands': commands.map((item) => item.toJson()).toList(),
    'summary': {
      'commands': commands.length,
      'nativeRequired': nativeRequiredCount,
    },
  };
}

class DesktopShellCommandService {
  const DesktopShellCommandService();

  DesktopShellCommandQueue buildQueue(DesktopCompanionShellPlan plan) {
    final config = plan.config;
    return DesktopShellCommandQueue([
      DesktopShellCommand(
        id: 'runtime.subscribe',
        label: '訂閱 Runtime',
        detail: '讀取 ${config.runtimeChannel}，接收夥伴狀態、表情與工作進度。',
        requiresNative: false,
        payload: {'channel': config.runtimeChannel},
      ),
      DesktopShellCommand(
        id: 'window.shape',
        label: '建立透明小窗',
        detail: '套用透明、無邊框與固定尺寸，讓夥伴像桌面生物一樣存在。',
        requiresNative: false,
        payload: {
          'transparent': config.transparent,
          'frameless': config.frameless,
          'width': config.width,
          'height': config.height,
        },
      ),
      DesktopShellCommand(
        id: 'window.drag-anchor',
        label: '註冊拖曳停靠',
        detail: '把拖曳座標寫回本機偏好，下一次啟動能回到同一個位置。',
        requiresNative: false,
        payload: {'draggable': config.draggable},
      ),
      const DesktopShellCommand(
        id: 'window.wander-loop',
        label: '啟動漫遊迴圈',
        detail: '根據 runtime action 與 tick 產生走動、停靠、呼吸光與工作表情。',
        requiresNative: false,
      ),
      DesktopShellCommand(
        id: 'window.always-on-top',
        label: '申請置頂視窗',
        detail: '需要原生外殼把小窗保持在桌面上層。',
        requiresNative: config.alwaysOnTop,
        payload: {'alwaysOnTop': config.alwaysOnTop},
      ),
      DesktopShellCommand(
        id: 'tray.install',
        label: '建立托盤選單',
        detail: '提供顯示、隱藏、暫停工作、切換夥伴與退出。',
        requiresNative: config.trayEnabled,
        payload: {'enabled': config.trayEnabled},
      ),
      DesktopShellCommand(
        id: 'login-item.configure',
        label: '設定開機啟動',
        detail: '依使用者選擇向作業系統申請登入後自動啟動。',
        requiresNative: config.launchAtLogin,
        payload: {'launchAtLogin': config.launchAtLogin},
      ),
    ]);
  }
}

class DesktopShellMockCommandAdapter {
  const DesktopShellMockCommandAdapter();

  List<DesktopShellCommandResult> dryRun(DesktopShellCommandQueue queue) {
    return [
      for (final command in queue.commands)
        DesktopShellCommandResult(
          command: command,
          status: command.requiresNative
              ? DesktopShellCommandStatus.requiresNative
              : _simulatedStatus(command),
          message: command.requiresNative
              ? '等待 native plugin 接管'
              : _messageFor(command),
        ),
    ];
  }

  DesktopShellCommandStatus _simulatedStatus(DesktopShellCommand command) {
    if (command.id == 'runtime.subscribe') {
      return DesktopShellCommandStatus.applied;
    }
    return DesktopShellCommandStatus.simulated;
  }

  String _messageFor(DesktopShellCommand command) {
    if (command.id == 'runtime.subscribe') {
      return 'Flutter 內已可讀取';
    }
    return 'Flutter 預覽模式模擬中';
  }
}
