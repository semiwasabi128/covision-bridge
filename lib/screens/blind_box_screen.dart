import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../models/companion.dart';
import '../services/companion_store.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

/// 🎲 抽盲盒界面
/// 驚喜感：隨機動畫 → 專屬夥伴揭曉
class BlindBoxScreen extends StatefulWidget {
  const BlindBoxScreen({super.key});

  @override
  State<BlindBoxScreen> createState() => _BlindBoxScreenState();
}

enum _Phase { ready, shaking, revealing, generating, done }

class _BlindBoxScreenState extends State<BlindBoxScreen>
    with TickerProviderStateMixin {
  late AnimationController _shakeController;
  late AnimationController _pulseController;
  late AnimationController _floatController;

  _Phase _phase = _Phase.ready;
  Companion? _companion;

  final _firstNames = [
    '晨曦',
    '星野',
    '雲深',
    '墨染',
    '風息',
    '露西',
    '琥珀',
    '靈溪',
    '霜華',
    '焰心',
    '鹿鳴',
    '竹音',
    '海月',
    '山嵐',
    '雨桐',
  ];
  final _titles = [
    '行者',
    '守護者',
    '編織者',
    '探索者',
    '觀星者',
    '旅人',
    '引路人',
    '守望者',
    '傳信者',
    '築夢者',
  ];

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pulseController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.shaking);
    await _shakeController.forward(from: 0);

    setState(() => _phase = _Phase.revealing);
    await Future.delayed(const Duration(seconds: 1));

    // 隨機生成夥伴
    final r = Random();
    final name =
        '${_firstNames[r.nextInt(_firstNames.length)]}'
        '${_titles[r.nextInt(_titles.length)]}';
    final mbti = MBTIType.allTypes[r.nextInt(MBTIType.allTypes.length)];
    final roles = CompanionRole.values;
    final role = roles[r.nextInt(roles.length)];
    final tags = [
      PersonalityTag.warm,
      PersonalityTag.concise,
      PersonalityTag.humorous,
      PersonalityTag.precise,
    ];

    _companion = Companion(
      id: CompanionStore.generateId(),
      name: name,
      mbtiCode: mbti.code,
      role: role,
      personalityTags: [tags[r.nextInt(tags.length)]],
      // [教練 Agent 2026-08-04] appearanceSeed 已刪除
      // appearanceSeed: r.nextInt(10000),
      appearancePrompt: '根據 ${mbti.name} 的 ${mbti.code} 性格生成的專屬形象',
      appearanceDescription:
          '${mbti.name}風格的幾何光點，帶有${mbti.colorHex}色調，會隨著對話節奏輕微脈動',
    );

    setState(() => _phase = _Phase.generating);
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _phase = _Phase.done);
    }
  }

  Future<void> _saveAndGo() async {
    if (_companion == null) return;
    await CompanionStore().add(_companion!);
    await CompanionStore().setActive(_companion!.id);
    if (mounted) context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return AdaptiveScaffold(
      backgroundColor: ds.canvas,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.2,
            colors: [Color(0xFF1A1A3E), Color(0xFF0D0D1A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_phase) {
      case _Phase.ready:
        return _buildReady();
      case _Phase.shaking:
        return _buildShaking();
      case _Phase.revealing:
        return _buildRevealing();
      case _Phase.generating:
        return _buildGenerating();
      case _Phase.done:
        return _buildDone();
    }
  }

  Widget _buildReady() {
    final ds = BridgeDSColors.of(context);
    return Column(
      key: const ValueKey('ready'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '🎁',
          style: TierStyle.of(context, Tier.ceremonyHeroEmoji).toTextStyle(),
        ),
        const SizedBox(height: 24),
        Text(
          '神秘夥伴盲盒',
          style: TierStyle.of(context, Tier.ceremonyHeroTitle).toTextStyle(),
        ),
        const SizedBox(height: 12),
        Text(
          '打開它，遇見你的專屬 AI 夥伴',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textTertiary),
        ),
        const SizedBox(height: 48),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) => Transform.scale(
            scale: 1.0 + 0.05 * _pulseController.value,
            child: ElevatedButton(
              onPressed: _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: ds.accentYellow,
                foregroundColor: ds.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 56,
                  vertical: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                elevation: 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_fix_high, size: 22),
                  SizedBox(width: 10),
                  Text(
                    '開 啟',
                    style: TierStyle.of(context, Tier.ceremonyCta).toTextStyle(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShaking() {
    final ds = BridgeDSColors.of(context);
    return AnimatedBuilder(
      key: const ValueKey('shaking'),
      animation: _shakeController,
      builder: (context, child) {
        final shake = sin(_shakeController.value * 4 * pi) * 12;
        final scale = 1.0 + _shakeController.value * 0.1;
        return Transform.translate(
          offset: Offset(shake, 0),
          child: Transform.scale(
            scale: scale,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: ds.accentYellow,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: ds.accentYellow.withValues(alpha: 0.5),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text('🎁', style: TierStyle.of(context, Tier.ceremonyHeroEmoji).toTextStyle().copyWith(fontSize: 60)),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  '召喚中...',
                  style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(color: ds.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRevealing() {
    final ds = BridgeDSColors.of(context);
    return Column(
      key: const ValueKey('revealing'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: ds.textPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: ds.textPrimary.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
          child: Center(
            child: CircularProgressIndicator(color: ds.textSecondary),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          '正在穿越數位次元...',
          style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: ds.textSecondary),
        ),
      ],
    );
  }

  Widget _buildGenerating() {
    final ds = BridgeDSColors.of(context);
    return Column(
      key: const ValueKey('generating'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: ds.accentBlue,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '正在為你的夥伴繪製形象...',
          style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: ds.textPrimary),
        ),
        const SizedBox(height: 8),
        Text(
          '這可能需要幾秒鐘',
          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textTertiary),
        ),
      ],
    );
  }

  Widget _buildDone() {
    if (_companion == null) return const SizedBox.shrink();

    final ds = BridgeDSColors.of(context);
    final mbti = _companion!.mbtiType;
    final color = mbti != null
        ? Color(int.parse(mbti.colorHex.replaceFirst('#', '0xFF')))
        : AppTheme.primary;

    return AnimatedBuilder(
      key: const ValueKey('done'),
      animation: _floatController,
      builder: (context, child) {
        final float = sin(_floatController.value * 2 * pi) * 8;

        return Transform.translate(
          offset: Offset(0, float),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 稀有度標籤
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 14, color: color),
                    const SizedBox(width: 4),
                    Text(
                      '專屬夥伴',
                      style: TierStyle.of(context, Tier.cardCaptionBold).toTextStyle().copyWith(color: color,
                        fontWeight: FontWeight.bold,),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 形象（幾何頭像）
              _buildAvatar(color, mbti?.code ?? '??'),
              const SizedBox(height: 24),

              // 名字
              Text(
                _companion!.name,
                style: TierStyle.of(context, Tier.appDisplayLarge).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                  color: Colors.white,),
              ),
              const SizedBox(height: 8),

              // MBTI + Role
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_companion!.roleName} • ${_companion!.mbtiCode}',
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: color),
                ),
              ),
              const SizedBox(height: 16),

              // 描述
              if (mbti != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    mbti.description,
                    textAlign: TextAlign.center,
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white.withValues(alpha: 0.7),
                      height: 1.6,),
                  ),
                ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _companion!.appearanceDescription,
                  textAlign: TextAlign.center,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white.withValues(alpha: 0.5),),
                ),
              ),
              const SizedBox(height: 40),

              // 開始按鈕
              ElevatedButton(
                onPressed: _saveAndGo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ds.canvas,
          side: BorderSide(color: ds.accentPurple, width: 1.5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 56,
                    vertical: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 18),
                    SizedBox(width: 8),
                    Text(
                      '開始對話',
                      style: TierStyle.of(context, Tier.ceremonyCallToAction).toTextStyle(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(Color color, String code) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.6), color.withValues(alpha: 0.2)],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 40,
            spreadRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.3),
                    Colors.white.withValues(alpha: 0.1),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  code.substring(0, 2),
                  style: TierStyle.of(context, Tier.ceremonyCode).toTextStyle(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              code,
              style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: Colors.white.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,),
            ),
          ],
        ),
      ),
    );
  }
}
