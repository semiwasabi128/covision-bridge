// lib/services/companion_certification/certification_keywords.dart
//
// [教練 Agent 2026-08-05] 夥伴合規檢查關鍵字常數集
//
// 從 `semi_dao_review_store.dart` 拆出，原本是 private static const。
// 改為公開常數，未來維護（新增 / 移除 / 多語系）更容易，
// 也能在 lint / 測試層級強制引用。
//
// ⚠️ 注意：這些是「合規檢查」的詞庫，未來若要擴充（例如日文 / 韓文 / 英文俚語），
// 請保持各類別的關鍵字純度，不要混入其他類別。

/// 18 禁 / 成人內容關鍵字（含中英文常見寫法）
const List<String> adultKeywords = <String>[
  '18禁',
  '成人內容',
  '成人向',
  '色情',
  '裸露',
  'nsfw',
  'porn',
  'sexual',
];

/// 官方授權 / 官方聯名 / 官方混淆關鍵字
const List<String> officialConfusionKeywords = <String>[
  '官方授權',
  '官方合作',
  '官方聯名',
  '官方角色',
  '官方版',
  '官方出品',
  '正版授權',
  '正版聯名',
  '正版角色',
  'official',
  'licensed',
  'authorized by',
];

/// 醜化 / 貶損 / 仇恨 / 攻擊原作關鍵字
const List<String> disparagementKeywords = <String>[
  '醜化',
  '侮辱',
  '羞辱',
  '貶損',
  '仇恨',
  '攻擊原作',
  '攻擊人物',
  '惡搞原作',
  'disparage',
  'hate',
];

/// 具名 IP / 工作室 / 創作者風格關鍵字（公開分享前需人工確認）
const List<String> knownIpKeywords = <String>[
  '吉卜力',
  '宮崎駿',
  'ghibli',
  'miyazaki',
  '迪士尼',
  'disney',
  '皮克斯',
  'pixar',
  '寶可夢',
  'pokemon',
  '任天堂',
  'nintendo',
  'marvel',
  'dc comics',
  'star wars',
];