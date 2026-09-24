import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/brain_container/brain_database.dart';
import '../../services/onboarding/onboarding_flow.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

/// 大腦資料庫位置設定卡片——從 settings_screen.dart 抽出
/// 讓使用者選擇大腦 DB 的存放位置，更改後需重啟 App
class DbLocationCard extends StatefulWidget {
  const DbLocationCard({super.key});

  @override
  State<DbLocationCard> createState() => _DbLocationCardState();
}

class _DbLocationCardState extends State<DbLocationCard> {
  String _dbPath = '';
  bool _dbPathValid = false;
  bool _isCheckingDbPath = false;
  bool _isChangingDbPath = false;
  bool _dbFileExists = false;

  @override
  void initState() {
    super.initState();
    _loadDbPath();
  }

  Future<void> _loadDbPath() async {
    final dbPath = await BrainDatabase.getCustomDbDirectory() ??
        OnboardingManager.defaultDbPath;
    final dbPathValid = await OnboardingManager.isPathAccessible(dbPath);
    final dbExists = await _checkDbFileExists(dbPath);
    if (!mounted) return;
    setState(() {
      _dbPath = dbPath;
      _dbPathValid = dbPathValid;
      _dbFileExists = dbExists;
    });
  }

  Future<bool> _checkDbFileExists(String path) async {
    try {
      final file = File('$path/brain_container.db');
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _pickDbDirectory() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇資料庫存放位置',
      initialDirectory: _dbPath,
    );

    if (result == null) return;

    setState(() => _isCheckingDbPath = true);

    final accessible = await OnboardingManager.isPathAccessible(result);

    if (!accessible) {
      setState(() {
        _dbPath = result;
        _dbPathValid = false;
        _isCheckingDbPath = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('此路徑無法存取或寫入，請選擇其他位置'),
            backgroundColor: BridgeDSColors.of(context).accentRed,
          ),
        );
      }
      return;
    }

    setState(() {
      _isChangingDbPath = true;
      _isCheckingDbPath = false;
    });

    await BrainDatabase.setCustomDbDirectory(result);
    final dbExists = await _checkDbFileExists(result);

    setState(() {
      _dbPath = result;
      _dbPathValid = true;
      _dbFileExists = dbExists;
      _isChangingDbPath = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('資料庫位置已更新為：$result\n請重啟 App 生效'),
          backgroundColor: BridgeDSColors.of(context).accentGreen,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ds.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題
          Row(
            children: [
              Icon(Icons.storage, size: 24, color: ds.accentPurple),
              const SizedBox(width: 12),
              Text(
                '大腦資料庫位置',
                style: TierStyle.of(context, Tier.blockHeading)
                    .toTextStyle()
                    .copyWith(
                      fontWeight: FontWeight.bold,
                      color: ds.textPrimary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '你的第二大腦資料庫（記憶、知識、人格卡）存放在這裡。更改位置後需要重啟 App。',
            style: TierStyle.of(context, Tier.cardBody)
                .toTextStyle()
                .copyWith(color: ds.textSecondary),
          ),
          const SizedBox(height: 20),

          // 目前路徑
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ds.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _dbPathValid
                    ? ds.accentGreen.withValues(alpha: 0.3)
                    : ds.accentRed.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '目前位置',
                  style: TierStyle.of(context, Tier.cardBody)
                      .toTextStyle()
                      .copyWith(color: ds.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _dbPath,
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(color: ds.textPrimary),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_open, size: 20),
                      tooltip: '選擇資料夾',
                      onPressed:
                          _isChangingDbPath ? null : _pickDbDirectory,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isCheckingDbPath)
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('檢查路徑中...',
                          style: TierStyle.of(context, Tier.cardBody)
                              .toTextStyle()),
                    ],
                  )
                else if (_dbPathValid)
                  Row(
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: ds.accentGreen),
                      const SizedBox(width: 6),
                      Text(
                        _dbFileExists
                            ? '路徑可用，DB 檔案已存在'
                            : '路徑可用，可正常讀寫',
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(color: ds.accentGreen),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 16, color: ds.accentRed),
                      const SizedBox(width: 6),
                      Text(
                        '路徑不可用',
                        style: TierStyle.of(context, Tier.cardBody)
                            .toTextStyle()
                            .copyWith(color: ds.accentRed),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 更改按鈕
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isChangingDbPath ? null : _pickDbDirectory,
              icon: _isChangingDbPath
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.drive_file_move_outline, size: 18),
              label: Text(_isChangingDbPath ? '處理中...' : '更改資料庫位置'),
            ),
          ),
        ],
      ),
    );
  }
}
