// [教練 Agent Sprint 17 Step 7 — 2026-07-07]
// AppBar 相關 UI：模型切換 sheet、夥伴選擇 sheet、AppBar 標題。
// 從 chat_screen.dart 抽取，行為不變。
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/agent_activity.dart';
import '../../../models/companion.dart';
import '../../../services/bridge_media_store.dart';
import '../../../services/companion_store.dart';
import '../../../services/storage_service.dart';
import '../../../services/provider_registry.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/companion_avatar_image.dart';
import '../../../theme/tier.dart';
import '../../../theme/tier_style.dart';
import '../../../theme/bridge_design_system.dart';

/// 顯示模型切換 bottom sheet，回傳選中的 provider key。
/// 調用方負責 saveProvider + setState。
Future<String?> showModelSwitcherSheet(BuildContext context) async {
  const providers = <String, String>{
    'openai': 'OpenAI (GPT-4o)',
    'glm': 'GLM (智譜)',
    'kimi': 'Kimi (月之暗面)',
    'minimax': 'MiniMax',
    'gemini': 'Gemini (Google)',
    'claude': 'Claude (Anthropic)',
  };
  const order = ['openai', 'glm', 'kimi', 'minimax', 'gemini', 'claude'];

  // 只顯示有 token 的 provider
  final available = <MapEntry<String, String>>[];
  for (final p in order) {
    final token = await StorageService.getToken(provider: p);
    if (token != null && token.trim().isNotEmpty) {
      available.add(MapEntry(p, providers[p]!));
    }
  }
  // 也檢查預設 token（未指定 provider）
  final defaultToken = await StorageService.getToken();
  if (defaultToken != null && defaultToken.trim().isNotEmpty) {
    final currentProvider = await StorageService.getProvider() ?? 'openai';
    if (!available.any((e) => e.key == currentProvider)) {
      available.insert(0, MapEntry(currentProvider, providers[currentProvider] ?? currentProvider));
    }
  }

  if (!context.mounted) return null;
  if (available.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('尚未設定任何 API Token，請先到設定頁面設定。')),
    );
    return null;
  }

  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '切換模型',
                style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ...available.map((entry) {
              return ListTile(
                leading: const Icon(Icons.smart_toy_outlined),
                title: Text(entry.value),
                onTap: () => Navigator.of(sheetContext).pop(entry.key),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

/// 顯示夥伴選擇 bottom sheet。
/// [onSelected] 在使用者選中夥伴時呼叫，調用方負責 setState。
void showCompanionSelectorSheet(
  BuildContext context, {
  required String? activeCompanionId,
  required void Function(Companion companion) onSelected,
}) {
  final companions = CompanionStore().all;
  if (companions.isEmpty) {
    context.go('/companion/create');
    return;
  }

  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '切換夥伴',
                    style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(fontWeight: FontWeight.bold,),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      context.go('/companions');
                    },
                    icon: const Icon(Icons.people, size: 18),
                    label: const Text('管理'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...companions.map((c) {
              final mbti = c.mbtiType;
              final color = mbti != null
                  ? Color(int.parse(mbti.colorHex.replaceFirst('#', '0xFF')))
                  : BridgeDS.successGreen;
              final isActive = c.id == activeCompanionId;

              return ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: 0.20)),
                  ),
                  child: Center(
                    child: ClipOval(
                      child: CompanionAvatarImage(
                        companion: c,
                        mbtiCode: c.mbtiCode,
                        seed: 0, // [教練 Agent 2026-08-04] appearanceSeed 已刪除
                        name: c.name,
                        mood: AgentCompanionMood.idle,
                        action: AgentCompanionAction.standing,
                        size: 36,
                        framed: false,
                      ),
                    ),
                  ),
                ),
                title: Text(c.name),
                subtitle: Text('${c.mbtiCode} · ${c.roleName}'),
                trailing: isActive
                    ? Icon(Icons.check_circle, color: BridgeDS.successGreen)
                    : null,
                onTap: () {
                  CompanionStore().setActive(c.id);
                  onSelected(c);
                  Navigator.pop(sheetContext);
                },
              );
            }),
            const SizedBox(height: 8),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: BridgeDS.successGreen,
                child: Icon(Icons.add, color: BridgeDS.textOnAccent),
              ),
              title: const Text('創造新夥伴'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.go('/companion/create');
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

/// 建置 AppBar 標題，顯示當前對話標題與夥伴名稱。
Widget buildAppBarTitle(
  BuildContext context, {
  required String? conversationTitle,
  required Companion? activeCompanion,
  required String currentMode,
  required VoidCallback onTapCompanion,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        conversationTitle ?? '橋樑',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle(),
      ),
      GestureDetector(
        onTap: onTapCompanion,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              activeCompanion != null
                  ? '${activeCompanion.name} · 夥伴列表'
                  : '夥伴 · $currentMode',
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.normal,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.9)
                    : Colors.black.withValues(alpha: 0.7),),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.black.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    ],
  );
}

