import 'package:bridge_app/theme/tier_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('default Tier manifest 可載入並解析 card.body', (tester) async {
    final theme = await loadDefaultTierTheme();
    expect(theme.resolve, isNotNull);
  });
}
