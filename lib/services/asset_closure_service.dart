// [Sprint 18c-1 — 資產引用閉環]
// AssetClosureService：實現「任務前查資產 → 引用 → 執行 → 歸檔寫回」完整閉環。
//
// 流程：
// 1. beforeTask：根據門意圖+步驟，查詢可用資產（用 DigitalAssetRegistryStore.suggestForTask）
// 2. linkAsset：將資產 ID 綁定到門的 flow step
// 3. completeStep：步驟完成時，將執行結果歸檔為新資產或寫入大腦
// 4. getLinkedAssets：查詢門/步驟已連結的資產

import '../models/digital_asset.dart';
import '../models/flow_step.dart';
import '../models/project_door.dart';
import 'digital_asset_registry_store.dart';
import 'project_door_store.dart';

/// 資產閉環中的步驟建議結果
class AssetClosureSuggestion {
  final DigitalAsset asset;
  final int score;
  final List<String> reasons;
  final String suggestedForStepId;

  const AssetClosureSuggestion({
    required this.asset,
    required this.score,
    required this.reasons,
    required this.suggestedForStepId,
  });
}

/// 步驟完成後的歸檔結果
class StepArchiveResult {
  final String? newAssetId;
  final bool memoryWritten;
  final String message;

  const StepArchiveResult({
    this.newAssetId,
    this.memoryWritten = false,
    required this.message,
  });
}

class AssetClosureService {
  final DigitalAssetRegistryStore _assetStore;
  final ProjectDoorStore _doorStore;

  const AssetClosureService({
    DigitalAssetRegistryStore? assetStore,
    ProjectDoorStore? doorStore,
  })  : _assetStore = assetStore ?? const DigitalAssetRegistryStore(),
        _doorStore = doorStore ?? const ProjectDoorStore();

  // ═══════════════════════════════════════════════════════
  // 1. 任務前查資產
  // ═══════════════════════════════════════════════════════

  /// 根據門的意圖和步驟，推薦可用的資產
  Future<List<AssetClosureSuggestion>> beforeTask(
    ProjectDoor door,
  ) async {
    final suggestions = <AssetClosureSuggestion>[];

    // 對整個門查資產
    final doorSuggestions = await _assetStore.suggestForTask(
      request: door.sourceIntent,
      projectTitle: door.title,
      projectCapabilities: door.requiredBridges,
      excludeProjectDoorId: door.id,
      limit: 5,
    );

    for (final s in doorSuggestions) {
      suggestions.add(AssetClosureSuggestion(
        asset: s.asset,
        score: s.score,
        reasons: s.reasons,
        suggestedForStepId: '', // 門級建議
      ));
    }

    // 對每個未完成的步驟也查資產
    for (final step in door.flowSteps.where((s) => !s.isDone)) {
      final stepSuggestions = await _assetStore.suggestForTask(
        request: '${step.title} ${step.description ?? ''}',
        projectTitle: door.title,
        projectCapabilities: door.requiredBridges,
        excludeProjectDoorId: door.id,
        limit: 2,
      );
      for (final s in stepSuggestions) {
        // 避免重複建議同一資產
        if (suggestions.any((e) => e.asset.id == s.asset.id)) continue;
        suggestions.add(AssetClosureSuggestion(
          asset: s.asset,
          score: s.score,
          reasons: s.reasons,
          suggestedForStepId: step.id,
        ));
      }
    }

    suggestions.sort((a, b) => b.score.compareTo(a.score));
    return suggestions;
  }

  // ═══════════════════════════════════════════════════════
  // 2. 引用資產到步驟
  // ═══════════════════════════════════════════════════════

  /// 將資產連結到門的特定步驟
  Future<ProjectDoor?> linkAssetToStep(
    String doorId,
    String stepId,
    String assetId,
  ) async {
    final all = await _doorStore.loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null;
    final door = all[index];
    final stepIndex = door.flowSteps.indexWhere((s) => s.id == stepId);
    if (stepIndex < 0) return null;

    final step = door.flowSteps[stepIndex];
    final newAssetIds = {...step.linkedAssetIds, assetId}.toList();
    final newSteps = List<FlowStep>.of(door.flowSteps);
    newSteps[stepIndex] = step.copyWith(linkedAssetIds: newAssetIds);

    // 同時加到門級的 linkedAssetIds
    final doorAssetIds = {...door.linkedAssetIds, assetId}.toList();
    final updated = door.copyWith(
      flowSteps: newSteps,
      linkedAssetIds: doorAssetIds,
      updatedAt: DateTime.now(),
    );
    all[index] = updated;
    // 用 store 的內部 persist
    await _doorStore.saveActive(updated);
    return updated;
  }

