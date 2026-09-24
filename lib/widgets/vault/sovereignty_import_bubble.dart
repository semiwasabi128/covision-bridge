// sovereignty_import_bubble.dart
// [資料主權 2026-09-15 Blue 令] 匯入前提示語泡泡——
// 讓使用者在資料進入向量資料庫之前，就看見：
//   1. 他的數位資產主權（資料是他的，去哪他決定）
//   2. 兩種模式的真實差別（不是行銷話術，是實測數據）
//
// 顯示時機：使用者按「開始嵌入」→ 泡泡彈出 → 選模式 → 才開始跑。
// 記憶：使用者選過一次就記住（下次直接用上次模式，泡泡變一行確認）——
// 過程不能太繁瑣（Blue 09-14 原則）。
//
// 兩模式數據來源：docs/benchmarks/vision-blind-2026-09-14（盲測實測）：
//   雲端（gpt-4o-mini）：品種辨識 20/20、~5s/張、~3100 token/張（09-15 實測 usage），照片送 OpenAI
//   本地（Gemma@18789）：品種辨識 17/20、~42s/張、免費、照片不出這台機器

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';

enum SovereigntyMode { cloud, local }

class SovereigntyImportBubble {
  SovereigntyImportBubble._();

  static const _modeKey = 'sovereignty.import.mode';

  static Future<SovereigntyMode?> lastMode() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_modeKey);
    return v == 'local' ? SovereigntyMode.local : v == 'cloud' ? SovereigntyMode.cloud : null;
  }

  /// 匯入前的主權泡泡。回傳 null＝使用者取消（不嵌入）。
  ///
  /// [pendingCount] 待嵌入檔數（泡泡裡顯示「這 N 個檔案」——具體才有感）
  /// [hasLocalModel] 本地模型是否在線（離線時本地選項標「無法使用」）
  static Future<SovereigntyMode?> show(
    BuildContext context, {
    required int pendingCount,
    required bool hasLocalModel,
  }) async {
    final last = await lastMode();
    if (!context.mounted) return null;

    // 用過一次：一行確認（不繁瑣原則——主權看得見，但不擋路）
    if (last != null) {
      return _showQuickConfirm(context, last, pendingCount, hasLocalModel);
    }
    // 第一次：完整泡泡（主權說明＋兩模式數據對照）
    return _showFull(context, pendingCount, hasLocalModel);
  }

  static Future<SovereigntyMode?> _showQuickConfirm(
    BuildContext context, SovereigntyMode last, int n, bool hasLocal) async {
    final modeText = last == SovereigntyMode.cloud
        ? '🟡 雲端優先（你的金鑰直連 OpenAI，照片會送出這台機器）'
        : '🟢 全本地（照片不出這台機器）';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('嵌入 $n 個檔案'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(modeText,
                style: TierStyle.of(context, Tier.cardBody)
                    .toTextStyle()),
            const SizedBox(height: 8),
            Text('上次選的模式。要換嗎？',
                style: TierStyle.of(context, Tier.listItemSubtitle).toTextStyle()),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('換模式'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(last == SovereigntyMode.cloud ? '雲端嵌入' : '本地嵌入'),
          ),
        ],
      ),
    );
    if (ok == true) return last;
    if (ok == null) return null; // 取消對話框 = 不嵌入
    // 「換模式」→ 完整泡泡
    if (!context.mounted) return null;
    return _showFull(context, n, hasLocal);
  }

  static Future<SovereigntyMode?> _showFull(
      BuildContext context, int n, bool hasLocal) {
    final colors = BridgeDSColors.of(context);
    return showDialog<SovereigntyMode>(
      context: context,
      barrierDismissible: false, // 主權選擇要明確——不能點外面閃掉
      builder: (ctx) {
        SovereigntyMode? selected = SovereigntyMode.cloud; // 預設雲端（Blue 09-14 拍板）
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.shield_outlined, color: colors.accentGreen, size: 20),
                const SizedBox(width: 8),
                const Text('你的資料要怎麼處理？'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Text(
                    '這 $n 個檔案即將建立搜尋索引。它們是你的資產——'
                    '送去哪裡分析，由你決定：',
                    style:
                        TierStyle.of(context, Tier.cardBody).toTextStyle(),
                  ),
                  const SizedBox(height: 12),
                  _modeCard(
                    ctx,
                    value: SovereigntyMode.cloud,
                    group: selected,
                    dot: colors.accentYellow,
                    title: '🟡 雲端優先（預設）',
                    lines: const [
                      '· 照片經你的金鑰直連 OpenAI（gpt-4o-mini）',
                      '· 品種辨識 20/20、約 5 秒/張',
                      // [09-15 Blue 令] 不寫金額——價格是 provider 訂的會變；
                      // token 是不變的物理量，使用者自己換算當前牌價。
                      // 實測：detail:low 圖片 ~2833 + 提示 ~90 + 回應 ~200
                      '· 約 3,100 token／張，走資料路徑閘門記帳',
                      '· 無網路時自動退回本地',
                    ],
                    onPick: () => setState(() => selected = SovereigntyMode.cloud),
                  ),
                  const SizedBox(height: 8),
                  _modeCard(
                    ctx,
                    value: SovereigntyMode.local,
                    group: selected,
                    dot: colors.accentGreen,
                    title: '🟢 全本地（主權模式）',
                    subtitle: hasLocal ? null : '（本地模型未在線——選了也會退回雲端）',
                    lines: const [
                      '· 照片不出這台機器（本地 Gemma 分析）',
                      '· 品種辨識 17/20、約 42 秒/張',
                      '· 免費、無網路也能跑',
                      '· 適合：機密文件、不想上雲的照片',
                    ],
                    onPick: () => setState(
                        () => selected = SovereigntyMode.local),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '兩種模式都會讀你的資料夾名稱作為提示（例如「魔鬼辣椒/」），'
                    '讓辨識更準——資料夾怎麼建，提示就是什麼。',
                    style: TierStyle.of(context, Tier.listItemMeta)
                        .toTextStyle()
                        .copyWith(color: colors.textMuted),
                  ),
                ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                      _modeKey,
                      selected == SovereigntyMode.local ? 'local' : 'cloud');
                  if (ctx.mounted) Navigator.pop(ctx, selected);
                },
                child: const Text('開始嵌入'),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _modeCard(
    BuildContext context, {
    required SovereigntyMode value,
    required SovereigntyMode? group,
    required Color dot,
    required String title,
    required List<String> lines,
    String? subtitle,
    required VoidCallback onPick,
  }) {
    final colors = BridgeDSColors.of(context);
    final isSelected = value == group;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? colors.accentBlue : colors.borderSubtle,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_off,
              size: 18,
              color: isSelected ? colors.accentBlue : colors.textMuted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TierStyle.of(context, Tier.cardBody)
                          .toTextStyle()
                          .copyWith(fontWeight: FontWeight.w700)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TierStyle.of(context, Tier.listItemMeta)
                            .toTextStyle()
                            .copyWith(color: colors.accentYellow)),
                  const SizedBox(height: 4),
                  ...lines.map((l) => Text(
                        l,
                        style: TierStyle.of(context, Tier.listItemSubtitle)
                            .toTextStyle(),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
