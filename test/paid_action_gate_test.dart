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

  test('拆牆後仍誠實計數（2026-09-24 Blue 拍板）：上限移除，計數照舊', () async {
    SharedPreferences.setMockInitialValues({});
    for (var i = 0; i < 30; i++) {
      final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
      expect(v.allowed, true, reason: '第 ${i + 1} 發應放行（無上限）');
    }
    // 第 31 發仍放行——牆已拆，但計數持續（帳要看，牆不擋）
    final v31 = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v31.allowed, true);
    expect(v31.reason, contains('無上限'));
    // 計數有在走
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('paid_gate.count_image'), 31);
  });

  test('跨日自動重置', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('paid_gate.date', '2000-01-01');
    await prefs.setInt('paid_gate.count_image', 999);
    final v = await PaidActionGate.instance.checkAndReserve(PaidActionKind.image);
    expect(v.allowed, true); // 舊日計數歸零
  });

  test('video/music 各自獨立計數（拆牆後計數獨立性不變）', () async {
    SharedPreferences.setMockInitialValues({});
    final video = await PaidActionGate.instance.checkAndReserve(PaidActionKind.video);
    final music = await PaidActionGate.instance.checkAndReserve(PaidActionKind.music);
    expect(video.allowed, true); // 牆已拆——video 一律放行
    expect(music.allowed, true); // music 照常
    // 計數各自獨立
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('paid_gate.count_video'), 1);
    expect(prefs.getInt('paid_gate.count_music'), 1);
  });
}
