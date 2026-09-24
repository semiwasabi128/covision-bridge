// [教練 Agent Sprint 17 Step 7 2026-07-07]
// 訊息卡片解析函數 — 從 chat_screen.dart 提取的純函數。
// 嘗試從訊息內容字串解析出各種卡片資料結構。
import 'dart:convert';

import '../../../models/chat_card_data.dart';

DigitalAssetInvocationCardData? tryParseDigitalAssetInvocationCard(
  String content,
) {
  if (!content.startsWith(digitalAssetInvocationCardPrefix)) return null;
  try {
    final jsonText = content.substring(digitalAssetInvocationCardPrefix.length);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return DigitalAssetInvocationCardData.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

DigitalAssetReusePlanCardData? tryParseDigitalAssetReusePlanCard(
  String content,
) {
  if (!content.startsWith(digitalAssetReusePlanCardPrefix)) return null;
  try {
    final jsonText = content.substring(digitalAssetReusePlanCardPrefix.length);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return DigitalAssetReusePlanCardData.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

DigitalAssetResultCardData? tryParseDigitalAssetResultCard(String content) {
  if (!content.startsWith(digitalAssetResultCardPrefix)) return null;
  try {
    final jsonText = content.substring(digitalAssetResultCardPrefix.length);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return DigitalAssetResultCardData.fromJson(decoded);
  } catch (_) {
    return null;
  }
}

ManagedFolderRulePickerCardData? tryParseManagedFolderRulePickerCard(
  String content,
) {
  if (!content.startsWith(managedFolderRulePickerCardPrefix)) return null;
  try {
    final jsonText = content.substring(managedFolderRulePickerCardPrefix.length);
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return null;
    return ManagedFolderRulePickerCardData.fromJson(decoded);
  } catch (_) {
    return null;
  }
}
