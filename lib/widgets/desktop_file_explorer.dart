import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/bridge_adapters/local_desktop_files_adapter.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import 'bridge_desktop_widgets.dart';

/// 桌面檔案總管 — 選資料夾 → 掃描 → 分類統計 + 檔案清單 + 一鍵整理
class DesktopFileExplorer extends StatefulWidget {
  const DesktopFileExplorer({super.key});

  @override
  State<DesktopFileExplorer> createState() => _DesktopFileExplorerState();
}

class _DesktopFileExplorerState extends State<DesktopFileExplorer> {
  final _adapter = LocalDesktopFilesAdapter();

  bool _scanning = false;
  String? _selectedPath;
  DesktopFolderScanResult? _scanResult;
  DesktopOrganizePlan? _plan;
  String? _error;

  bool _organizing = false;
  String? _organizeResult;

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '選擇要掃描的資料夾',
    );
    if (path == null) return;
    await _scan(path);
  }

  Future<void> _scan(String path) async {
    setState(() {
      _scanning = true;
      _error = null;
      _selectedPath = path;
      _scanResult = null;
      _plan = null;
      _organizeResult = null;
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        setState(() {
          _scanning = false;
          _error = '資料夾不存在：$path';
        });
        return;
      }
      final result = await _adapter.scan(dir);
      final plan = _adapter.buildPlan(result);
      setState(() {
        _scanning = false;
        _scanResult = result;
        _plan = plan;
      });
    } catch (e) {
      setState(() {
        _scanning = false;
        _error = '掃描失敗：$e';
      });
    }
  }

  Future<void> _applyOrganize() async {
    if (_plan == null || _selectedPath == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BridgeDSColors.of(context).surface,
        title: Text('確認整理', style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle()),
        content: Text(
          '將建立 ${_plan!.foldersToCreate.length} 個分類資料夾，'
          '移動 ${_plan!.moves.length} 個檔案。\n'
          '未分類的 ${_plan!.skipped.length} 個檔案會留在原處。\n\n'
          '確定要執行嗎？',
          style: BridgeDSColors.of(context).body.copyWith(color: BridgeDSColors.of(context).textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: BridgeDSColors.of(context).body.copyWith(
              color: BridgeDSColors.of(context).textTertiary,
            )),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: BridgeDSColors.of(context).accentBlue),
            child: const Text('執行整理'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _organizing = true;
      _organizeResult = null;
    });

    try {
      var createdFolders = 0;
      for (final folder in _plan!.foldersToCreate) {
        final target = Directory(folder);
        if (!await target.exists()) {
          await target.create(recursive: true);
          createdFolders++;
        }
      }

      var moved = 0;
      var failed = 0;
      for (final move in _plan!.moves) {
        final source = File(move.sourcePath);
        if (!await source.exists()) {
          failed++;
          continue;
        }
        try {
          final targetPath = await _uniquePath(move.targetPath);
          await source.rename(targetPath);
          moved++;
        } catch (_) {
          failed++;
        }
      }

      setState(() {
        _organizing = false;
        _organizeResult = '整理完成：建立 $createdFolders 個資料夾，'
            '移動 $moved 個檔案'
            '${failed > 0 ? '，$failed 個失敗' : ''}';
      });

      // 重新掃描顯示結果
      await _scan(_selectedPath!);
    } catch (e) {
      setState(() {
        _organizing = false;
        _organizeResult = '整理失敗：$e';
      });
    }
  }

  Future<String> _uniquePath(String targetPath) async {
    final file = File(targetPath);
    if (!await file.exists()) return targetPath;
    final sep = Platform.pathSeparator;
    final parent = targetPath.contains(sep)
        ? targetPath.substring(0, targetPath.lastIndexOf(sep))
        : '.';
    final name = targetPath.contains(sep)
        ? targetPath.substring(targetPath.lastIndexOf(sep) + 1)
        : targetPath;
    final dotIndex = name.lastIndexOf('.');
    final stem = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final ext = dotIndex > 0 ? name.substring(dotIndex) : '';
    for (var i = 1; i < 100; i++) {
      final candidate = '$parent$sep$stem ($i)$ext';
      if (!await File(candidate).exists()) return candidate;
    }
    return '$parent$sep$stem (copy)$ext';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 工具列
        Row(
          children: [
            BridgePillButton(
              label: _selectedPath == null ? '選擇資料夾' : '重新選擇',
              icon: Icons.folder_open,
              type: BridgeButtonType.accent,
              onPressed: _scanning || _organizing ? null : _pickFolder,
            ),
            SizedBox(width: 12),
            if (_scanResult != null && _plan != null && _plan!.moves.isNotEmpty)
              BridgePillButton(
                label: _organizing ? '整理中…' : '一鍵整理',
                icon: Icons.auto_fix_high,
                type: BridgeButtonType.accent,
                onPressed: _organizing ? null : _applyOrganize,
              ),
            Spacer(),
            if (_selectedPath != null)
              Expanded(
                child: Text(
                  _selectedPath!,
                  style: BridgeDSColors.of(context).labelMono.copyWith(
                    fontSize: 14,
                    color: BridgeDSColors.of(context).textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
          ],
        ),

        SizedBox(height: BridgeDS.spaceMD),

        // 錯誤訊息
        if (_error != null)
          BridgeCard(
            child: Padding(
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      color: BridgeDSColors.of(context).accentRed, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                      style: BridgeDSColors.of(context).caption.copyWith(
                        fontSize: 14,
                        color: BridgeDSColors.of(context).accentRed,
                      )),
                  ),
                ],
              ),
            ),
          ),

        // 掃描中
        if (_scanning)
          Padding(
            padding: EdgeInsets.all(BridgeDS.spaceXXL),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    color: BridgeDSColors.of(context).accentBlue,
                    strokeWidth: 2,
                  ),
                  SizedBox(height: 16),
                  Text('掃描中…',
                    style: TextStyle(color: BridgeDSColors.of(context).textMuted)),
                ],
              ),
            ),
          ),

        // 整理結果
        if (_organizeResult != null) ...[
          BridgeCard(
            child: Padding(
              padding: const EdgeInsets.all(BridgeDS.spaceMD),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: BridgeDSColors.of(context).accentGreen, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(_organizeResult!,
                      style: BridgeDSColors.of(context).caption.copyWith(
                        fontSize: 14,
                        color: BridgeDSColors.of(context).accentGreen,
                      )),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: BridgeDS.spaceMD),
        ],

        // 掃描結果
        if (_scanResult != null && !_scanning) ..._buildScanResults(),

        // 空狀態
        if (_scanResult == null && !_scanning && _error == null)
          BridgeCard(
            child: Padding(
              padding: const EdgeInsets.all(BridgeDS.spaceXXL),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open,
                        color: BridgeDSColors.of(context).textQuaternary, size: 48),
                    SizedBox(height: 16),
                    Text('檔案總管',
                      style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(fontSize: 24)),
                    SizedBox(height: 8),
                    Text(
                      '選擇一個資料夾開始掃描\n掃描為只讀操作，不會移動任何檔案',
                      textAlign: TextAlign.center,
                      style: BridgeDSColors.of(context).caption.copyWith(
                        fontSize: 14,
                        color: BridgeDSColors.of(context).textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildScanResults() {
    final scan = _scanResult!;
    final plan = _plan!;

    return [
      // 統計卡片
      BridgeCard(
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.analytics_outlined,
                      color: BridgeDSColors.of(context).accentBlue, size: 16),
                  SizedBox(width: 8),
                  Text('掃描結果', style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(fontSize: 18)),
                ],
              ),
              SizedBox(height: BridgeDS.spaceMD),
              _statRow('檔案數', '${scan.fileCount}'),
              _statRow('資料夾數', '${scan.folderCount}'),
              if (scan.truncated)
                _statRow('截斷', '超過 200 個檔案，僅掃描前 200 個',
                    color: BridgeDSColors.of(context).accentYellow),
              const SizedBox(height: BridgeDS.spaceMD),
              // 分類統計
              if (scan.categoryCounts.isNotEmpty) ...[
                Text('分類統計',
                  style: BridgeDSColors.of(context).labelMono.copyWith(fontSize: 14)),
                const SizedBox(height: BridgeDS.spaceSM),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (scan.categoryCounts.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map((e) => _categoryChip(e.key, e.value))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),

      if (plan.moves.isNotEmpty) ...[
        SizedBox(height: BridgeDS.spaceMD),
        // 整理計畫預覽
        BridgeCard(
          child: Padding(
            padding: const EdgeInsets.all(BridgeDS.spaceMD),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sort,
                        color: BridgeDSColors.of(context).accentPurple, size: 16),
                    SizedBox(width: 8),
                    Text('整理計畫',
                      style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(fontSize: 18)),
                    Spacer(),
                    BridgeStatusTag(
                      label: '${plan.moves.length} 移動 · '
                          '${plan.foldersToCreate.length} 資料夾',
                      type: BridgeTagType.info,
                    ),
                  ],
                ),
                SizedBox(height: BridgeDS.spaceMD),
                // 計畫資料夾清單
                ...plan.foldersToCreate.map((folder) {
                  final name = folder.split(Platform.pathSeparator).last;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(Icons.create_new_folder_outlined,
                          size: 14, color: BridgeDSColors.of(context).accentYellow),
                        SizedBox(width: 8),
                        Text(name, style: BridgeDSColors.of(context).caption.copyWith(
                          fontSize: 14,
                          color: BridgeDSColors.of(context).textSecondary,
                        )),
                      ],
                    ),
                  );
                }),
                if (plan.skipped.isNotEmpty) ...[
                  SizedBox(height: BridgeDS.spaceSM),
                  Text('${plan.skipped.length} 個未分類檔案將留在原處',
                    style: BridgeDSColors.of(context).caption.copyWith(
                      fontSize: 14,
                      color: BridgeDSColors.of(context).textMuted,
                    )),
                ],
              ],
            ),
          ),
        ),
      ],

      SizedBox(height: BridgeDS.spaceMD),

      // 檔案清單
      BridgeCard(
        child: Padding(
          padding: const EdgeInsets.all(BridgeDS.spaceMD),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.list_alt,
                      color: BridgeDSColors.of(context).accentGreen, size: 16),
                  SizedBox(width: 8),
                  Text('檔案清單',
                    style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(fontSize: 18)),
                  Spacer(),
                  Text('${scan.samples.length} 個',
                    style: BridgeDSColors.of(context).labelMono.copyWith(
                      fontSize: 14,
                      color: BridgeDSColors.of(context).textMuted,
                    )),
                ],
              ),
              SizedBox(height: BridgeDS.spaceMD),
              // 檔案列表
              ...scan.samples.map((file) => _fileTile(file)),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _statRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(label, style: BridgeDSColors.of(context).caption.copyWith(
            fontSize: 14,
            color: BridgeDSColors.of(context).textTertiary,
          )),
          SizedBox(width: 12),
          Text(value, style: BridgeDSColors.of(context).caption.copyWith(
            fontSize: 14,
            color: color ?? BridgeDSColors.of(context).textPrimary,
          )),
        ],
      ),
    );
  }

  Widget _categoryChip(String category, int count) {
    final color = _colorForCategory(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(BridgeDS.roundStandard),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconForCategory(category), size: 12, color: color),
          const SizedBox(width: 6),
          Text(category, style: BridgeDSColors.of(context).caption.copyWith(
            fontSize: 14,
            color: color,
            fontWeight: FontWeight.w600,
          )),
          SizedBox(width: 4),
          Text('$count', style: BridgeDSColors.of(context).labelMono.copyWith(
            fontSize: 14,
            color: color.withValues(alpha: 0.7),
          )),
        ],
      ),
    );
  }

  Widget _fileTile(DesktopFileSummary file) {
    final color = _colorForCategory(file.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(_iconForCategory(file.kind), size: 14, color: color),
          SizedBox(width: 8),
          Expanded(
            child: Text(file.name,
              style: BridgeDSColors.of(context).caption.copyWith(
                fontSize: 14,
                color: BridgeDSColors.of(context).textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8),
          Text(_formatSize(file.sizeBytes),
            style: BridgeDSColors.of(context).labelMono.copyWith(
              fontSize: 14,
              color: BridgeDSColors.of(context).textMuted,
            )),
        ],
      ),
    );
  }

  Color _colorForCategory(String kind) {
    switch (kind) {
      case '圖片':
        return BridgeDSColors.of(context).accentMagenta;
      case '文件':
        return BridgeDSColors.of(context).accentBlue;
      case '影片':
        return BridgeDSColors.of(context).accentPurple;
      case '音訊':
        return BridgeDSColors.of(context).accentGreen;
      case '壓縮檔':
        return BridgeDSColors.of(context).accentYellow;
      case '程式碼':
        return BridgeDSColors.of(context).accentMiro;
      default:
        return BridgeDSColors.of(context).textMuted;
    }
  }

  IconData _iconForCategory(String kind) {
    switch (kind) {
      case '圖片':
        return Icons.image_outlined;
      case '文件':
        return Icons.description_outlined;
      case '影片':
        return Icons.movie_outlined;
      case '音訊':
        return Icons.music_note_outlined;
      case '壓縮檔':
        return Icons.folder_zip_outlined;
      case '程式碼':
        return Icons.code;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
