// lib/theme/tier.dart
//
// [教練 Agent 2026-08-05] Tier enum — 33 個語意化設計層級
//
// 對應 docs/BRIDGE_TIER_SYSTEM.md v1.0
//
// 使用範例：
//   final style = TierStyle.of(context, Tier.list.item.title);
//
// 防呆：
//   1. Tier 是 enum，新增/刪除必須明確宣告
//   2. TierStyle 內部會對照 manifest，未定義的 tier → throw
//   3. TierStyle.textColor 只接受 String token 名，不接受 Color

import 'package:flutter/foundation.dart';

/// Bridge Tier — 33 個語意化設計層級
///
/// 每個 Tier 對應 manifest 內一筆設定（含 textColor/fontSize/fontWeight/fontFamily 等）
@immutable
class Tier {
  final String _key;
  final String _namespace;
  final String _element;
  final String _role;
  final String? _variant;

  const Tier._({
    required String key,
    required String namespace,
    required String element,
    required String role,
    String? variant,
  }) : _key = key,
       _namespace = namespace,
       _element = element,
       _role = role,
       _variant = variant;

  /// 完整識別字串（與 manifest 對應），例如 "list.item.title"
  String get key => _key;

  /// 命名空間，例如 "list"
  String get namespace => _namespace;

  /// 元素類型，例如 "item"
  String get element => _element;

  /// layout 角色，例如 "title"
  String get role => _role;

  /// 變體（選用），例如 "hover" / "selected" / "disabled"
  String? get variant => _variant;

  /// 判斷這個 tier 是不是某個類別的 instance
  bool isIn(String ns) => _namespace == ns;

  @override
  String toString() => 'Tier($_key)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Tier && other._key == _key);

  @override
  int get hashCode => _key.hashCode;

  // ===========================================================================
  // App 全域層級
  // ===========================================================================

  /// App 大標題（頁面 H1）
  static const Tier appTitle = Tier._(
    key: 'app.title',
    namespace: 'app',
    element: 'title',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 A 推廣] App 顯示大標題（32/w400）— 對應舊 headingL
  static const Tier appDisplayLarge = Tier._(
    key: 'app.displayLarge',
    namespace: 'app',
    element: 'displayLarge',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 A 推廣] App 標題（24/w500）— 對應舊 headingM
  static const Tier appHeadline = Tier._(
    key: 'app.headline',
    namespace: 'app',
    element: 'headline',
    role: 'primary',
  );

  /// App 副標題（頁面 H2）
  static const Tier appSubtitle = Tier._(
    key: 'app.subtitle',
    namespace: 'app',
    element: 'subtitle',
    role: 'primary',
  );

  // ===========================================================================
  // Sidebar / 導覽列
  // ===========================================================================

  /// sidebar 列表項主文字
  static const Tier sidebarRowTitle = Tier._(
    key: 'sidebar.row.title',
    namespace: 'sidebar',
    element: 'row',
    role: 'title',
  );

  /// sidebar 列表項副文字
  static const Tier sidebarRowSubtitle = Tier._(
    key: 'sidebar.row.subtitle',
    namespace: 'sidebar',
    element: 'row',
    role: 'subtitle',
  );

  /// sidebar 列表項 metadata（時間、tag）
  static const Tier sidebarRowMeta = Tier._(
    key: 'sidebar.row.meta',
    namespace: 'sidebar',
    element: 'row',
    role: 'meta',
  );

  // ===========================================================================
  // Card / 卡片
  // ===========================================================================

  /// 卡片標題
  static const Tier cardTitle = Tier._(
    key: 'card.title',
    namespace: 'card',
    element: 'title',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 A 推廣] 卡片大標題（20/w500）— 對應舊 headingS
  static const Tier cardHeroTitle = Tier._(
    key: 'card.heroTitle',
    namespace: 'card',
    element: 'heroTitle',
    role: 'primary',
  );

  /// 卡片內文
  static const Tier cardBody = Tier._(
    key: 'card.body',
    namespace: 'card',
    element: 'body',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 A 推廣] 主要內文（18/w400）— 對應舊 bodyL
  static const Tier bodyPrimary = Tier._(
    key: 'body.primary',
    namespace: 'body',
    element: 'primary',
    role: 'primary',
  );

  // ===========================================================================
  // Ceremony / 儀式場景（盲盒召喚、慶祝動畫）
  // ===========================================================================

