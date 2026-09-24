import 'package:flutter/foundation.dart';

/// No-op JS bridge used on non-web platforms and in VM tests.
class JsBridge {
  static JsBridge? _instance;
  static JsBridge get instance => _instance ??= JsBridge._();
  JsBridge._();

  final ValueNotifier<Map<String, dynamic>?> settingsCommand = ValueNotifier(
    null,
  );
  final ValueNotifier<Map<String, dynamic>?> chatCommand = ValueNotifier(null);
  final ValueNotifier<Map<String, dynamic>> appState = ValueNotifier({
    'screen': 'unknown',
    'ready': false,
  });

  void init() {}

  void updateScreenState(String screen, Map<String, dynamic> state) {
    appState.value = {...appState.value, 'screen': screen, ...state};
  }

  void reportMessages(List<Map<String, dynamic>> messages) {
    appState.value = {
      ...appState.value,
      'messages': messages,
      'messageCount': messages.length,
    };
  }

  void reportBridgeActions(List<Map<String, dynamic>> actions) {
    appState.value = {...appState.value, 'bridgeActions': actions};
  }

  void reportConnectionResult(bool success, String message) {
    appState.value = {
      ...appState.value,
      'connectionTest': {'success': success, 'message': message},
    };
  }

  void reportCompanionRuntime(Map<String, dynamic> payload) {
    appState.value = {...appState.value, 'companionRuntime': payload};
  }

  void clearSettingsCommand() => settingsCommand.value = null;
  void clearChatCommand() => chatCommand.value = null;
  void clearNavigateCommand() {
    final current = Map<String, dynamic>.from(appState.value);
    current.remove('navigateTo');
    appState.value = current;
  }
}
