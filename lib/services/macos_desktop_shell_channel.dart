import 'package:flutter/services.dart';

import 'desktop_companion_shell_commands.dart';
import 'local_model_catalog_service.dart';

class MacosDesktopShellConnection {
  final bool connected;
  final String platform;
  final String message;
  final int lastCommandCount;
  final bool nativePanelAvailable;

  const MacosDesktopShellConnection({
    required this.connected,
    required this.platform,
    required this.message,
    this.lastCommandCount = 0,
    this.nativePanelAvailable = false,
  });

  factory MacosDesktopShellConnection.fromJson(Map<dynamic, dynamic> json) {
    return MacosDesktopShellConnection(
      connected: json['connected'] == true,
      platform: json['platform'] is String
          ? json['platform'] as String
          : 'macos',
      message: json['message'] is String
          ? json['message'] as String
          : 'macOS desktop shell channel responded.',
      lastCommandCount: json['lastCommandCount'] is num
          ? (json['lastCommandCount'] as num).toInt()
          : 0,
      nativePanelAvailable: json['nativePanelAvailable'] == true,
    );
  }

  static const unavailable = MacosDesktopShellConnection(
    connected: false,
    platform: 'macos',
    message: 'macOS desktop shell MethodChannel 尚未連線。',
  );
}

class MacosDesktopShellSnapshot {
  final bool visible;
  final bool paused;
  final bool transparent;
  final bool frameless;
  final bool alwaysOnTop;
  final bool draggable;
  final bool trayEnabled;
  final bool launchAtLogin;
  final bool runtimeSynced;
  final double width;
  final double height;
  final int commandCount;
  final String lastAction;
  final String companionName;
  final String companionRole;
  final String statusText;

  const MacosDesktopShellSnapshot({
    this.visible = true,
    this.paused = false,
    this.transparent = true,
    this.frameless = true,
    this.alwaysOnTop = false,
    this.draggable = true,
    this.trayEnabled = false,
    this.launchAtLogin = false,
    this.runtimeSynced = false,
    this.width = 228,
    this.height = 286,
    this.commandCount = 0,
    this.lastAction = 'none',
    this.companionName = 'Bridge Companion',
    this.companionRole = '橋樑代理人',
    this.statusText = '自由待機',
  });

  factory MacosDesktopShellSnapshot.fromJson(Map<dynamic, dynamic> json) {
    return MacosDesktopShellSnapshot(
      visible: _readBool(json, 'visible', true),
      paused: _readBool(json, 'paused', false),
      transparent: _readBool(json, 'transparent', true),
      frameless: _readBool(json, 'frameless', true),
      alwaysOnTop: _readBool(json, 'alwaysOnTop', false),
      draggable: _readBool(json, 'draggable', true),
      trayEnabled: _readBool(json, 'trayEnabled', false),
      launchAtLogin: _readBool(json, 'launchAtLogin', false),
      runtimeSynced: _readBool(json, 'runtimeSynced', false),
      width: _readDouble(json, 'width', 228),
      height: _readDouble(json, 'height', 286),
      commandCount: json['commandCount'] is num
          ? (json['commandCount'] as num).toInt()
          : 0,
      lastAction: json['lastAction'] is String
          ? json['lastAction'] as String
          : 'none',
      companionName: _readString(json, 'companionName', 'Bridge Companion'),
      companionRole: _readString(json, 'companionRole', '橋樑代理人'),
      statusText: _readString(json, 'statusText', '自由待機'),
    );
  }

  static bool _readBool(Map<dynamic, dynamic> json, String key, bool fallback) {
    return json[key] is bool ? json[key] as bool : fallback;
  }

  static double _readDouble(
    Map<dynamic, dynamic> json,
    String key,
    double fallback,
  ) {
    final value = json[key];
    return value is num ? value.toDouble() : fallback;
  }

  static String _readString(
    Map<dynamic, dynamic> json,
    String key,
    String fallback,
  ) {
    return json[key] is String ? json[key] as String : fallback;
  }
}

class MacosDesktopShellChannel {
  static const String channelName = 'bridge.desktop_shell.macos.v1';
  static const MethodChannel _channel = MethodChannel(channelName);

  const MacosDesktopShellChannel();

  Future<MacosDesktopShellConnection> inspect() async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'inspect',
      );
      if (response == null) return MacosDesktopShellConnection.unavailable;
      return MacosDesktopShellConnection.fromJson(response);
    } on MissingPluginException {
      return MacosDesktopShellConnection.unavailable;
    } on PlatformException catch (error) {
      return MacosDesktopShellConnection(
        connected: false,
        platform: 'macos',
        message: error.message ?? 'macOS desktop shell channel failed.',
      );
    }
  }

  Future<List<Map<String, dynamic>>> apply(
    DesktopShellCommandQueue queue,
  ) async {
    try {
      final response = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'applyCommands',
        queue.toJson(),
      );
      return [
        for (final item in response ?? const <Map<dynamic, dynamic>>[])
          item.map((key, value) => MapEntry(key.toString(), value)),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> lastResults() async {
    try {
      final response = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
        'lastResults',
      );
      return [
        for (final item in response ?? const <Map<dynamic, dynamic>>[])
          item.map((key, value) => MapEntry(key.toString(), value)),
      ];
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  Future<MacosDesktopShellSnapshot?> snapshot() async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'snapshot',
      );
      if (response == null) return null;
      return MacosDesktopShellSnapshot.fromJson(response);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<MacosDesktopShellSnapshot?> syncRuntime(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'syncRuntime',
        payload,
      );
      if (response == null) return null;
      return MacosDesktopShellSnapshot.fromJson(response);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<MacosDesktopShellSnapshot?> lifecycle(String action) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'lifecycle',
        {'action': action},
      );
      if (response == null) return null;
      return MacosDesktopShellSnapshot.fromJson(response);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<LocalHardwareProfile?> hardwareProfile() async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'hardwareProfile',
      );
      if (response == null) return null;
      return LocalHardwareProfile.fromJson(response);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<Map<String, dynamic>?> localRuntime(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'localRuntime',
        payload,
      );
      return response;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