  /// [教練 Agent 2026-08-05 階段 B 推廣] 儀式場景大標題（28/w700）— 召喚夥伴成功標題
  static const Tier ceremonyHeroTitle = Tier._(
    key: 'ceremony.heroTitle',
    namespace: 'ceremony',
    element: 'heroTitle',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 B 推廣] 儀式場景 hero emoji（80/w400）— 🎁 視覺衝擊
  static const Tier ceremonyHeroEmoji = Tier._(
    key: 'ceremony.heroEmoji',
    namespace: 'ceremony',
    element: 'heroEmoji',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 B 推廣] 儀式場景 CTA 按鈕（letterSpacing: 4）— 「開 啟」儀式感
  static const Tier ceremonyCta = Tier._(
    key: 'ceremony.cta',
    namespace: 'ceremony',
    element: 'cta',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 B 推廣] 儀式場景 callToAction（letterSpacing: 2）— 「開始對話」CTA
  static const Tier ceremonyCallToAction = Tier._(
    key: 'ceremony.callToAction',
    namespace: 'ceremony',
    element: 'callToAction',
    role: 'primary',
  );

  /// [教練 Agent 2026-08-05 階段 B 推廣] 儀式場景召喚碼（28/w900）— 神秘數字視覺
  static const Tier ceremonyCode = Tier._(
    key: 'ceremony.code',
    namespace: 'ceremony',
    element: 'code',
    role: 'primary',
  );

  /// 卡片註腳（小字）
  static const Tier cardCaption = Tier._(
    key: 'card.caption',
    namespace: 'card',
    element: 'caption',
    role: 'primary',
  );
  // [教練 Agent 2026-08-05] Step 4 推廣 — 加重 caption 變體
  static const Tier cardCaptionHeavy = Tier._(
    key: 'card.caption.heavy',
    namespace: 'card',
    element: 'caption',
    role: 'heavy',
  );
  static const Tier cardCaptionBold = Tier._(
    key: 'card.caption.bold',
    namespace: 'card',
    element: 'caption',
    role: 'bold',
  );
  static const Tier cardCaptionEmphasized = Tier._(
    key: 'card.caption.emphasized',
    namespace: 'card',
    element: 'caption',
    role: 'emphasized',
  );

  // ===========================================================================
  // List item / 列表項
  // ===========================================================================

  /// 列表項主文字
  static const Tier listItemTitle = Tier._(
    key: 'list.item.title',
    namespace: 'list',
    element: 'item',
    role: 'title',
  );

  /// 列表項副文字
  static const Tier listItemSubtitle = Tier._(
    key: 'list.item.subtitle',
    namespace: 'list',
    element: 'item',
    role: 'subtitle',
  );

  /// 列表項 metadata
  static const Tier listItemMeta = Tier._(
    key: 'list.item.meta',
    namespace: 'list',
    element: 'item',
    role: 'meta',
  );

  // ===========================================================================
  // Form / 表單
  // ===========================================================================

  /// 表單欄位 label
  static const Tier formLabel = Tier._(
    key: 'form.label',
    namespace: 'form',
    element: 'label',
    role: 'primary',
  );

  /// 表單輸入文字
  static const Tier formInput = Tier._(
    key: 'form.input',
    namespace: 'form',
    element: 'input',
    role: 'primary',
  );

  /// 表單 helper text
  static const Tier formHelper = Tier._(
    key: 'form.helper',
    namespace: 'form',
    element: 'helper',
    role: 'primary',
  );

  // ===========================================================================
  // Dialog / 對話框
  // ===========================================================================

  /// 對話框標題
  static const Tier dialogTitle = Tier._(
    key: 'dialog.title',
    namespace: 'dialog',
    element: 'title',
    role: 'primary',
  );

  /// 對話框內文
  static const Tier dialogBody = Tier._(
    key: 'dialog.body',
    namespace: 'dialog',
    element: 'body',
    role: 'primary',
  );

  // ===========================================================================
  // Button / 按鈕
  // ===========================================================================

  /// 主按鈕文字
  static const Tier buttonPrimary = Tier._(
    key: 'button.primary',
    namespace: 'button',
    element: 'primary',
    role: 'primary',
  );

  /// 次按鈕文字
  static const Tier buttonSecondary = Tier._(
    key: 'button.secondary',
    namespace: 'button',
    element: 'secondary',
    role: 'primary',
  );

  // ===========================================================================
  // Status / 狀態色
  // ===========================================================================

  /// 成功（綠）
  static const Tier statusSuccess = Tier._(
    key: 'status.success',
    namespace: 'status',
    element: 'success',
    role: 'primary',
  );

  /// 警告（黃）
  static const Tier statusWarning = Tier._(
    key: 'status.warning',
    namespace: 'status',
    element: 'warning',
    role: 'primary',
  );

  /// 錯誤（紅）
  static const Tier statusError = Tier._(
    key: 'status.error',
    namespace: 'status',
    element: 'error',
    role: 'primary',
  );

