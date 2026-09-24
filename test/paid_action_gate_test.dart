// paid_action_gate_test.dart
// [小葵 2026-08-21] $33 根治驗證——閘門邏輯實測（mock prefs，零成本）
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bridge_app/services/paid_action_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('上限內放行並計數', () async {
    SharedPreferences.setMockInitialValues({});
    final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v.allowed, true);
    final v2 = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v2.allowed, true);
  });

  test('超過上限誠實擋下（保險絲）：30 發後第 31 發必擋', () async {
    SharedPreferences.setMockInitialValues({});
    // 不依賴跨測試狀態——真的跑滿預設上限 30 發
    for (var i = 0; i < 30; i++) {
      final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
      expect(v.allowed, true, reason: '第 ${i + 1} 發應放行');
    }
    final v31 = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v31.allowed, false);
    expect(v31.reason, contains('上限'));
    expect(v31.reason, contains('30/30'));
  });

  test('跨日自動重置', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paid_gate.date', '2000-01-01');
    await prefs.setInt('paid_gate.count_image', 999);
    final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v.allowed, true); // 舊日計數歸零
  });

  test('video/music 各自獨立額度', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('paid_gate.cap_video', 0);
    await prefs.setString('paid_gate.date',
        DateTime.now().toIso8601String().substring(0, 10));
    final video = await PaidActionGate.instance.checkAndReserve(PaidActionKind.video);
    final music = await PaidActionGate.instance.checkAndReserve(PaidActionKind.music);
    expect(video.allowed, false); // video 爆了
    expect(music.allowed, true); // music 不受影響
  });
}
