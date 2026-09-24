import 'package:flutter/foundation.dart';

import '../models/bridge_action.dart';

class CapabilityActivationSignal {
  final String id;
  final String title;
  final BridgeActionType? actionType;
  final String source;
  final String? provider;
  final DateTime emittedAt;

  CapabilityActivationSignal({
    required this.title,
    required this.source,
    this.actionType,
    this.provider,
    DateTime? emittedAt,
    String? id,
  }) : emittedAt = emittedAt ?? DateTime.now(),
       id = id ?? 'capability-signal-${DateTime.now().microsecondsSinceEpoch}';

  bool matches(BridgeAction action) {
    final expected = actionType;
    if (expected == null) return true;
    return expected == action.type;
  }
}

class CapabilityActivationBus {
  CapabilityActivationBus._();

  static final CapabilityActivationBus instance = CapabilityActivationBus._();

  final ValueNotifier<CapabilityActivationSignal?> latest = ValueNotifier(null);

  void emit(CapabilityActivationSignal signal) {
    latest.value = signal;
  }

  void emitReady({
    required String title,
    required String source,
    BridgeActionType? actionType,
    String? provider,
  }) {
    emit(
      CapabilityActivationSignal(
        title: title,
        source: source,
        actionType: actionType,
        provider: provider,
      ),
    );
  }

  void resetForTest() {
    latest.value = null;
  }
}