  /// 資訊（藍）
  static const Tier statusInfo = Tier._(
    key: 'status.info',
    namespace: 'status',
    element: 'info',
    role: 'primary',
  );

  // ===========================================================================
  // Background / 背景角色（用於 Container）
  // ===========================================================================

  /// 視窗主背景
  static const Tier bgPanelBase = Tier._(
    key: 'bg.panel.base',
    namespace: 'bg',
    element: 'panel',
    role: 'base',
  );

  /// 卡片表面（亮一級）
  static const Tier bgPanelElevated = Tier._(
    key: 'bg.panel.elevated',
    namespace: 'bg',
    element: 'panel',
    role: 'elevated',
  );

  /// hover 狀態（亮更多）
  static const Tier bgPanelHover = Tier._(
    key: 'bg.panel.hover',
    namespace: 'bg',
    element: 'panel',
    role: 'hover',
  );

  /// selected 狀態（強調色背景）
  static const Tier bgPanelSelected = Tier._(
    key: 'bg.panel.selected',
    namespace: 'bg',
    element: 'panel',
    role: 'selected',
  );

  // ===========================================================================
  // Border / 邊框
  // ===========================================================================

  /// 細線
  static const Tier borderSubtle = Tier._(
    key: 'border.subtle',
    namespace: 'border',
    element: 'subtle',
    role: 'primary',
  );

  /// 一般
  static const Tier borderDefault = Tier._(
    key: 'border.default',
    namespace: 'border',
    element: 'default',
    role: 'primary',
  );

  /// 強調
  static const Tier borderStrong = Tier._(
    key: 'border.strong',
    namespace: 'border',
    element: 'strong',
    role: 'primary',
  );

  // ===========================================================================
  // [教練 Agent 2026-08-05] Step 4 推廣 — Wizard 特定 tier
  // ===========================================================================

  /// Wizard 步驟摘要（顯示在 Stepper subtitle）
  static const Tier stepSummary = Tier._(
    key: 'step.summary',
    namespace: 'step',
    element: 'summary',
    role: 'primary',
  );

  /// Wizard 區塊標題（中等大小，比 card.title 略大）
  static const Tier blockHeading = Tier._(
    key: 'block.heading',
    namespace: 'block',
    element: 'heading',
    role: 'primary',
  );

  /// Wizard 區塊副標（小標題，比 card.title 小）
  static const Tier blockSubheading = Tier._(
    key: 'block.subheading',
    namespace: 'block',
    element: 'subheading',
    role: 'primary',
  );

  /// 數字強調（夥伴計數、X 圖等）
  static const Tier numericEmphasis = Tier._(
    key: 'numeric.emphasis',
    namespace: 'numeric',
    element: 'emphasis',
    role: 'primary',
  );

  /// 全部 33 個 tier（用於測試 + 完整性檢查）
  static const List<Tier> all = [
    appTitle,
    appDisplayLarge,
    appHeadline,
    appSubtitle,
    sidebarRowTitle,
    sidebarRowSubtitle,
    sidebarRowMeta,
    cardTitle,
    cardHeroTitle, // [教練 Agent 2026-08-05] Step 4 推廣（補註冊到 all）
    cardBody,
    cardCaption,
    cardCaptionHeavy, // [教練 Agent 2026-08-05] Step 4 推廣
    cardCaptionBold, // [教練 Agent 2026-08-05] Step 4 推廣
    cardCaptionEmphasized, // [教練 Agent 2026-08-05] Step 4 推廣
    stepSummary, // [教練 Agent 2026-08-05] Step 4 推廣
    blockHeading, // [教練 Agent 2026-08-05] Step 4 推廣
    blockSubheading, // [教練 Agent 2026-08-05] Step 4 推廣
    numericEmphasis, // [教練 Agent 2026-08-05] Step 4 推廣
    bodyPrimary,
    ceremonyHeroTitle,
    ceremonyHeroEmoji,
    ceremonyCta,
    ceremonyCallToAction,
    ceremonyCode,
    listItemTitle,
    listItemSubtitle,
    listItemMeta,
    formLabel,
    formInput,
    formHelper,
    dialogTitle,
    dialogBody,
    buttonPrimary,
    buttonSecondary,
    statusSuccess,
    statusWarning,
    statusError,
    statusInfo,
    bgPanelBase,
    bgPanelElevated,
    bgPanelHover,
    bgPanelSelected,
    borderSubtle,
    borderDefault,
    borderStrong,
  ];

  /// 用 key 查找 Tier（manifest 載入時反查）
  static Tier? fromKey(String key) {
    for (final t in all) {
      if (t.key == key) return t;
    }
    return null;
  }
}
