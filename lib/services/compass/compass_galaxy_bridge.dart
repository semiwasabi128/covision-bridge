// compass_galaxy_bridge.dart
// 羅盤 ↔ galaxy.html（3D 星系）橋接器。
//
// 模式：store → 匯出 galaxy_rules.json → WebView 透過 http://127.0.0.1:<port>/ 載入
//       或 postMessage 即時套用。規則真相仍在 store，WebView 純渲染端。
//
// 寫入端：store 變更 → 廣播 rulesChanged → 匯出器重寫 JSON + postMessage
// 讀取端：galaxy.html 透過 fetch('galaxy_rules.json') 或 postMessage 取得最新參數

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'compass_models.dart';
import 'compass_store.dart';

/// 3D 星系規則匯出器
class CompassGalaxyBridge {
  final CompassStore store;
  StreamSubscription? _sub;
  Directory? _exportDir;

  CompassGalaxyBridge(this.store);

  /// 設定匯出目錄（預設 = ~/Library/Application Support/bridge_app）
  void setExportDir(Directory dir) {
    _exportDir = dir;
  }

  void start() {
    _sub?.cancel();
    _sub = store.events.listen((e) {
      if (e.type == 'rulesChanged') {
        exportGalaxyRules(organId: 'brain.galaxy3d');
      }
    });
    // 啟動時立刻匯出一次
    exportGalaxyRules(organId: 'brain.galaxy3d');
  }

  /// 把 organ 的 active 規則寫入 JSON 檔，供 galaxy.html 載入
  File exportGalaxyRules({required String organId}) {
    final dir = _exportDir ?? _defaultDir();
    final out = <String, dynamic>{
      'version': store.version,
      'exportedAt': DateTime.now().toIso8601String(),
      'organ': organId,
      'rules': <String, dynamic>{},
    };
    for (final r in store.rules(organId: organId)) {
      if (r.status == CompassRuleStatus.active) {
        (out['rules'] as Map<String, dynamic>)[r.id] = {
          'params': r.params,
          'kind': r.kind.name,
          'why': r.why,
          'updatedBy': r.updatedBy,
          'updatedAt': r.updatedAt.toIso8601String(),
        };
      }
    }
    final f = File('${dir.path}/galaxy_rules.json');
    f.writeAsStringSync(jsonEncode(out));
    return f;
  }

  Directory _defaultDir() {
    final home = Platform.environment['HOME'] ?? '/';
    return Directory('$home/Library/Application Support/bridge_app');
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
