import 'package:flutter/foundation.dart';

import '../models/companion_runtime.dart';
import 'companion_runtime_store.dart';
import 'js_bridge.dart';

class CompanionRuntimeOutlet {
  CompanionRuntimeOutlet._();

  static final CompanionRuntimeOutlet instance = CompanionRuntimeOutlet._();

  static const schema = 'bridge.companion.runtime.v1';
  static const source = 'bridge_app';

  CompanionRuntimeStore? _store;
  JsBridge? _bridge;
  VoidCallback? _listener;
  Map<String, dynamic> _latestPayload = const {};

  Map<String, dynamic> get latestPayload =>
      Map<String, dynamic>.unmodifiable(_latestPayload);

  bool get isStarted => _listener != null;

  static Map<String, dynamic> payloadFor(
    CompanionRuntimeState runtime, {
    DateTime? exportedAt,
  }) {
    return {
      'schema': schema,
      'source': source,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'runtime': runtime.toJson(),
    };
  }

  void start({CompanionRuntimeStore? store, JsBridge? bridge}) {
    if (isStarted) {
      publish((_store ?? store ?? CompanionRuntimeStore.instance).current);
      return;
    }
    _store = store ?? CompanionRuntimeStore.instance;
    _bridge = bridge ?? JsBridge.instance;
    _listener = () => publish(_store!.current);
    _store!.state.addListener(_listener!);
    publish(_store!.current);
  }

  void publish(CompanionRuntimeState runtime) {
    final payload = payloadFor(runtime);
    _latestPayload = payload;
    (_bridge ?? JsBridge.instance).reportCompanionRuntime(payload);
  }

  void stop() {
    final listener = _listener;
    if (listener != null) {
      _store?.state.removeListener(listener);
    }
    _listener = null;
    _store = null;
    _bridge = null;
    _latestPayload = const {};
  }

  @visibleForTesting
  void resetForTest() => stop();
}
