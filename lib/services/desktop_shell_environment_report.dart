import 'dart:convert';

import 'bridge_json_extractor.dart';
import 'desktop_shell_native_contract_report.dart';

enum DesktopShellEnvironmentStatus { ready, pending, blocked }

DesktopShellEnvironmentStatus _environmentStatusFromName(String? name) {
  return DesktopShellEnvironmentStatus.values.firstWhere(
    (status) => status.name == name,
    orElse: () => DesktopShellEnvironmentStatus.pending,
  );
}

class DesktopShellEnvironmentItem {
  final String id;
  final String label;
  final String detail;
  final DesktopShellEnvironmentStatus status;
  final String command;

  const DesktopShellEnvironmentItem({
    required this.id,
    required this.label,
    required this.detail,
    required this.status,
    this.command = '',
  });

  Map<String, Object> toJson() {
    return {
      'id': id,
      'label': label,
      'detail': detail,
      'status': status.name,
      if (command.isNotEmpty) 'command': command,
    };
  }

  factory DesktopShellEnvironmentItem.fromJson(Map<String, dynamic> json) {
    return DesktopShellEnvironmentItem(
      id: json['id'] is String ? json['id'] as String : 'unknown',
      label: json['label'] is String ? json['label'] as String : 'Unknown',
      detail: json['detail'] is String ? json['detail'] as String : '',
      status: _environmentStatusFromName(json['status'] as String?),
      command: json['command'] is String ? json['command'] as String : '',
    );
  }
}

class DesktopShellEnvironmentReport {
  final List<DesktopShellEnvironmentItem> items;
  final String summary;

  const DesktopShellEnvironmentReport({
    required this.items,
    required this.summary,
  });

  int get readyCount => items
      .where((item) => item.status == DesktopShellEnvironmentStatus.ready)
      .length;

  int get pendingCount => items
      .where((item) => item.status == DesktopShellEnvironmentStatus.pending)
      .length;

  int get blockedCount => items
      .where((item) => item.status == DesktopShellEnvironmentStatus.blocked)
      .length;

  bool get canRunNativeConnectionTest => blockedCount == 0 && pendingCount == 0;

  Map<String, Object> toJson() {
    return {
      'schema': 'bridge.desktop.shell.environment.v1',
      'summary': summary,
      'readyCount': readyCount,
      'pendingCount': pendingCount,
      'blockedCount': blockedCount,
      'canRunNativeConnectionTest': canRunNativeConnectionTest,
      'items': [for (final item in items) item.toJson()],
    };
  }

  factory DesktopShellEnvironmentReport.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return DesktopShellEnvironmentReport(
      summary: json['summary'] is String
          ? json['summary'] as String
          : '已匯入桌面端測試環境報告。',
      items: rawItems is List
          ? [
              for (final raw in rawItems)
                if (raw is Map)
                  DesktopShellEnvironmentItem.fromJson(
                    raw.map((key, value) => MapEntry(key.toString(), value)),
                  ),
            ]
          : const [],
    );
  }
}

class DesktopShellEnvironmentReportService {
  const DesktopShellEnvironmentReportService();

