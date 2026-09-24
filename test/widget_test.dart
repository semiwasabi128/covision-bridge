import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bridge_app/app.dart';

void main() {
  // BridgeApp 啟動時初始化大量服務（CompanionStore, JsBridge,
  // CompanionRuntimeOutlet, BrainContainerService, SkillStore），
  // 這些服務建立 pending timers，在 flutter test 環境中無法全部完成。
  // 需要 deep mocking 才能穩定測試，目前以整合測試（真機）替代。
  testWidgets(
    'BridgeApp renders without platform import failures',
    (WidgetTester tester) async {
      await tester.pumpWidget(const BridgeApp());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(MaterialApp), findsOneWidget);
    },
    skip: true,
  );
}
