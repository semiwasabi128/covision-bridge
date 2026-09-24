import 'package:shared_preferences/shared_preferences.dart';

/// [教練 Agent 2026-07-31] 計費模式管理
/// 資料驅動設計：provider 支援哪些計費模式由 billingModesMap 決定
/// 未來新 provider 開放月訂時，只需更新 _defaultBillingModes

class BillingMode {
  final String id;
  final String label;
  final String baseUrl;

  const BillingMode({
    required this.id,
    required this.label,
    required this.baseUrl,
  });

  factory BillingMode.fromJson(Map<String, dynamic> json) => BillingMode(
        id: json['id'] as String,
        label: json['label'] as String,
        baseUrl: json['base_url'] as String,
      );
}

class BillingModes {
  BillingModes._();

  /// 預設計費模式表
  /// 只有 provider 有 >1 個 mode 時，UI 才顯示 toggle
  static const Map<String, Map<String, dynamic>> _defaultBillingModes = {
    'glm': {
      'modes': {
        'payg': {
          'id': 'payg',
          'label': '💰 按量計費',
          'base_url': 'https://open.bigmodel.cn/api/paas/v4',
        },
        'coding': {
          'id': 'coding',
          'label': '📦 Coding Plan 月訂',
          'base_url': 'https://api.z.ai/api/coding/paas/v4',
        },
      },
      'default': 'payg',
    },
    'gemini': {
      'modes': {
        'payg': {
          'id': 'payg',
          'label': '💰 按量計費',
          'base_url': 'https://generativelanguage.googleapis.com/v1beta/openai',
        },
      },
      'default': 'payg',
    },
    'claude': {
      'modes': {
        'payg': {
          'id': 'payg',
          'label': '💰 按量計費',
          'base_url': 'https://api.anthropic.com/v1',
        },
      },
      'default': 'payg',
    },
    'openai': {
      'modes': {
        'payg': {
          'id': 'payg',
          'label': '💰 按量計費',
          'base_url': 'https://api.openai.com/v1',
        },
      },
      'default': 'payg',
    },
    'kimi': {
      'modes': {
        'payg': {
          'id': 'payg',
          'label': '💰 按量計費',
          'base_url': 'https://api.moonshot.cn/v1',
        },
      },
      'default': 'payg',
    },
    'minimax': {
      'modes': {
        'payg': {
          'id': 'payg',
          'label': '💰 按量計費',
          'base_url': 'https://api.minimax.io/v1',
        },
      },
      'default': 'payg',
    },
  };

  /// 取得某 provider 的所有計費模式
  static List<BillingMode> getModes(String provider) {
    final config = _defaultBillingModes[provider];
    if (config == null) return [];
    final modes = config['modes'] as Map<String, dynamic>;
    return modes.values.map((m) => BillingMode.fromJson(m as Map<String, dynamic>)).toList();
  }

  /// 該 provider 是否有多個計費模式（UI 要不要顯示 toggle）
  static bool hasMultipleModes(String provider) {
    return getModes(provider).length > 1;
  }

  /// 取得預設計費模式 ID
  static String getDefaultModeId(String provider) {
    final config = _defaultBillingModes[provider];
    if (config == null) return 'payg';
    return config['default'] as String? ?? 'payg';
  }

  /// 取得使用者選的計費模式（從 SharedPreferences 讀）
  static Future<String> getSelectedModeId(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('billing_mode_$provider') ?? getDefaultModeId(provider);
  }

  /// 儲存使用者選的計費模式
  static Future<void> setSelectedModeId(String provider, String modeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('billing_mode_$provider', modeId);
  }

  /// 取得目前選的計費模式對應的 base_url
  static Future<String> getBaseUrl(String provider) async {
    final modeId = await getSelectedModeId(provider);
    final modes = getModes(provider);
    for (final m in modes) {
      if (m.id == modeId) return m.baseUrl;
    }
    // fallback: 用第一個 mode 的 base_url
    if (modes.isNotEmpty) return modes.first.baseUrl;
    // ultimate fallback: 空字串（讓 _defaultApiUrl 處理）
    return '';
  }

  /// 取得目前選的 BillingMode 物件
  static Future<BillingMode?> getSelectedMode(String provider) async {
    final modeId = await getSelectedModeId(provider);
    final modes = getModes(provider);
    for (final m in modes) {
      if (m.id == modeId) return m;
    }
    return modes.isNotEmpty ? modes.first : null;
  }
}