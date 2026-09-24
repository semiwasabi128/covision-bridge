// lib/state/typography_scale_provider.dart
//
// [教練 Agent 2026-08-04] TypographyScaleProvider
//
// 功能：全域字體縮放（無障礙）
//   - 預設 scale = 1.0
//   - 最小 scale = 0.85（90% 縮減，再小會看不清）
//   - 最大 scale = 2.0（200%，老花眼友善）
//   - 快速鍵：Cmd +/-/0
//
// 設計：
//   - singleton，跟 ThemeProvider 同樣 pattern
//   - 持久化 SharedPreferences
//   - 跟 BridgeDS 整合：每個 token 套用 scale

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TypographyScaleProvider extends ChangeNotifier {
  /// singleton
  static TypographyScaleProvider? _instance;
  static TypographyScaleProvider get instance =>
      _instance ??= TypographyScaleProvider();

  static const double minScale = 0.85;
  static const double maxScale = 2.0;
  static const double defaultScale = 1.0;
  static const double step = 0.1;
  static const String _prefsKey = 'typography_scale';

  double _scale = defaultScale;
  bool _initialized = false;

  double get scale => _scale;
  bool get initialized => _initialized;

  /// 套用 scale 到任何字體大小
  /// 確保不會小於 14（使用者 2026-08-04 規定：最小字 14）
  /// 即使 scale=0.85，原本 16 也只變 13.6 → 但這是「縮減」行為
  /// 但若 scale=0.85，原本 14 會變 11.9 → 違規！所以 scale 縮減時也有下限 14
  double scaled(double original) {
    final s = original * _scale;
    return s < 14.0 ? 14.0 : s;
  }

  /// 增加（Cmd +）
  void increase() {
    final next = (_scale + step).clamp(minScale, maxScale);
    if (next != _scale) {
      _scale = next;
      _save();
      notifyListeners();
      debugPrint('[TypographyScale] increase: $_scale');
    }
  }

  /// 減少（Cmd -）
  void decrease() {
    final next = (_scale - step).clamp(minScale, maxScale);
    if (next != _scale) {
      _scale = next;
      _save();
      notifyListeners();
      debugPrint('[TypographyScale] decrease: $_scale');
    }
  }

  /// 重置（Cmd 0）
  void reset() {
    if (_scale != defaultScale) {
      _scale = defaultScale;
      _save();
      notifyListeners();
      debugPrint('[TypographyScale] reset: $_scale');
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(_prefsKey);
      if (saved != null) {
        _scale = saved.clamp(minScale, maxScale);
      }
    } catch (e) {
      debugPrint('[TypographyScale] init 失敗: $e');
    }
    _initialized = true;
    debugPrint('[TypographyScale] init: $_scale');
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKey, _scale);
    } catch (e) {
      debugPrint('[TypographyScale] save 失敗: $e');
    }
  }
}