  DesktopShellEnvironmentReport parseDoctorJson(String rawJson) {
    final decoded = jsonDecode(extractFirstJsonObject(rawJson));
    if (decoded is! Map) {
      throw const FormatException('Doctor JSON 必須是物件。');
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (json['schema'] != 'bridge.desktop.shell.environment.v1') {
      throw const FormatException('不是 bridge desktop shell environment 報告。');
    }
    return DesktopShellEnvironmentReport.fromJson(json);
  }

  DesktopShellEnvironmentReport previewReport() {
    return const DesktopShellEnvironmentReport(
      summary: 'Web 預覽可測 App 端流程；真正 macOS 連線需要本機 doctor 報告確認。',
      items: [
        DesktopShellEnvironmentItem(
          id: 'flutter-web-preview',
          label: 'Flutter Web 預覽',
          detail: '可測 UI、runtime payload、煙霧測試流程與測試封包。',
          status: DesktopShellEnvironmentStatus.ready,
        ),
        DesktopShellEnvironmentItem(
          id: 'doctor-json',
          label: '桌面端 doctor JSON',
          detail:
              '執行 tool/desktop_shell_doctor.dart 後，可取得 Xcode 與 macOS build 狀態。',
          status: DesktopShellEnvironmentStatus.pending,
          command: 'dart run tool/desktop_shell_doctor.dart --build',
        ),
        DesktopShellEnvironmentItem(
          id: 'full-xcode',
          label: '完整 Xcode',
          detail: '需要完整 Xcode 與 xcodebuild，才能編譯 macOS Runner 並啟動 AppKit 面板。',
          status: DesktopShellEnvironmentStatus.pending,
          command: 'xcode-select -p && xcrun -find xcodebuild',
        ),
        DesktopShellEnvironmentItem(
          id: 'native-contract',
          label: '原生橋接契約',
          detail:
              'doctor 會檢查 macOS Runner 是否包含 MethodChannel、methods、snapshot 與 NSPanel 契約。',
          status: DesktopShellEnvironmentStatus.pending,
          command: 'dart run tool/desktop_shell_native_contract.dart',
        ),
        DesktopShellEnvironmentItem(
          id: 'macos-runner',
          label: 'macOS Runner',
          detail:
              '需要 flutter build macos --debug 成功後，才能做真正 MethodChannel 連線測試。',
          status: DesktopShellEnvironmentStatus.pending,
          command: 'flutter build macos --debug',
        ),
      ],
    );
  }

  DesktopShellEnvironmentReport fromSignals({
    required bool flutterAvailable,
    required bool fullXcodeAvailable,
    required bool swiftParsePassed,
    required bool macosBuildPassed,
    bool nativeContractPassed = true,
    DesktopShellNativeContractReport? nativeContractReport,
    String xcodeSelectPath = '',
    String macosBuildMessage = '',
  }) {
    final items = [
      DesktopShellEnvironmentItem(
        id: 'flutter',
        label: 'Flutter CLI',
        detail: flutterAvailable ? 'Flutter CLI 可用。' : '找不到 Flutter CLI。',
        status: flutterAvailable
            ? DesktopShellEnvironmentStatus.ready
            : DesktopShellEnvironmentStatus.blocked,
        command: 'flutter --version',
      ),
      DesktopShellEnvironmentItem(
        id: 'full-xcode',
        label: '完整 Xcode',
        detail: fullXcodeAvailable
            ? 'xcodebuild 可用：$xcodeSelectPath'
            : '目前未偵測到完整 Xcode/xcodebuild。',
        status: fullXcodeAvailable
            ? DesktopShellEnvironmentStatus.ready
            : DesktopShellEnvironmentStatus.blocked,
        command: 'xcode-select -p && xcrun -find xcodebuild',
      ),
      DesktopShellEnvironmentItem(
        id: 'swift-parse',
        label: 'Swift 語法檢查',
        detail: swiftParsePassed
            ? 'MainFlutterWindow.swift 語法可解析。'
            : 'Swift 語法解析尚未通過。',
        status: swiftParsePassed
            ? DesktopShellEnvironmentStatus.ready
            : DesktopShellEnvironmentStatus.blocked,
        command: 'swiftc -parse macos/Runner/MainFlutterWindow.swift',
      ),
      DesktopShellEnvironmentItem(
        id: 'native-contract',
        label: '原生橋接契約',
        detail:
            nativeContractReport?.summary ??
            (nativeContractPassed
                ? 'macOS Runner 原生橋接契約已對齊 Dart MethodChannel。'
                : 'macOS Runner 原生橋接契約尚未通過靜態檢查。'),
        status: nativeContractPassed
            ? DesktopShellEnvironmentStatus.ready
            : DesktopShellEnvironmentStatus.blocked,
        command: 'dart run tool/desktop_shell_native_contract.dart',
      ),
      DesktopShellEnvironmentItem(
        id: 'macos-build',
        label: 'macOS Runner build',
        detail: _macosBuildDetail(
          fullXcodeAvailable: fullXcodeAvailable,
          macosBuildPassed: macosBuildPassed,
          macosBuildMessage: macosBuildMessage,
        ),
        status: macosBuildPassed
            ? DesktopShellEnvironmentStatus.ready
            : DesktopShellEnvironmentStatus.pending,
        command: 'flutter build macos --debug',
      ),
    ];

    final hasBlocked = items.any(
      (item) => item.status == DesktopShellEnvironmentStatus.blocked,
    );
    final hasPending = items.any(
      (item) => item.status == DesktopShellEnvironmentStatus.pending,
    );
    return DesktopShellEnvironmentReport(
      items: items,
      summary: hasBlocked
          ? '桌面端測試環境尚未完成，需先補齊阻擋項。'
          : hasPending
          ? '桌面端環境接近可測，剩下 macOS build 驗證。'
          : '桌面端環境已可執行完整原生連線測試。',
    );
  }
}

String _macosBuildDetail({
  required bool fullXcodeAvailable,
  required bool macosBuildPassed,
  required String macosBuildMessage,
}) {
  if (macosBuildPassed) return 'macOS debug build 已通過。';
  if (!fullXcodeAvailable) {
    return '尚未偵測到完整 Xcode/xcodebuild；安裝完整 Xcode 或切換 xcode-select 後再執行 macOS build。';
  }
  if (macosBuildMessage.isEmpty) return 'macOS debug build 尚未通過。';
  return macosBuildMessage;
}