/// [Sprint 17 Step 7] 模型切換按鈕，顯示當前 provider 並可切換。
/// [onChanged] 在切換後呼叫，調用方負責 setState。
Widget buildModelSwitchButton(
  BuildContext context, {
  required VoidCallback onChanged,
}) {
  return FutureBuilder<String?>(
    future: StorageService.getProvider(),
    builder: (context, snapshot) {
      final provider = snapshot.data ?? 'openai';
      const providerLabels = {
        'openai': 'GPT-4o',
        'glm': 'GLM',
        'kimi': 'Kimi',
        'minimax': 'MiniMax',
        'gemini': 'Gemini',
        'claude': 'Claude',
      };
      final label = providerLabels[provider] ?? provider;
      return TextButton.icon(
        onPressed: () async {
          final selected = await showModelSwitcherSheet(context);
          if (selected != null) {
            await StorageService.saveProvider(selected);
            // [教練 Agent 2026-08-12] 同步更新 gateway URL + model
            // 使用 ProviderRegistry.baseUrlOf() 取代遺失的 _defaultUrlForProvider()
            final gatewayUrl = selected != 'default'
                ? ProviderRegistry.baseUrlOf(selected)
                : null;
            await StorageService.saveProviderConfig(
              selected,
              gatewayUrl,
            );
            onChanged();
          }
        },
        icon: Text(
          label,
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,),
        ),
        label: const Icon(Icons.arrow_drop_down, size: 18),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    },
  );
}

/// [Sprint 17 Step 7] 文件預覽對話框。
void showDocumentPreviewDialog(BuildContext context, String path) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.description_outlined, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('文件預覽'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: FutureBuilder<String>(
            future: BridgeMediaStore.readMarkdownDocument(path),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return SelectableText('讀取文件失敗：${snapshot.error}');
              }
              return SingleChildScrollView(
                child: SelectableText(
                  snapshot.data ?? '',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(height: 1.45),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('關閉'),
          ),
        ],
      );
    },
  );
}

/// [Sprint 17 Step 7] 夥伴切換 picker sheet（對話中模糊換夥伴偵測用）。
void showCompanionPickerSheet(
  BuildContext context, {
  required List<Companion> companions,
  required String? autoTargetId,
  required void Function(Companion companion) onSelected,
  required VoidCallback onDismissed,
}) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => ListView(
      shrinkWrap: true,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('選擇要切換的夥伴', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        ...companions.map((c) {
          final isAutoSelected = autoTargetId != null && c.id == autoTargetId;
          return ListTile(
            tileColor: isAutoSelected ? Colors.blue.withValues(alpha: 0.15) : null,
            title: Text(c.name),
            trailing: isAutoSelected
                ? const Icon(Icons.check_circle, color: BridgeDS.blue500, size: 18)
                : null,
            subtitle: c.systemPrompt.isNotEmpty
              ? Text(
                  c.systemPrompt.length > 40
                    ? '${c.systemPrompt.substring(0, 40)}...'
                    : c.systemPrompt,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white54),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
            onTap: () {
              Navigator.pop(ctx);
              onSelected(c);
            },
          );
        }),
      ],
    ),
  ).then((_) {
    onDismissed();
  });
}
