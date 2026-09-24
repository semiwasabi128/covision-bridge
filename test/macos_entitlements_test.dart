import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('macOS app can connect to cloud APIs and serve local gateway', () {
    for (final path in [
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
    ]) {
      final contents = File(path).readAsStringSync();

      expect(
        contents,
        contains('<key>com.apple.security.network.client</key>'),
        reason: '$path must allow outbound model API calls.',
      );
      expect(
        contents,
        contains('<key>com.apple.security.network.server</key>'),
        reason: '$path must allow Bridge Desktop to host the local gateway.',
      );
      expect(
        contents,
        contains('<key>com.apple.security.files.user-selected.read-only</key>'),
        reason:
            '$path must allow users to upload selected reference images for companion generation.',
      );
      expect(
        contents,
        contains(
          '<key>com.apple.security.files.user-selected.read-write</key>',
        ),
        reason: '$path must allow users to export companion pack files.',
      );
      expect(
        contents,
        isNot(contains('<key>keychain-access-groups</key>')),
        reason:
            '$path must stay compatible with local debug signing; storage uses standard macOS Keychain instead.',
      );
    }
  });
}
