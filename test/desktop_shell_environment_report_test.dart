import 'package:bridge_app/services/desktop_shell_environment_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview report marks web preview ready and native checks pending', () {
    final report = const DesktopShellEnvironmentReportService().previewReport();

    expect(report.readyCount, 1);
    expect(report.pendingCount, 4);
    expect(report.blockedCount, 0);
    expect(report.canRunNativeConnectionTest, isFalse);
    expect(report.toJson()['schema'], 'bridge.desktop.shell.environment.v1');
    expect(
      report.items.map((item) => item.id),
      containsAll([
        'flutter-web-preview',
        'doctor-json',
        'full-xcode',
        'native-contract',
      ]),
    );
    expect(
      report.items.firstWhere((item) => item.id == 'doctor-json').command,
      'dart run tool/desktop_shell_doctor.dart --build',
    );
  });

  test('signal report blocks native test when full xcode is missing', () {
    final report = const DesktopShellEnvironmentReportService().fromSignals(
      flutterAvailable: true,
      fullXcodeAvailable: false,
      swiftParsePassed: true,
      macosBuildPassed: false,
      xcodeSelectPath: '/Library/Developer/CommandLineTools',
    );

    expect(report.readyCount, 3);
    expect(report.blockedCount, 1);
    expect(report.pendingCount, 1);
    expect(report.canRunNativeConnectionTest, isFalse);
    expect(report.summary, contains('尚未完成'));
    expect(
      report.items.firstWhere((item) => item.id == 'macos-build').detail,
      contains('尚未偵測到完整 Xcode/xcodebuild'),
    );
  });

  test('signal report is ready when all host checks pass', () {
    final report = const DesktopShellEnvironmentReportService().fromSignals(
      flutterAvailable: true,
      fullXcodeAvailable: true,
      swiftParsePassed: true,
      macosBuildPassed: true,
      xcodeSelectPath: '/Applications/Xcode.app/Contents/Developer',
    );

    expect(report.readyCount, 5);
    expect(report.pendingCount, 0);
    expect(report.blockedCount, 0);
    expect(report.canRunNativeConnectionTest, isTrue);
  });

  test('parses doctor json back into environment report', () {
    final report = const DesktopShellEnvironmentReportService().parseDoctorJson(
      '''
{
  "schema": "bridge.desktop.shell.environment.v1",
  "summary": "桌面端測試環境尚未完成，需先補齊阻擋項。",
  "items": [
    {
      "id": "flutter",
      "label": "Flutter CLI",
      "detail": "Flutter CLI 可用。",
      "status": "ready",
      "command": "flutter --version"
    },
    {
      "id": "full-xcode",
      "label": "完整 Xcode",
      "detail": "目前未偵測到完整 Xcode/xcodebuild。",
      "status": "blocked"
    }
  ]
}
''',
    );

    expect(report.readyCount, 1);
    expect(report.blockedCount, 1);
    expect(report.items.first.command, 'flutter --version');
  });

  test('parses doctor json from mixed terminal output', () {
    final report = const DesktopShellEnvironmentReportService().parseDoctorJson(
      '''
Running build hooks...
{"schema":"bridge.desktop.shell.environment.v1","summary":"ok","items":[{"id":"flutter","label":"Flutter CLI","detail":"ready","status":"ready"}]}
Done.
''',
    );

    expect(report.summary, 'ok');
    expect(report.readyCount, 1);
  });

  test('rejects non-environment doctor json', () {
    expect(
      () => const DesktopShellEnvironmentReportService().parseDoctorJson(
        '{"schema":"wrong"}',
      ),
      throwsFormatException,
    );
  });
}
