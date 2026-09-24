import 'package:shared_preferences/shared_preferences.dart';

import 'brain_progress_store.dart';
import 'memory_store.dart';

class AgentMotivationSnapshot {
  final String agentName;
  final int driveXp;
  final int driveLevel;
  final int accuracyScore;
  final int resonanceScore;
  final int autonomyScore;
  final int usefulFeedbackCount;
  final int correctionCount;
  final int mutedCount;
  final int recoveryRouteCount;
  final int correctionStreak;
  final String learningFocus;
  final String lastSignal;
  final String activeRecoveryRoute;

  const AgentMotivationSnapshot({
    required this.agentName,
    required this.driveXp,
    required this.driveLevel,
    required this.accuracyScore,
    required this.resonanceScore,
    required this.autonomyScore,
    required this.usefulFeedbackCount,
    required this.correctionCount,
    required this.mutedCount,
    this.recoveryRouteCount = 0,
    this.correctionStreak = 0,
    required this.learningFocus,
    required this.lastSignal,
    this.activeRecoveryRoute = '尚未形成通關路線',
  });

  int get totalFeedback => usefulFeedbackCount + correctionCount + mutedCount;
  bool get hasRecoveryRoute => recoveryRouteCount > 0;
}

class AgentMotivationChange {
  final AgentMotivationSnapshot before;
  final AgentMotivationSnapshot after;
  final BrainProgressChange? brainProgressChange;

  const AgentMotivationChange({
    required this.before,
    required this.after,
    this.brainProgressChange,
  });

  bool get didLevelUp => after.driveLevel > before.driveLevel;
}

class AgentMotivationEngine {
  static const String _prefix = 'bridge_agent_motivation_v1';
  static const int _baseScore = 60;

  const AgentMotivationEngine();

  Future<AgentMotivationSnapshot> getSnapshot(String? agentName) async {
    final name = _safeAgentName(agentName);
    final prefs = await SharedPreferences.getInstance();
    final useful = prefs.getInt(_key(name, 'useful')) ?? 0;
    final corrections = prefs.getInt(_key(name, 'corrections')) ?? 0;
    final muted = prefs.getInt(_key(name, 'muted')) ?? 0;
    final correctionStreak = prefs.getInt(_key(name, 'correction_streak')) ?? 0;
    final recoveryRoutes = prefs.getInt(_key(name, 'recovery_routes')) ?? 0;
    final driveXp = prefs.getInt(_key(name, 'xp')) ?? 0;
    final lastSignal = prefs.getString(_key(name, 'last_signal')) ?? '等待校準';
    final activeRecoveryRoute =
        prefs.getString(_key(name, 'active_recovery_route')) ?? '尚未形成通關路線';

    return AgentMotivationSnapshot(
      agentName: name,
      driveXp: driveXp,
      driveLevel: BrainProgressStore.snapshotForXp(driveXp).level,
      accuracyScore: _score(
        positive: useful,
        negative: corrections,
        neutral: muted,
      ),
      resonanceScore: _score(
        positive: useful,
        negative: corrections + muted,
        neutral: 0,
      ),
      autonomyScore: _score(
        positive: useful,
        negative: muted,
        neutral: corrections,
      ),
      usefulFeedbackCount: useful,
      correctionCount: corrections,
      mutedCount: muted,
      recoveryRouteCount: recoveryRoutes,
      correctionStreak: correctionStreak,
      learningFocus: _learningFocus(useful, corrections, muted),
      lastSignal: lastSignal,
      activeRecoveryRoute: activeRecoveryRoute,
    );
  }

