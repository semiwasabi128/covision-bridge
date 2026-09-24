// [S17 收尾] 第二大腦資料夾匯入 handler。
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../models/second_brain_file_index.dart';
import '../../../models/second_brain_trace.dart';
import '../../../models/transurfing_brain.dart';
import '../../../services/memory_store.dart';
import '../../../services/second_brain_folder_import_service.dart';
import '../../../services/second_brain_trace_service.dart';

class SecondBrainImportConfig {
  final SecondBrainFolderImportService importService;
  final SecondBrainTraceService traceService;
  final bool Function() mounted;
  final BuildContext Function() context;
  final void Function(void Function()) setState;
  final BrainReflection? Function() getBrainReflection;
  final List<String> Function() getRecalledInsights;
  final String? Function() getActiveCompanionName;
  final String? Function() getLastBridgeActionLabel;
  final void Function(
    SecondBrainTrace trace,
    Map<String, SecondBrainAssociationFeedback> feedbacks,
  ) onTraceUpdated;

  const SecondBrainImportConfig({
    required this.importService,
    required this.traceService,
    required this.mounted,
    required this.context,
    required this.setState,
    required this.getBrainReflection,
    required this.getRecalledInsights,
    required this.getActiveCompanionName,
    required this.getLastBridgeActionLabel,
    required this.onTraceUpdated,
  });
}

/// 從 chat_screen.dart 抽出。負責第二大腦資料夾匯入 + trace 重建 + SnackBar。
class SecondBrainImportHandler {
  final SecondBrainImportConfig _c;
  SecondBrainImportHandler(this._c);

  Future<void> importFolder() async {
    if (kIsWeb) {
      _snack('開發預覽環境暫不支援資料夾索引匯入，請在桌面 APP 使用。');
      return;
    }
    try {
      final folderPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '選擇要匯入第二大腦的資料夾',
      );
      if (folderPath == null || folderPath.trim().isEmpty) return;

      final result = await _c.importService.importFolder(
        folderPath,
        room: SecondBrainRoom.files,
      );

      final reflection = _c.getBrainReflection();
      if (reflection != null) {
        final refreshedTrace = await _c.traceService.build(
          reflection: reflection,
          recalledInsights: _c.getRecalledInsights(),
          newInsights: const [],
          activeCompanionName: _c.getActiveCompanionName(),
          activeBridgeActionLabel: _c.getLastBridgeActionLabel(),
        );
        final feedbacks =
            await MemoryStore.getSecondBrainAssociationFeedbacks(
          refreshedTrace.associations,
        );
        if (_c.mounted()) {
          _c.setState(() {});
          _c.onTraceUpdated(refreshedTrace, feedbacks);
        }
      }

      if (!_c.mounted()) return;
      _snack(
        result.indexedCount == 0
            ? '沒有找到可索引的檔案。'
            : '已匯入 ${result.indexedCount} 個檔案，其中 ${result.digestedCount} 個已讀取內容摘要。',
      );
    } catch (e) {
      _snack('匯入第二大腦資料夾失敗: $e');
    }
  }

  void _snack(String msg) {
    if (!_c.mounted()) return;
    ScaffoldMessenger.of(_c.context()).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }
}