  /// 將資產連結到門（門級）
  Future<ProjectDoor?> linkAssetToDoor(
    String doorId,
    String assetId,
  ) async {
    final all = await _doorStore.loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null;
    final door = all[index];
    final newAssetIds = {...door.linkedAssetIds, assetId}.toList();
    final updated = door.copyWith(
      linkedAssetIds: newAssetIds,
      updatedAt: DateTime.now(),
    );
    all[index] = updated;
    await _doorStore.saveActive(updated);
    return updated;
  }

  // ═══════════════════════════════════════════════════════
  // 3. 歸檔寫回
  // ═══════════════════════════════════════════════════════

  /// 步驟完成後，將結果歸檔為新資產
  Future<StepArchiveResult> archiveStepResult({
    required String doorId,
    required String stepId,
    required String resultSummary,
    DigitalAssetKind kind = DigitalAssetKind.projectPlaybook,
    List<String> tags = const [],
  }) async {
    final all = await _doorStore.loadAll();
    final door = all.where((d) => d.id == doorId).firstOrNull;
    if (door == null) {
      return const StepArchiveResult(message: '門不存在');
    }
    final step = door.flowSteps.where((s) => s.id == stepId).firstOrNull;
    if (step == null) {
      return const StepArchiveResult(message: '步驟不存在');
    }

    // 歸檔為新資產
    final asset = await _assetStore.registerAsset(
      title: '${door.title} — ${step.title}（產出）',
      kind: kind,
      summary: resultSummary,
      sourceProjectDoorId: doorId,
      sourceLabel: door.title,
      capabilities: door.requiredBridges,
      tags: ['步驟產出', step.title, ...tags],
      reusableByProjects: true,
      reusableByAgents: true,
    );

    // 將步驟標記為完成
    await _doorStore.updateFlowStep(doorId, stepId, status: FlowStep.statusDone);

    return StepArchiveResult(
      newAssetId: asset.id,
      message: '已歸檔為資產「${asset.title}」',
    );
  }

  // ═══════════════════════════════════════════════════════
  // 4. 查詢已連結資產
  // ═══════════════════════════════════════════════════════

  /// 取得門已連結的完整資產物件列表
  Future<List<DigitalAsset>> getLinkedAssets(ProjectDoor door) async {
    if (door.linkedAssetIds.isEmpty) return const [];
    final all = await _assetStore.getAll();
    final idSet = door.linkedAssetIds.toSet();
    return all.where((a) => idSet.contains(a.id)).toList();
  }

  /// 取得步驟已連結的完整資產物件列表
  Future<List<DigitalAsset>> getStepAssets(
    ProjectDoor door,
    String stepId,
  ) async {
    final step = door.flowSteps.where((s) => s.id == stepId).firstOrNull;
    if (step == null || step.linkedAssetIds.isEmpty) return const [];
    final all = await _assetStore.getAll();
    final idSet = step.linkedAssetIds.toSet();
    return all.where((a) => idSet.contains(a.id)).toList();
  }

  /// 解除資產連結
  Future<ProjectDoor?> unlinkAsset(String doorId, String assetId) async {
    final all = await _doorStore.loadAll();
    final index = all.indexWhere((d) => d.id == doorId);
    if (index < 0) return null;
    final door = all[index];

    // 從門級移除
    final doorAssets = door.linkedAssetIds.where((id) => id != assetId).toList();
    // 從步驟級移除
    final newSteps = door.flowSteps.map((step) {
      final stepAssets = step.linkedAssetIds.where((id) => id != assetId).toList();
      return step.copyWith(linkedAssetIds: stepAssets);
    }).toList();

    final updated = door.copyWith(
      linkedAssetIds: doorAssets,
      flowSteps: newSteps,
      updatedAt: DateTime.now(),
    );
    all[index] = updated;
    await _doorStore.saveActive(updated);
    return updated;
  }
}
