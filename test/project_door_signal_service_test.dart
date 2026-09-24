import 'package:bridge_app/services/project_door_signal_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ProjectDoorSignalService();

  test('detects direct big-goal project start language', () {
    final signal = service.detect(
      text: '我打算用 AI 角色直播帶貨銷售商品，請一步一步帶我完成這個目標。',
      conversationContext: const [],
    );

    expect(signal, isNotNull);
    expect(signal!.title, 'AI 角色直播帶貨專案');
    expect(signal.firstFlow, '目標定義');
    expect(signal.requiredBridges, contains('直播平台橋'));
    expect(signal.requiredBridges, contains('商品資料橋'));
  });

  test('detects follow-up language that refers back to a big project', () {
    final signal = service.detect(
      text: '好，我們就把這個案子做起來，請一步一步帶我完成。',
      conversationTitle: 'AI 直播帶貨討論',
      conversationContext: const [
        '如果我想要用 AI 來生成影片讓 AI agent 控制角色直播帶貨銷售商品，這可行嗎？',
        '可行，但要先拆成影片生成、角色互動、直播平台、商品資料、金流物流與法規檢查。',
      ],
    );

    expect(signal, isNotNull);
    expect(signal!.title, 'AI 角色直播帶貨專案');
    expect(signal.requiredBridges, contains('影片生成橋'));
    expect(signal.requiredBridges, contains('金流/物流橋'));
  });

  test('detects semidao role-creation project language', () {
    final signal = service.detect(
      text: '我想把「創建角色」這個玩法先拉出來，再創一個叫做「SemiDAO」的專案門',
      conversationTitle: '直播帶貨',
      conversationContext: const [
        '我們剛才在聊 AI 助理角色的創建玩法。',
        '這可以變成一包可被其他專案共享的數位資產。',
      ],
    );

    expect(signal, isNotNull);
    expect(signal!.title, 'SemiDAO');
    expect(signal.requiredBridges, contains('角色資產橋'));
    expect(signal.requiredBridges, contains('SemiDAO 社群資產橋'));
  });

  test('does not open a project door for a simple analysis question', () {
    final signal = service.detect(
      text: '這個想法可行嗎？',
      conversationContext: const ['AI 直播帶貨可能需要很多工具。'],
    );

    expect(signal, isNull);
  });
}
