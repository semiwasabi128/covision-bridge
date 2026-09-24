// lib/screens/desktop/settings/theme_settings_page.dart
//
// [教練 Agent 2026-08-04] Phase E+：主題設定頁
//
// 功能：
//   - 列出已安裝主題（內建 + 第三方）
//   - 一鍵切換主題
//   - 從 ZIP 匯入
//   - 卸載第三方主題（內建不可卸載）

import 'package:flutter/material.dart';

import '../../../models/theme_pack.dart';
import '../../../services/theme_pack_service.dart';
import '../../../state/theme_provider.dart';
import '../../../theme/bridge_design_system.dart';
import '../../../widgets/adaptive_scaffold.dart';

class ThemeSettingsPage extends StatefulWidget {
  final ThemeProvider themeProvider;

  const ThemeSettingsPage({super.key, required this.themeProvider});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  bool _importing = false;
  String? _statusMessage;

  Future<void> _importTheme() async {
    setState(() {
      _importing = true;
      _statusMessage = null;
    });
    try {
      final service = ThemePackService();
      final pack = await service.pickAndImport();
      if (pack == null) {
        setState(() {
          _importing = false;
          _statusMessage = '已取消';
        });
        return;
      }
      // 安裝 + 套用
      await service.install(pack);
      await widget.themeProvider.refresh();
      await widget.themeProvider.applyTheme(pack);
      setState(() {
        _importing = false;
        _statusMessage = '已匯入並啟用「${pack.name}」';
      });
    } catch (e) {
      setState(() {
        _importing = false;
        _statusMessage = '匯入失敗: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    final activeId = widget.themeProvider.activePackId;
    final packs = widget.themeProvider.installedPacks;

    return Scaffold(
      backgroundColor: ds.canvas,
      appBar: AppBar(
        title: const Text('主題設定'),
        backgroundColor: ds.surface,
        foregroundColor: ds.textPrimary,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 說明
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ds.surface,
                borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
                border: Border.all(color: ds.borderDefault),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: ds.accentBlue),
                      const SizedBox(width: 8),
                      Text(
                        '主題包',
                        style: ds.headingS.copyWith(color: ds.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '主題包是一份可下載的設計資產，內含 33 個色彩 token。'
                    '從設定 → 主題匯入 ZIP 即可一鍵切換整個 App 的配色。\n\n'
                    '目前內建 2 套（深色 / 淺色）。更多主題可由社群貢獻。',
                    style: ds.body.copyWith(color: ds.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 匯入按鈕
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _importing ? null : _importTheme,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.file_download_outlined),
                    label: Text(_importing ? '匯入中...' : '匯入主題包 ZIP'),
                  ),
                ),
              ],
            ),

            // 狀態訊息
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: ds.caption.copyWith(
                  color: _statusMessage!.startsWith('匯入失敗')
                      ? ds.accentRed
                      : ds.textSecondary,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // 已安裝主題清單
            Expanded(
              child: ListView.builder(
                itemCount: packs.length,
                itemBuilder: (context, index) {
                  final pack = packs[index];
                  final isActive = pack.id == activeId;
                  final isBuiltin = pack.id == ThemePackService.builtinDarkId ||
                      pack.id == ThemePackService.builtinLightId;
                  return _ThemePackCard(
                    pack: pack,
                    isActive: isActive,
                    isBuiltin: isBuiltin,
                    onActivate: () => _activate(pack),
                    onUninstall: isBuiltin
                        ? null
                        : () => _uninstall(pack),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _activate(ThemePack pack) async {
    try {
      await widget.themeProvider.applyTheme(pack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切換到「${pack.name}」')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切換失敗: $e')),
      );
    }
  }

  Future<void> _uninstall(ThemePack pack) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('卸載主題包？'),
        content: Text('確定要卸載「${pack.name}」嗎？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('卸載'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await widget.themeProvider.uninstall(pack.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已卸載「${pack.name}」')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('卸載失敗: $e')),
      );
    }
  }
}

class _ThemePackCard extends StatelessWidget {
  final ThemePack pack;
  final bool isActive;
  final bool isBuiltin;
  final VoidCallback onActivate;
  final VoidCallback? onUninstall;

  const _ThemePackCard({
    required this.pack,
    required this.isActive,
    required this.isBuiltin,
    required this.onActivate,
    this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive ? ds.surfaceElevated : ds.surface,
        borderRadius: BorderRadius.circular(BridgeDS.roundComfortable),
        border: Border.all(
          color: isActive ? ds.accentBlue : ds.borderDefault,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 顏色預覽（4 個小圓點：canvas / accentBlue / accentRed / textPrimary）
              _ColorPreview(pack: pack),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.name,
                      style: ds.headingS.copyWith(color: ds.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pack.author} · ${pack.license}',
                      style: ds.caption.copyWith(color: ds.textMuted),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ds.accentGreen.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '啟用中',
                    style: ds.caption.copyWith(color: ds.accentGreen),
                  ),
                )
              else if (isBuiltin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ds.accentPurple.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '內建',
                    style: ds.caption.copyWith(color: ds.accentPurple),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pack.description,
            style: ds.body.copyWith(color: ds.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (!isActive)
                FilledButton.icon(
                  onPressed: onActivate,
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('啟用'),
                ),
              if (onUninstall != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onUninstall,
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('卸載'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorPreview extends StatelessWidget {
  final ThemePack pack;
  const _ColorPreview({required this.pack});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dot(pack.colors['canvas']!),
        _dot(pack.colors['accentBlue']!),
        _dot(pack.colors['accentRed']!),
        _dot(pack.colors['textPrimary']!),
      ],
    );
  }

  Widget _dot(Color color) => Container(
        width: 20,
        height: 20,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black26, width: 0.5),
        ),
      );
}