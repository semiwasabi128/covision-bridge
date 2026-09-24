// lib/screens/semi_dao_review_coming_soon_screen.dart
//
// [教練 Agent 2026-08-05] 社群評審系統 placeholder
//
// 當前路由 `/semi-dao/review` 綁到這個 placeholder，使用者會看到清楚的
// 「即將上線」訊息，未來 SemiDAO 社群評審系統實作完成時，只需把這條
// 路由綁回真正的審核池 widget 即可，介面切換零成本。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/bridge_design_system.dart';
import '../theme/tier.dart';
import '../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

class SemiDaoReviewComingSoonScreen extends StatelessWidget {
  const SemiDaoReviewComingSoonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ds = BridgeDSColors.of(context);
    return Scaffold(
      backgroundColor: ds.canvas,
      appBar: AppBar(
        backgroundColor: ds.canvas,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/companions');
            }
          },
        ),
        title: Text(
          '社群評審系統',
          style: TierStyle.of(context, Tier.blockHeading).toTextStyle().copyWith(color: ds.textPrimary,
            fontWeight: FontWeight.w700,),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: ds.accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.handshake_outlined,
                  size: 48,
                  color: ds.accentBlue,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '社群評審系統即將上線',
                style: TierStyle.of(context, Tier.appHeadline).toTextStyle().copyWith(color: ds.textPrimary,
                  fontWeight: FontWeight.w800,),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'SemiDAO 將在社群成員達到一定規模後正式啟動評審池。\n屆時所有夥伴都會進入社群投票與評審流程。',
                style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textSecondary,
                  height: 1.5,),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('返回夥伴館'),
                onPressed: () => context.go('/companions'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}