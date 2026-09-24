// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// JS Bridge - 外部自動化測試橋接器
///
/// 允許 OpenClaw CEO 透過 Chrome DevTools + postMessage 操作 Flutter Web App
///
/// 使用方式（從外部 JavaScript console）：
/// ```js
/// window.postMessage({
///   type: 'bridge',
///   action: 'fillSettings',
///   payload: { token: 'sk-xxx', url: 'https://...' }
/// }, '*');
/// ```
class JsBridge {
  static JsBridge? _instance;
  static JsBridge get instance => _instance ??= JsBridge._();
  JsBridge._();

  // 設定頁面的狀態控制器（已廢棄——settings_screen.dart 已刪除）
  final ValueNotifier<Map<String, dynamic>?> settingsCommand = ValueNotifier(
    null,
  );

  // 聊天頁面的狀態控制器（由 ChatScreen 注入）
  final ValueNotifier<Map<String, dynamic>?> chatCommand = ValueNotifier(null);

  // App 狀態回報
  final ValueNotifier<Map<String, dynamic>> appState = ValueNotifier({
    'screen': 'unknown',
    'ready': false,
  });

  /// 初始化 JS Bridge（僅在 Web 環境）
  void init() {
    if (!kIsWeb) return;

    _registerCallbacks();
    _notifyJsReady();
    debugPrint('[JsBridge] Initialized on Web');
  }

  /// 註冊所有可外部呼叫的動作
  void _registerCallbacks() {
    // 建立 Dart callbacks map
    final dartCallbacks = <String, Function>{
      // 設定頁面動作
      'fillSettings': (payload) {
        final url = payload['url'] as String?;
        final token = payload['token'] as String?;
        // 直接注入 ApiService（自動化測試用，繞過 SharedPreferences）
        ApiService.setOverrideConfig(baseUrl: url, token: token);
        settingsCommand.value = {
          'action': 'fill',
          'url': url,
          'token': token,
          'provider': payload['provider'],
        };
      },
      'saveSettings': (_) => settingsCommand.value = {'action': 'save'},
      'testConnection': (_) =>
          settingsCommand.value = {'action': 'testConnection'},
      'getSettingsState': (_) {},

      // 聊天頁面動作
      'sendMessage': (payload) {
        chatCommand.value = {
          'action': 'send',
          'message': payload['message'] ?? '',
          'intent': payload['intent'],
        };
      },
      'getChatState': (_) {},
      'clearChat': (_) => chatCommand.value = {'action': 'clear'},
      'setMode': (payload) {
        chatCommand.value = {
          'action': 'setMode',
          'mode': payload['mode'] ?? 'chat',
        };
      },
      'clickSkill': (payload) {
        chatCommand.value = {
          'action': 'clickSkill',
          'skill': payload['skill'] ?? '',
        };
      },

      // 通用動作
      'navigate': (payload) {
        appState.value = {
          ...appState.value,
          'navigateTo': payload['route'] ?? '/chat',
        };
      },
      'getAppState': (_) =>
          debugPrint('[JsBridge] getAppState: ${appState.value}'),
      'ping': (_) => debugPrint('[JsBridge] pong'),
    };

    // 透過 JS context 註冊
    js.context['__bridgeDartCallbacks'] = js.JsObject.jsify(
      dartCallbacks.map((key, fn) => MapEntry(key, _wrapJsFunction(fn))),
    );
  }

  /// 將 Dart Function 包裝成 JS callable
  dynamic _wrapJsFunction(Function fn) {
    return (dynamic payload) {
      try {
        final map = payload != null ? _jsToMap(payload) : <String, dynamic>{};
        fn(map);
        return true;
      } catch (e) {
        debugPrint('[JsBridge] Error in callback: $e');
        return false;
      }
    };
  }

  /// 通知 JavaScript Flutter 已 ready
  void _notifyJsReady() {
    final register = js.context['__bridgeRegister'];
    if (register != null && register is js.JsFunction) {
      register.apply([js.context['__bridgeDartCallbacks']]);
      debugPrint('[JsBridge] Registered callbacks with JS bridge-controller');
    } else {
      debugPrint(
        '[JsBridge] __bridgeRegister not found, will retry on next frame',
      );
      // 延遲重試（可能 JS 還沒載入完）
      Future.delayed(const Duration(seconds: 1), _notifyJsReady);
    }
  }

  /// 更新 App 狀態（由各 Screen 呼叫）
  void updateScreenState(String screen, Map<String, dynamic> state) {
    appState.value = {...appState.value, 'screen': screen, ...state};
  }

  /// 回報聊天訊息列表（由 ChatScreen 呼叫）
  void reportMessages(List<Map<String, dynamic>> messages) {
    appState.value = {
      ...appState.value,
      'messages': messages,
      'messageCount': messages.length,
    };
  }

  /// 回報目前 AI 回覆中的標記（由 ChatScreen 呼叫）
  void reportBridgeActions(List<Map<String, dynamic>> actions) {
    appState.value = {...appState.value, 'bridgeActions': actions};
  }

  /// 回報連線測試結果
  void reportConnectionResult(bool success, String message) {
    appState.value = {
      ...appState.value,
      'connectionTest': {'success': success, 'message': message},
    };
  }

  /// 發布電子夥伴 runtime，供 Bridge Desktop / 外部控制器讀取。
  void reportCompanionRuntime(Map<String, dynamic> payload) {
    appState.value = {...appState.value, 'companionRuntime': payload};

    try {
      html.window.localStorage['bridge.runtime.v1'] = jsonEncode(payload);
    } catch (e) {
      debugPrint('[JsBridge] Failed to write runtime localStorage: $e');
    }

    try {
      js.context['__bridgeRuntime'] = js.JsObject.jsify(payload);
    } catch (e) {
      debugPrint('[JsBridge] Failed to expose runtime window object: $e');
    }

    try {
      html.window.dispatchEvent(
        html.CustomEvent('bridge-runtime', detail: payload),
      );
    } catch (e) {
      debugPrint('[JsBridge] Failed to dispatch runtime event: $e');
    }
  }

  /// 清除已處理的命令（由各 Screen 在處理完後呼叫）
  void clearSettingsCommand() => settingsCommand.value = null;
  void clearChatCommand() => chatCommand.value = null;
  void clearNavigateCommand() {
    final current = Map<String, dynamic>.from(appState.value);
    current.remove('navigateTo');
    appState.value = current;
  }

  /// JS Object → Dart Map 轉換
  Map<String, dynamic> _jsToMap(dynamic obj) {
    if (obj == null) return {};
    if (obj is Map) {
      return obj.map((k, v) => MapEntry(k.toString(), _jsValueToDart(v)));
    }
    if (obj is js.JsObject) {
      final result = <String, dynamic>{};
      final keys = js.context['Object'].callMethod('keys', [obj]);
      for (var i = 0; i < keys['length']; i++) {
        final key = keys[i] as String;
        result[key] = _jsValueToDart(obj[key]);
      }
      return result;
    }
    return {};
  }

  dynamic _jsValueToDart(dynamic value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    if (value is js.JsObject) return _jsToMap(value);
    if (value is List) return value.map(_jsValueToDart).toList();
    return value.toString();
  }
}
