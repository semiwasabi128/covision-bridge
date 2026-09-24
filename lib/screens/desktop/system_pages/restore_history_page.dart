// RestoreHistoryPage — 還原歷史對話頁面
// [教練 Agent 2026-08-02]
//
// 功能：
// - 列出所有 conversations.json 備份
// - 可選任一備份還原（需確認）
// - 可清除歷史備份，保留最新（需二次確認）

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../models/conversation.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

class RestoreHistoryPage extends StatefulWidget {
  const RestoreHistoryPage({super.key});

  @override
  State<RestoreHistoryPage> createState() => _RestoreHistoryPageState();
}

class _RestoreHistoryPageState extends State<RestoreHistoryPage> {
  static const String _storageFolderName = 'bridge_state';
  static const String _storageFileName = 'conversations.json';

  List<_BackupEntry> _backups = [];
  bool _loading = true;
  String? _error;
  String? _selectedId; // 目前選中的備份

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<Directory> _storageDirectory() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory('${support.path}/$_storageFolderName');
    } catch (_) {
      return Directory('${Directory.systemTemp.path}/bridge_app/$_storageFolderName');
    }
  }

  Future<void> _loadBackups() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = await _storageDirectory();
      if (!await dir.exists()) {
        setState(() {
          _backups = [];
          _loading = false;
        });
        return;
      }

      final files = await dir.list().toList();
      final backupFiles = files
          .whereType<File>()
          .where((f) => f.path.contains('.${_storageFileName}.v'))
          .toList();

      final entries = <_BackupEntry>[];
      for (final file in backupFiles) {
        try {
          final stat = await file.stat();
          final content = await file.readAsString();
          final list = jsonDecode(content) as List;
          final conversations = list
              .take(5)
              .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
              .toList();
          entries.add(_BackupEntry(
            path: file.path,
            timestamp: stat.modified,
            conversationCount: list.length,
            preview: conversations
                .map((c) => '「${c.title}」(${c.messages.length}則)')
                .join(', '),
          ));
        } catch (_) {
          // 該備份無法解析，忽略
        }
      }

      // 按時間排序（新的在前面）
      entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      setState(() {
        _backups = entries;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _restoreBackup(_BackupEntry backup) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('還原對話'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('即將以此備份還原：'),
            SizedBox(height: BridgeDS.spaceSM),
            Container(
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatTime(backup.timestamp),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: BridgeDS.spaceSM),
                  Text(
                    '${backup.conversationCount} 個對話',
                    style: TextStyle(color: BridgeDS.grey600),
                  ),
                  SizedBox(height: BridgeDS.spaceSM),
                  Text(
                    backup.preview,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.grey600),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ 還原後會覆蓋目前的對話紀錄，確定嗎？',
              style: TextStyle(color: BridgeDS.orangeStd),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: BridgeDS.orangeStd,
              foregroundColor: BridgeDSColors.of(context).textPrimary,
            ),
            child: const Text('確認還原'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final currentFile = File(backup.path.replaceAll('.${_storageFileName}.v', ''));
      await File(backup.path).copy(currentFile.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已還原：${_formatTime(backup.timestamp)}，請重開 App'),
            backgroundColor: BridgeDS.green500,
          ),
        );
        await _loadBackups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('還原失敗：$e'),
            backgroundColor: BridgeDS.red500,
          ),
        );
      }
    }
  }

  Future<void> _clearOldBackups() async {
    if (_backups.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('備份不足，無需清除'),
          backgroundColor: BridgeDS.grey600,
        ),
      );
      return;
    }

    final newest = _backups.first;
    final olderOnes = _backups.skip(1).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除歷史備份'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('即將刪除以下備份（保留最新）：'),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                shrinkWrap: true,
                children: olderOnes.map((b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${_formatTime(b.timestamp)} — ${b.conversationCount}個對話',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle(),
                  ),
                )).toList(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '⚠️ 刪除後無法恢復，確定嗎？',
              style: TextStyle(color: BridgeDS.red500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: BridgeDS.red500,
              foregroundColor: BridgeDSColors.of(context).textPrimary,
            ),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      for (final backup in olderOnes) {
        await File(backup.path).delete();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已清除 ${olderOnes.length} 個舊備份'),
            backgroundColor: BridgeDS.green500,
          ),
        );
        await _loadBackups();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('清除失敗：$e'),
            backgroundColor: BridgeDS.red500,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} '
        '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 說明
        Container(
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: BridgeDS.blue700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '每次儲存對話前會自動備份，保留最近 10 個版本。選取任一版本可還原覆蓋目前對話。',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.blue700),
                ),
              ),
            ],
          ),
        ),

        // 清除按鈕
        if (_backups.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Row(
              children: [
                Text(
                  '${_backups.length} 個備份',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.grey600,
                    fontWeight: FontWeight.w500,),
                ),
                const Spacer(),
                if (_backups.length > 1)
                  TextButton.icon(
                    onPressed: _clearOldBackups,
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清除歷史備份（保留最新）'),
                    style: TextButton.styleFrom(
                      foregroundColor: BridgeDS.red400,
                    ),
                  ),
              ],
            ),
          ),

        // 列表
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('載入失敗：$_error'))
                  : _backups.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.backup_outlined,
                                  size: 48, color: BridgeDS.grey400),
                              const SizedBox(height: 12),
                              Text(
                                '尚無備份',
                                style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: BridgeDS.grey600),
                              ),
                              SizedBox(height: BridgeDS.spaceSM),
                              Text(
                                '開始聊天後會自動產生第一個備份',
                                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.grey400),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          itemCount: _backups.length,
                          itemBuilder: (ctx, i) {
                            final backup = _backups[i];
                            final isNewest = i == 0;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: isNewest
                                    ? BorderSide(
                                        color: Colors.green.withOpacity(0.5),
                                        width: 1.5)
                                    : BorderSide.none,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _restoreBackup(backup),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 圖示
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: isNewest
                                              ? Colors.green.withOpacity(0.1)
                                              : Colors.grey.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          isNewest
                                              ? Icons.star
                                              : Icons.history,
                                          color: isNewest
                                              ? BridgeDS.green500
                                              : BridgeDS.grey600,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // 內容
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  _formatTime(backup.timestamp),
                                                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,),
                                                ),
                                                if (isNewest) ...[
                                                  const SizedBox(width: BridgeDS.spaceSM),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                      horizontal: BridgeDS.spaceSM,
                                                      vertical: BridgeDS.spaceSM,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: BridgeDS.green500
                                                          .withOpacity(0.1),
                                                      borderRadius:
                                                          BorderRadius.circular(BridgeDS.roundSubtle),
                                                    ),
                                                    child: Text(
                                                      '最新',
                                                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.green500,
                                                        fontWeight:
                                                            FontWeight.w600,),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: BridgeDS.spaceSM),
                                            Text(
                                              '${backup.conversationCount} 個對話',
                                              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDS.grey600,),
                                            ),
                                            if (backup.preview.isNotEmpty) ...[
                                              const SizedBox(height: BridgeDS.spaceSM),
                                              Text(
                                                backup.preview,
                                                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: BridgeDSColors.of(context).textMuted,),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      // 還原按鈕
                                      TextButton(
                                        onPressed: () => _restoreBackup(backup),
                                        child: const Text('還原'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

class _BackupEntry {
  final String path;
  final DateTime timestamp;
  final int conversationCount;
  final String preview;

  _BackupEntry({
    required this.path,
    required this.timestamp,
    required this.conversationCount,
    required this.preview,
  });
}
