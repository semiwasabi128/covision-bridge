import '../../models/bridge_action.dart';
import '../bridge_action_executor.dart';

abstract class BridgeActionAdapter {
  String get id;
  String get displayName;
  Set<BridgeActionType> get supportedTypes;

  bool canHandle(BridgeAction action, String provider) {
    return supportedTypes.contains(action.type) && provider == id;
  }

  Future<BridgeActionResult> execute(BridgeAction action);
}