  Future<AgentMotivationChange> applyInsightFeedback({
    required String? agentName,
    required String insight,
    required TransurfingInsightFeedback feedback,
  }) async {
    final name = _safeAgentName(agentName);
    final before = await getSnapshot(name);
    await MemoryStore.markTransurfingInsightFeedback(insight, feedback);

    final prefs = await SharedPreferences.getInstance();
    final xp = _xpFor(feedback);
    await prefs.setInt(_key(name, 'xp'), before.driveXp + xp);
    switch (feedback) {
      case TransurfingInsightFeedback.accurate:
        await _increment(prefs, name, 'useful');
        await prefs.setInt(_key(name, 'correction_streak'), 0);
        await prefs.setString(
          _key(name, 'last_signal'),
          '這筆洞察有用，之後可以更常引用相似線索。',
        );
        break;
      case TransurfingInsightFeedback.inaccurate:
        await _increment(prefs, name, 'corrections');
        await _markCorrectionStreak(
          prefs,
          name,
          route: '下次遇到類似線索，先停下確認主線、卡點與能力缺口，再直接走已驗證的通關路線。',
        );
        await prefs.setString(_key(name, 'last_signal'), '這筆洞察不準，之後要降低相似判斷權重。');
        break;
      case TransurfingInsightFeedback.muted:
        await _increment(prefs, name, 'muted');
        await _markCorrectionStreak(
          prefs,
          name,
          route: '下次遇到類似線索，先不要引用，改用提問或搜尋可驗證來源。',
        );
        await prefs.setString(_key(name, 'last_signal'), '這筆洞察暫停使用，之後不要主動引用。');
        break;
    }

    BrainProgressChange? brainProgressChange;
    if (xp > 0) {
      brainProgressChange = await BrainProgressStore.awardXp(xp);
    }
    final after = await getSnapshot(name);
    return AgentMotivationChange(
      before: before,
      after: after,
      brainProgressChange: brainProgressChange,
    );
  }

  static Future<void> clear({String? agentName}) async {
    final prefs = await SharedPreferences.getInstance();
    if (agentName != null) {
      final name = _safeAgentName(agentName);
      for (final suffix in const [
        'useful',
        'corrections',
        'muted',
        'correction_streak',
        'recovery_routes',
        'active_recovery_route',
        'xp',
        'last_signal',
      ]) {
        await prefs.remove(_key(name, suffix));
      }
      return;
    }
    final keys = prefs.getKeys().where((key) => key.startsWith(_prefix));
    for (final key in keys.toList()) {
      await prefs.remove(key);
    }
  }

  Future<void> _increment(
    SharedPreferences prefs,
    String agentName,
    String suffix,
  ) async {
    final key = _key(agentName, suffix);
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }

  Future<void> _markCorrectionStreak(
    SharedPreferences prefs,
    String agentName, {
    required String route,
  }) async {
    final streakKey = _key(agentName, 'correction_streak');
    final nextStreak = (prefs.getInt(streakKey) ?? 0) + 1;
    await prefs.setInt(streakKey, nextStreak);
    if (nextStreak < 2) return;

    await _increment(prefs, agentName, 'recovery_routes');
    await prefs.setString(_key(agentName, 'active_recovery_route'), route);
  }

  int _xpFor(TransurfingInsightFeedback feedback) {
    return switch (feedback) {
      TransurfingInsightFeedback.accurate => 15,
      TransurfingInsightFeedback.inaccurate => 3,
      TransurfingInsightFeedback.muted => 1,
    };
  }

  static int _score({
    required int positive,
    required int negative,
    required int neutral,
  }) {
    final score = _baseScore + (positive * 8) - (negative * 10) - (neutral * 2);
    return score.clamp(0, 100).toInt();
  }

  static String _learningFocus(int useful, int corrections, int muted) {
    if (corrections > 0 && corrections >= useful && corrections >= muted) {
      return '先降低誤判，少用不確定線索。';
    }
    if (muted > useful && muted >= corrections) {
      return '先學會何時不要引用記憶。';
    }
    if (useful == 0 && corrections == 0 && muted == 0) {
      return '等待使用者校準第一批線索。';
    }
    return '延續高分線索，靠近使用者真正意圖。';
  }

  static String _safeAgentName(String? agentName) {
    final trimmed = agentName?.trim();
    if (trimmed == null || trimmed.isEmpty) return 'Bridge Agent';
    return trimmed;
  }

  static String _key(String agentName, String suffix) {
    final safeName = agentName.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u4e00-\u9fff]+'),
      '_',
    );
    return '$_prefix.$safeName.$suffix';
  }
}
