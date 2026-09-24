// brain_panel_state.dart
// Sprint 6 — Panel 狀態管理（展開/摺疊 + 單層 override + Auto-refresh）
// 建立日期: 2026-07-04 by 教練 Agent (CEO)
//
// 設計原則（Sprint 6 設計文件）：
// - 不用 Bloc，用 ChangeNotifier + ValueNotifier
// - Auto-refresh 訂閱 BrainReflectionStore 的 ValueNotifier
// - 單層 override 存在記憶體 Map<String, LayerOverrideMode>
// - 全部摺疊時高度 < 100px，全展開時 < 800px

import 'package:flutter/foundation.dart';

import '../models/transurfing_brain.dart';
import '../services/brain_reflection_store.dart';
import '../widgets/brain_pipeline/layer_source_chip.dart';

class BrainPanelState extends ChangeNotifier {
  /// 是否展開全部 LayerCard
  bool _allExpanded = false;

  /// 展開的層（個別 toggle）
  final Set<String> _expandedLayers = {};

  /// 單層 source override
  final Map<String, LayerOverrideMode> _overrides = {};

  /// 當前的 BrainReflection（從 store 訂閱）
  BrainReflection? _reflection;

  bool get allExpanded => _allExpanded;
  BrainReflection? get reflection => _reflection;
  Map<String, LayerOverrideMode> get overrides => Map.unmodifiable(_overrides);

  /// 是否展開某層
  bool isLayerExpanded(String layerKey) {
    return _allExpanded || _expandedLayers.contains(layerKey);
  }

  /// toggle 單層展開
  void toggleLayer(String layerKey) {
    if (_expandedLayers.contains(layerKey)) {
      _expandedLayers.remove(layerKey);
    } else {
      _expandedLayers.add(layerKey);
    }
    notifyListeners();
  }

  /// toggle 全部展開/摺疊
  void toggleAllExpanded() {
    _allExpanded = !_allExpanded;
    if (!_allExpanded) {
      _expandedLayers.clear();
    }
    notifyListeners();
  }

  /// 取得某層的 override mode
  LayerOverrideMode? getOverride(String layerKey) => _overrides[layerKey];

  /// toggle 單層 override（ai ↔ rule），再點取消
  void toggleOverride(String layerKey) {
    final current = _overrides[layerKey];
    if (current == null) {
      _overrides[layerKey] = LayerOverrideMode.ai;
    } else if (current == LayerOverrideMode.ai) {
      _overrides[layerKey] = LayerOverrideMode.rule;
    } else {
      _overrides.remove(layerKey);
    }
    notifyListeners();
  }

  /// 清除所有 override
  void clearOverrides() {
    _overrides.clear();
    notifyListeners();
  }

  /// 啟動 auto-refresh 訂閱
  void startListening() {
    _reflection = BrainReflectionStore.instance.current;
    BrainReflectionStore.instance.reflection.addListener(_onStoreChanged);
  }

  void _onStoreChanged() {
    _reflection = BrainReflectionStore.instance.current;
    notifyListeners();
  }

  /// 停止訂閱
  void stopListening() {
    BrainReflectionStore.instance.reflection.removeListener(_onStoreChanged);
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
