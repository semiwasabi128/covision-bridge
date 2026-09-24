// lib/state/theme_provider.dart
//
// [教練 Agent 2026-08-04] ThemeProvider v1.1 — 簡化版
//
// 概念：
//   - 「主題」= 一份 BridgeDSColors（33 token 完整定義）
//   - 「深 / 淺切換」不該是「主題切換」，只是亮度反轉
//   - 但因為我們決定「主題包自己定義深淺」(Phase E+ 修正)，
//     所以**取消 ThemeController 的深淺切換**，
//     ThemeProvider 只負責「當前主題是誰」。
//
// API：
//   - applyTheme(ThemePack): 切換到任意主題（含內建/社群）
//   - applyBuiltin(BridgeDSColors.dark/light): 切到內建
//   - cycleToNext(): 切到下一個主題（快速鍵輪播用）
//   - init(): 從 SharedPreferences 讀回上次主題
//
// 維護原則（使用者 2026-08-04）：
//   - 內建只 2 個：dark + light
//   - 社群主題自己一套（不再乘 2 深淺）
//   - 快速鍵輪播所有主題（不限 2 個）

import 'package:flutter/foundation.dart';

import '../models/theme_pack.dart';
import '../services/theme_pack_service.dart';
import '../theme/bridge_design_system.dart';

class ThemeProvider extends ChangeNotifier {
  /// singleton
  static ThemeProvider? _instance;
  static ThemeProvider get instance => _instance ??= ThemeProvider();

  final ThemePackService _service = ThemePackService();

  BridgeDSColors _colors = BridgeDSColors.dark;
  String _activePackId = ThemePackService.builtinDarkId;
  List<ThemePack> _installedPacks = const [];
  bool _initialized = false;

  BridgeDSColors get colors => _colors;
  String get activePackId => _activePackId;
  List<ThemePack> get installedPacks => _installedPacks;
  bool get initialized => _initialized;
  ThemePack? get activePack {
    for (final p in _installedPacks) {
      if (p.id == _activePackId) return p;
    }
    return null;
  }

  Future<void> init() async {
    if (_initialized) return;

    final activeId = await _service.getActiveId();
    final allPacks = await _service.listInstalled();

    ThemePack active;
    try {
      active = allPacks.firstWhere((p) => p.id == activeId);
    } catch (_) {
      active = allPacks.first;
    }

    _activePackId = active.id;
    _colors = active.toBridgeDSColors();
    _installedPacks = allPacks;
    _initialized = true;

    notifyListeners();
    debugPrint('[ThemeProvider] init: active=$_activePackId, packs=${_installedPacks.length}');
  }

  /// 套用任意主題包（內建或第三方）
  Future<void> applyTheme(ThemePack pack) async {
    await _service.setActive(pack.id);
    _activePackId = pack.id;
    _colors = pack.toBridgeDSColors();
    notifyListeners();
    debugPrint('[ThemeProvider] applyTheme: ${pack.id}');
  }

  /// 卸載第三方主題；若是當前主題則切回 dark
  Future<void> uninstall(String packId) async {
    await _service.uninstall(packId);
    _installedPacks = await _service.listInstalled();
    if (_activePackId == packId) {
      final dark = _installedPacks.firstWhere(
        (p) => p.id == ThemePackService.builtinDarkId,
      );
      await applyTheme(dark);
    } else {
      notifyListeners();
    }
  }

  /// 切到下一個主題（快速鍵輪播用）
  /// 不循環，到尾巴就停在最後一個
  Future<void> cycleToNext() async {
    if (_installedPacks.isEmpty) return;
    final idx = _installedPacks.indexWhere((p) => p.id == _activePackId);
    final next = (idx + 1) >= _installedPacks.length ? 0 : idx + 1;
    await applyTheme(_installedPacks[next]);
  }

  /// 匯入第三方主題 + 套用
  Future<void> importAndApply(List<int> zipBytes) async {
    final pack = await _service.importFromZip(zipBytes);
    await _service.install(pack);
    _installedPacks = await _service.listInstalled();
    await applyTheme(pack);
  }

  /// 重整已安裝清單
  Future<void> refresh() async {
    _installedPacks = await _service.listInstalled();
    notifyListeners();
  }
}