import 'bridge_action.dart';

enum IntentSpineMode {
  casual,
  clarify,
  analyze,
  execute,
  project,
  assetReuse,
  capabilitySetup,
}

extension IntentSpineModeX on IntentSpineMode {
  String get label {
    switch (this) {
      case IntentSpineMode.casual:
        return '閒聊';
      case IntentSpineMode.clarify:
        return '釐清需求';
      case IntentSpineMode.analyze:
        return '分析判斷';
      case IntentSpineMode.execute:
        return '執行任務';
      case IntentSpineMode.project:
        return '建立專案門';
      case IntentSpineMode.assetReuse:
        return '調用既有資產';
      case IntentSpineMode.capabilitySetup:
        return '開通能力';
    }
  }
}

class IntentSpine {
  final String rawText;
  final String normalizedGoal;
  final IntentSpineMode mode;
  final double confidence;
  final List<String> signals;
  final List<BridgeActionType> suggestedBridgeTypes;
  final bool shouldCheckReusableAssets;
  final bool shouldCreateOrRouteProject;
  final bool shouldExecuteImmediately;
  final bool shouldAnalyzeBeforeBridge;
  final bool shouldSelectManagedFolderRuleFirst;
  final bool shouldAskClarifyingQuestion;
  final List<String> clarificationOptions;

  const IntentSpine({
    required this.rawText,
    required this.normalizedGoal,
    required this.mode,
    required this.confidence,
    required this.signals,
    this.suggestedBridgeTypes = const [],
    this.shouldCheckReusableAssets = false,
    this.shouldCreateOrRouteProject = false,
    this.shouldExecuteImmediately = false,
    this.shouldAnalyzeBeforeBridge = false,
    this.shouldSelectManagedFolderRuleFirst = false,
    this.shouldAskClarifyingQuestion = false,
    this.clarificationOptions = const [],
  });

  String get userFacingSummary {
    if (normalizedGoal.trim().isEmpty) return mode.label;
    return '${mode.label}：$normalizedGoal';
  }
}
