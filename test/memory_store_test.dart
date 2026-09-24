import 'package:bridge_app/models/second_brain_trace.dart';
import 'package:bridge_app/services/memory_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists second brain association feedback', () async {
    const association = '正式橋能力 ↔ adapter 完成訊號 ↔ 回到原本卡點';

    await MemoryStore.markSecondBrainAssociationFeedback(
      association,
      SecondBrainAssociationFeedback.useful,
    );

    expect(
      await MemoryStore.getSecondBrainAssociationFeedback(association),
      SecondBrainAssociationFeedback.useful,
    );

    await MemoryStore.markSecondBrainAssociationFeedback(
      association,
      SecondBrainAssociationFeedback.wrong,
    );

    expect(
      await MemoryStore.getSecondBrainAssociationFeedback(association),
      SecondBrainAssociationFeedback.wrong,
    );
  });

  test('loads only requested second brain association feedbacks', () async {
    const goodAssociation = '角色資產包 ↔ 權利護照 ↔ 分享社群包';
    const hiddenAssociation = '新聞橋 ↔ adapter 分支 ↔ 待回流門';

    await MemoryStore.markSecondBrainAssociationFeedback(
      goodAssociation,
      SecondBrainAssociationFeedback.useful,
    );
    await MemoryStore.markSecondBrainAssociationFeedback(
      hiddenAssociation,
      SecondBrainAssociationFeedback.wrong,
    );

    final feedbacks = await MemoryStore.getSecondBrainAssociationFeedbacks(
      const [goodAssociation, '尚未評分的關聯'],
    );

    expect(feedbacks, {goodAssociation: SecondBrainAssociationFeedback.useful});
  });
}
