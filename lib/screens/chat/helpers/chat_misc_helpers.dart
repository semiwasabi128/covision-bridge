// [教練 Agent Sprint 17 Step 7 2026-07-07]
// 雜項純函數 helpers — 從 chat_screen.dart 提取。
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/agent_activity.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/bridge_design_system.dart';
import '../../bridge_desktop_screen.dart';

String moodActionLabel(AgentActivitySnapshot snapshot) {
  return '${moodLabel(snapshot.mood)} / ${actionLabel(snapshot.action)}';
}

String moodLabel(AgentCompanionMood mood) {
  return switch (mood) {
    AgentCompanionMood.idle => '待機',
    AgentCompanionMood.curious => '好奇',
    AgentCompanionMood.focused => '專注',
    AgentCompanionMood.routing => '指路',
    AgentCompanionMood.waiting => '等待',
    AgentCompanionMood.proud => '得意',
    AgentCompanionMood.bridging => '橋接',
  };
}

String actionLabel(AgentCompanionAction action) {
  return switch (action) {
    AgentCompanionAction.standing => '站立',
    AgentCompanionAction.wandering => '漫遊',
    AgentCompanionAction.reading => '閱讀',
    AgentCompanionAction.pointing => '指向',
    AgentCompanionAction.bouncing => '跳動',
    AgentCompanionAction.spinning => '旋轉',
  };
}

String desktopCategorySummary(Map<String, dynamic> metadata) {
  final summary = metadata['categorySummary']?.toString().trim();
  if (summary != null && summary.isNotEmpty) return summary;
  final counts = metadata['categoryCounts'];
  if (counts is! Map || counts.isEmpty) return '尚無分類';
  final entries =
      counts.entries
          .map((entry) => MapEntry(entry.key.toString(), entry.value))
          .where((entry) => entry.value is num)
          .toList()
        ..sort(
          (a, b) =>
              (b.value as num).toInt().compareTo((a.value as num).toInt()),
        );
  return entries
      .take(4)
      .map((entry) => '${entry.key} ${(entry.value as num).toInt()}')
      .join('、');
}

String documentWorkflowActionKey(Map<String, dynamic> action) {
  final label = action['label']?.toString().trim();
  final prompt = action['prompt']?.toString().trim();
  return [
    if (label != null && label.isNotEmpty) label,
    if (prompt != null && prompt.isNotEmpty) prompt,
  ].join('|');
}

String dioErrorMessage(DioException e) {
  if (e.response != null) {
    return '伺服器回應 ${e.response?.statusCode}: ${e.response?.data?['error']?['message'] ?? e.message}';
  }
  return e.message ?? '未知錯誤';
}

String formatTime(DateTime dt) {
  // [教練 Agent 2026-07-23] 統一日期+時間格式，跟畫布聊天面板一致
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$mo/$d $h:$m';
}

// [Sprint 17 Step 9] SnackBar helpers — 從 chat_screen.dart 提取。

void showErrorSnackBar(BuildContext context, String message, {VoidCallback? onOpenSettings}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 86),
      duration: const Duration(seconds: 8),
      action: onOpenSettings != null
          ? SnackBarAction(
              label: '設定',
              textColor: BridgeDSColors.of(context).textPrimary,
              onPressed: onOpenSettings,
            )
          : null,
    ),
  );
}

void showSuccessSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 86),
      duration: const Duration(seconds: 4),
    ),
  );
}

void openSettingsFromError(BuildContext context) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    BridgeDesktopScreen.navigateTo('system');
  });
}

Future<String?> showRenameDialog(
  BuildContext context,
  TextEditingController controller,
) {
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('重新命名對話'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: '對話名稱'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('儲存'),
        ),
      ],
    ),
  );
}

Future<void> openLocalBridgePath(
  BuildContext context,
  String path, {
  required Future<void> Function(String) onCopyFallback,
}) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return;
  if (kIsWeb || trimmed.startsWith('data:')) {
    await onCopyFallback(trimmed);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('網頁預覽已複製檔案位置')));
    return;
  }

  final file = File(trimmed);
  final directory = Directory(trimmed);
  final target = file.existsSync() || directory.existsSync()
      ? trimmed
      : file.parent.path;
  try {
    final result = await Process.run('open', [target]);
    if (!context.mounted) return;
    if (result.exitCode == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已開啟：$target')));
    } else {
      await onCopyFallback(trimmed);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('開啟失敗，已改為複製路徑')));
    }
  } catch (_) {
    await onCopyFallback(trimmed);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('開啟失敗，已改為複製路徑')));
  }
}
