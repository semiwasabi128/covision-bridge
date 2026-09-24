// sub_workflow_picker.dart
// [教練 Agent 2026-08-15] 子工作流選擇器 — 使用者 提案
//
// 子工作流節點原本要手填 ID（.bridge-workflow ID 文字框），
// 改為：點擊 → 彈出選擇器 →
//   1. 預設資料夾 ~/Documents/bridge_workflows/ 的 .bridge-workflow 檔案
//   2. 內建範本（ig_post 等，可作為子工作流引用）
//   3. 「瀏覽其他位置」→ 檔案總管式導航，使用者可選任意位置
// 選好 → 回呼注入 workflowRef 到節點。

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bridge_app/theme/bridge_design_system.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../services/vault/vault_templates.dart';

/// 子工作流預設資料夾（App 初始安裝時建立）
Future<Directory> subWorkflowDefaultDir() async {
  final home = Platform.environment['HOME'] ?? Directory.current.path;
  final dir = Directory('$home/Documents/bridge_workflows');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

/// 選擇結果：id（內建範本 ID 或檔案路徑）
class SubWorkflowPick {
  final String ref;      // workflowRef 值（範本 ID 或檔案絕對路徑）
  final String label;    // 顯示名
  final bool isBuiltin;  // 內建範本？
  final bool isFile;     // 檔案？
  const SubWorkflowPick(this.ref, this.label, {this.isBuiltin = false, this.isFile = false});
}

/// 子工作流選擇器對話框
class SubWorkflowPickerDialog extends StatefulWidget {
  final String currentRef;

  const SubWorkflowPickerDialog({super.key, required this.currentRef});

  @override
  State<SubWorkflowPickerDialog> createState() => _SubWorkflowPickerDialogState();
}

class _SubWorkflowPickerDialogState extends State<SubWorkflowPickerDialog> {
  List<SubWorkflowPick> _items = [];
  Directory? _browseDir;      // null = 預設視圖（預設資料夾 + 內建範本）
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = <SubWorkflowPick>[];

    if (_browseDir == null) {
      // 預設視圖：內建範本 + 預設資料夾的 .bridge-workflow 檔
      final templates = VaultTemplateService.instance.getBuiltinTemplates()
          .where((t) => t.nodes.isNotEmpty); // 空範本（教學入口）不列
      for (final t in templates) {
        items.add(SubWorkflowPick(t.id, t.name, isBuiltin: true));
      }
      try {
        final dir = await subWorkflowDefaultDir();
        final files = await dir.list().toList();
        files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        for (final f in files) {
          if (f is File && f.path.endsWith('.bridge-workflow')) {
            final name = f.path.split(Platform.pathSeparator).last;
            items.add(SubWorkflowPick(f.path, name, isFile: true));
          }
        }
      } catch (_) {/* 資料夾讀取失敗就只列內建 */}
    } else {
      // 瀏覽模式：列出目錄內容
      try {
        final entries = await _browseDir!.list().toList();
        entries.sort((a, b) {
          final aDir = a is Directory, bDir = b is Directory;
          if (aDir != bDir) return aDir ? -1 : 1;
          return a.path.split(Platform.pathSeparator).last
              .compareTo(b.path.split(Platform.pathSeparator).last);
        });
        for (final e in entries) {
          final name = e.path.split(Platform.pathSeparator).last;
          if (e is Directory) {
            if (name.startsWith('.')) continue;
            items.add(SubWorkflowPick(e.path, '📁 $name', isFile: false));
          } else if (e is File && (name.endsWith('.bridge-workflow') || name.endsWith('.json'))) {
            items.add(SubWorkflowPick(e.path, name, isFile: true));
          }
        }
      } catch (_) {}
    }

    if (mounted) setState(() { _items = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Dialog(
      backgroundColor: ds.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(BridgeDS.roundComfortable)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: ds.borderDefault)),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_tree_outlined, size: 18, color: ds.accentBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _browseDir == null ? '選擇子工作流' : '瀏覽資料夾',
                      style: TierStyle.of(context, Tier.cardTitle).toTextStyle()
                          .copyWith(color: ds.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                    color: ds.textMuted,
                  ),
                ],
              ),
            ),
            // 路徑條（瀏覽模式）
            if (_browseDir != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: ds.canvas),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_upward, size: 16),
                      tooltip: '上一層',
                      onPressed: () {
                        final parent = _browseDir!.parent;
                        setState(() => _browseDir = parent.path == _browseDir!.path ? null : parent);
                        _load();
                      },
                      color: ds.textSecondary,
                    ),
                    Expanded(
                      child: Text(
                        _browseDir!.path,
                        style: TierStyle.of(context, Tier.cardBody).toTextStyle()
                            .copyWith(color: ds.textTertiary, fontFamily: 'monospace', fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            // 清單
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                      ? Center(
                          child: Text('沒有找到工作流檔案',
                              style: TextStyle(color: ds.textMuted)))
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final item = _items[i];
                            final selected = item.ref == widget.currentRef;
                            final isDir = !item.isBuiltin && !item.isFile;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                item.isBuiltin
                                    ? Icons.auto_awesome
                                    : isDir
                                        ? Icons.folder_outlined
                                        : Icons.description_outlined,
                                size: 18,
                                color: item.isBuiltin ? ds.accentMagenta : (isDir ? ds.accentBlue : ds.textTertiary),
                              ),
                              title: Text(
                                item.label,
                                style: TierStyle.of(context, Tier.listItemTitle).toTextStyle()
                                    .copyWith(color: selected ? ds.accentBlue : ds.textPrimary),
                              ),
                              trailing: selected
                                  ? Icon(Icons.check_circle, size: 18, color: ds.accentBlue)
                                  : null,
                              onTap: () {
                                if (isDir) {
                                  setState(() => _browseDir = Directory(item.ref));
                                  _load();
                                } else {
                                  Navigator.of(context).pop(item);
                                }
                              },
                            );
                          },
                        ),
            ),
            // Footer：瀏覽其他位置
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: ds.borderDefault)),
              ),
              child: Row(
                children: [
                  if (_browseDir == null)
                    TextButton.icon(
                      icon: Icon(Icons.folder_open, size: 16, color: ds.accentBlue),
                      label: Text('瀏覽其他位置…',
                          style: TextStyle(color: ds.accentBlue)),
                      onPressed: () async {
                        final dir = await subWorkflowDefaultDir();
                        setState(() => _browseDir = dir);
                        _load();
                      },
                    )
                  else
                    TextButton.icon(
                      icon: Icon(Icons.list, size: 16, color: ds.accentBlue),
                      label: Text('回預設清單', style: TextStyle(color: ds.accentBlue)),
                      onPressed: () {
                        setState(() => _browseDir = null);
                        _load();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
