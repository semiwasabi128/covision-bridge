import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/companion_store.dart';
import '../theme/app_theme.dart';
import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../widgets/adaptive_scaffold.dart';
import 'bridge_desktop_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _isLoading = true;
  bool _needsAuth = false;
  String? _passcodeInput;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final hasConfig = await StorageService.hasConfig();
    final needsAuth = await AuthService.shouldRequireAuth();

    setState(() {
      _needsAuth = needsAuth;
      _isLoading = false;
    });

    if (!hasConfig) {
      // 首次使用，導向設定
      if (mounted) BridgeDesktopScreen.navigateTo('system');
      return;
    }

    if (!needsAuth) {
      // 未啟用認證，檢查是否有夥伴
      await CompanionStore().init();
      final hasCompanion = CompanionStore().hasCompanions;
      if (mounted) {
        context.go(hasCompanion ? '/chat' : '/summon');
      }
      return;
    }
  }

  Future<void> _authenticate() async {
    final success = await AuthService.authenticate();
    if (!mounted) return;
    if (success) {
      await _navigateAfterAuth();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('驗證失敗，請重試')));
    }
  }

  Future<void> _verifyPasscode() async {
    if (_passcodeInput == null || _passcodeInput!.isEmpty) return;
    final success = await AuthService.authenticateWithPasscode(_passcodeInput!);
    if (!mounted) return;
    if (success) {
      await _navigateAfterAuth();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('授權碼錯誤')));
    }
  }

  Future<void> _navigateAfterAuth() async {
    await CompanionStore().init();
    final hasCompanion = CompanionStore().hasCompanions;
    if (mounted) {
      context.go(hasCompanion ? '/chat' : '/summon');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_needsAuth) return const SizedBox.shrink();

    final ds = BridgeDSColors.of(context);

    return AdaptiveScaffold(
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      ds.accentBlue.withValues(alpha: 0.5),
                      ds.accentBlue,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: 48,
                  color: ds.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '橋樑計畫',
                style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '個人 AI 入口',
                style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(
                  color: ds.textSecondary,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _authenticate,
                  icon: Icon(Icons.fingerprint, color: ds.textPrimary),
                  label: Text('生物識別解鎖', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ds.canvas,
          side: BorderSide(color: ds.accentPurple, width: 1.5),
                    foregroundColor: ds.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () => _showPasscodeDialog(),
                  icon: Icon(Icons.pin_outlined, color: ds.accentBlue),
                  label: Text('授權碼解鎖', style: TierStyle.of(context, Tier.cardTitle).toTextStyle()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ds.accentBlue,
                    side: BorderSide(color: ds.accentBlue),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
      ),
    );
  }

  void _showPasscodeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('輸入授權碼'),
        content: TextField(
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          decoration: const InputDecoration(hintText: '6 位數字', counterText: ''),
          onChanged: (v) => _passcodeInput = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _verifyPasscode();
            },
            child: const Text('確認'),
          ),
        ],
      ),
    );
  }
}
