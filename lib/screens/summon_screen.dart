import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../models/companion.dart';
import 'blind_box_screen.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';

/// 🌌 橋樑召喚主界面
/// 設計圖風格：星空山脈背景 + 夥伴卡片輪播 + 發光 Summon 按鈕
class SummonScreen extends StatefulWidget {
  const SummonScreen({super.key});

  @override
  State<SummonScreen> createState() => _SummonScreenState();
}

class _SummonScreenState extends State<SummonScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _glowController;
  late AnimationController _floatController;
  int _currentIndex = 0;

  final List<_CompanionCardData> _cards = [
    _CompanionCardData(
      role: CompanionRole.research,
      name: '研究夥伴',
      icon: '🔬',
      gradient: const [Color(0xFF4CAF50), Color(0xFF81C784)],
      accent: const Color(0xFF2E7D32),
      description: '擅長深度研究、資料整理、趨勢分析',
    ),
    _CompanionCardData(
      role: CompanionRole.writing,
      name: '創意導師',
      icon: '🎨',
      gradient: const [Color(0xFFFF9800), Color(0xFFFFB74D)],
      accent: const Color(0xFFF57C00),
      description: '天馬行空、聯想豐富、幫你突破框架',
    ),
    _CompanionCardData(
      role: CompanionRole.translation,
      name: '數據分析師',
      icon: '📊',
      gradient: const [Color(0xFF2196F3), Color(0xFF64B5F6)],
      accent: const Color(0xFF1565C0),
      description: '邏輯嚴謹、善於拆解、找出盲點',
    ),
    _CompanionCardData(
      role: CompanionRole.farmManager,
      name: '生活教練',
      icon: '🌿',
      gradient: const [Color(0xFF8BC34A), Color(0xFFAED581)],
      accent: const Color(0xFF558B2F),
      description: '溫暖陪伴、善於傾聽、給予方向',
    ),
    _CompanionCardData(
      role: CompanionRole.custom,
      name: '策略家',
      icon: '♟️',
      gradient: const [Color(0xFF9C27B0), Color(0xFFBA68C8)],
      accent: const Color(0xFF6A1B9A),
      description: '大局觀、策略規劃、長期佈局',
    ),
    _CompanionCardData(
      role: CompanionRole.general,
      name: '建造者',
      icon: '🔨',
      gradient: const [Color(0xFF795548), Color(0xFFA1887F)],
      accent: const Color(0xFF4E342E),
      description: '動手實作、快速驗證、把想法落地',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.72);
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _glowController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  void _openBlindBox() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const BlindBoxScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final ds = BridgeDSColors.of(context);

    return Scaffold(
      body: Container(
        width: size.width,
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1117),
              Color(0xFF161B22),
              Color(0xFF1C2128),
              Color(0xFF0D1117),
            ],
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // ⭐ 星空
            CustomPaint(size: size, painter: _StarfieldPainter()),
            // ⛰️ 山脈
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: CustomPaint(
                size: Size(size.width, 180),
                painter: _MountainPainter(),
              ),
            ),
            // 主內容
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  // 標題
                  Text(
                    '橋 樑',
                    style: TierStyle.of(context, Tier.appTitle).toTextStyle().copyWith(fontWeight: FontWeight.w200,
                      color: ds.textPrimary,
                      letterSpacing: 20,),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '選擇你的 AI 夥伴',
                    style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textMuted,
                      letterSpacing: 4,),
                  ),
                  const SizedBox(height: 40),
                  // 卡片輪播
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (i) => setState(() => _currentIndex = i),
                      itemCount: _cards.length,
                      itemBuilder: (context, index) => _buildCard(index),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 分頁點
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _cards.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentIndex == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == i
                              ? ds.textPrimary
                              : ds.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Summon 按鈕
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: ds.accentBlue.withValues(
                              alpha: 0.3 + 0.4 * _glowController.value,
                            ),
                            blurRadius: 20 + 15 * _glowController.value,
                            spreadRadius: 2 + 3 * _glowController.value,
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _openBlindBox,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ds.canvas,
          side: BorderSide(color: ds.accentPurple, width: 1.5),
                          foregroundColor: ds.textPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
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
                              Icon(Icons.auto_fix_high, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'SUMMON',
                                style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                                  letterSpacing: 3,),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // 盲盒提示
                  GestureDetector(
                    onTap: _openBlindBox,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.casino, size: 16, color: ds.textTertiary),
                        const SizedBox(width: 6),
                        Text(
                          '或試試手氣，抽個盲盒夥伴',
                          style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textTertiary,),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 底部提示文字
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: Text(
                      '召喚你的夥伴',
                      style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary.withValues(alpha: 0.85),
                        letterSpacing: 1,),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(int index) {
    final card = _cards[index];
    final isCenter = index == _currentIndex;
    final ds = BridgeDSColors.of(context);

    return AnimatedBuilder(
      animation: _floatController,
      builder: (context, child) {
        final float = isCenter ? sin(_floatController.value * 2 * pi) * 6 : 0.0;

        return Transform.translate(
          offset: Offset(0, float),
          child: AnimatedScale(
            scale: isCenter ? 1.0 : 0.85,
            duration: const Duration(milliseconds: 300),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 40),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: card.gradient
                      .map((c) => c.withValues(alpha: isCenter ? 0.9 : 0.6))
                      .toList(),
                ),
                boxShadow: [
                  BoxShadow(
                    color: card.accent.withValues(alpha: isCenter ? 0.5 : 0.1),
                    blurRadius: isCenter ? 30 : 10,
                    spreadRadius: isCenter ? 4 : 0,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(
                  color: ds.canvas.withValues(alpha: isCenter ? 0.2 : 0.05),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  children: [
                    Positioned(
                      top: -40,
                      right: -40,
                      child: Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ds.canvas.withValues(alpha: 0.08),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
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
                                  ds.canvas.withValues(alpha: 0.3),
                                  ds.canvas.withValues(alpha: 0.1),
                                ],
                              ),
                              border: Border.all(
                                color: ds.canvas.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                card.icon,
                                style: TierStyle.of(context, Tier.appTitle).toTextStyle(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            card.name,
                            style: TierStyle.of(context, Tier.cardHeroTitle).toTextStyle().copyWith(fontWeight: FontWeight.bold,
                              color: ds.textPrimary,
                              letterSpacing: 1,),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            card.description,
                            textAlign: TextAlign.center,
                            style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary.withValues(alpha: 0.8),
                              height: 1.5,),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            alignment: WrapAlignment.center,
                            children: [
                              _buildTag('AI', card.accent),
                              _buildTag('專屬', card.accent),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTag(String label, Color color) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ds.canvas.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textPrimary.withValues(alpha: 0.9),),
      ),
    );
  }
}

class _CompanionCardData {
  final CompanionRole role;
  final String name;
  final String icon;
  final List<Color> gradient;
  final Color accent;
  final String description;

  const _CompanionCardData({
    required this.role,
    required this.name,
    required this.icon,
    required this.gradient,
    required this.accent,
    required this.description,
  });
}

// ===== 繪製器 =====

class _StarfieldPainter extends CustomPainter {
  final List<Offset> _stars;
  final List<double> _sizes;

  _StarfieldPainter()
    : _stars = List.generate(80, (_) {
        final r = Random();
        return Offset(r.nextDouble() * 2000, r.nextDouble() * 2000);
      }),
      _sizes = List.generate(80, (_) {
        final r = Random();
        return 0.5 + r.nextDouble() * 2.5;
      });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = BridgeDSColors.dark.textPrimary;
    for (var i = 0; i < _stars.length; i++) {
      final star = Offset(
        _stars[i].dx % size.width,
        _stars[i].dy % (size.height * 0.6),
      );
      canvas.drawCircle(star, _sizes[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MountainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final farPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.lineTo(size.width * 0.15, size.height * 0.2);
    path.lineTo(size.width * 0.3, size.height * 0.45);
    path.lineTo(size.width * 0.45, size.height * 0.1);
    path.lineTo(size.width * 0.6, size.height * 0.4);
    path.lineTo(size.width * 0.75, size.height * 0.15);
    path.lineTo(size.width * 0.9, size.height * 0.35);
    path.lineTo(size.width, size.height * 0.2);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, farPaint);

    final nearPaint = Paint()
      ..color = const Color(0xFF0D0D1A)
      ..style = PaintingStyle.fill;

    final nearPath = Path();
    nearPath.moveTo(0, size.height);
    nearPath.lineTo(0, size.height * 0.65);
    nearPath.lineTo(size.width * 0.2, size.height * 0.45);
    nearPath.lineTo(size.width * 0.4, size.height * 0.6);
    nearPath.lineTo(size.width * 0.55, size.height * 0.35);
    nearPath.lineTo(size.width * 0.75, size.height * 0.55);
    nearPath.lineTo(size.width * 0.9, size.height * 0.4);
    nearPath.lineTo(size.width, size.height * 0.65);
    nearPath.lineTo(size.width, size.height);
    nearPath.close();
    canvas.drawPath(nearPath, nearPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
