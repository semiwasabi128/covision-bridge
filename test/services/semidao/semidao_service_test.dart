// semidao_service_test.dart
// SemiDAO Phase 1 服務測試

import 'dart:io';
import 'dart:typed_data';

import 'package:bridge_app/services/semidao/semidao_models.dart';
import 'package:bridge_app/services/semidao/semidao_service.dart';
import 'package:bridge_app/services/semidao/signature_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String _appDocPath;

  _MockPathProvider(this._appDocPath);

  @override
  Future<String?> getApplicationDocumentsPath() async => _appDocPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SemidaoService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('semidao_test_');
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
    service = SemidaoService();
    await service.signatureService.ensureKeypair(displayName: 'TestCreator');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SemidaoService.registerAsset', () {
    test('registers an original asset with signature + IPFS pin', () async {
      const content = '{"nodes":[],"edges":[]}';
      final result = await service.registerAsset(
        name: 'MV製作工作流',
        kind: SemidaoAssetKind.workflow,
        content: content,
        description: '測試工作流',
      );

      final asset = result.asset;
      expect(asset.id, isNotEmpty);
      expect(asset.name, 'MV製作工作流');
      expect(asset.kind, SemidaoAssetKind.workflow);
      expect(asset.isOriginal, isTrue);
      expect(result.wasDerived, isFalse);
      expect(asset.isSigned, isTrue);
      expect(asset.isPinned, isTrue);
      expect(asset.contentHash, isNotEmpty);
      expect(asset.signature!.signerFingerprint, isNotEmpty);
      expect(asset.ipfsRecord!.cid, startsWith('Qm'));
      expect(asset.ipfsRecord!.sizeBytes, greaterThan(0));
    });

    test('computes consistent content hash for same content', () async {
      const content = '{"test":true}';
      final r1 = await service.registerAsset(
        name: 'A',
        kind: SemidaoAssetKind.workflow,
        content: content,
      );
      // clear and re-register
      await service.clearForTest();
      SharedPreferences.setMockInitialValues({});
      await service.signatureService.ensureKeypair(displayName: 'T');
      final r2 = await service.registerAsset(
        name: 'B',
        kind: SemidaoAssetKind.workflow,
        content: content,
      );

      expect(r1.asset.contentHash, r2.asset.contentHash);
    });
  });

  group('SemidaoService.verifyAsset', () {
    test('verifies a signed asset', () async {
      const content = '{"nodes":[]}';
      final result = await service.registerAsset(
        name: 'test',
        kind: SemidaoAssetKind.workflow,
        content: content,
      );

      final verified = await service.verifyAsset(result.asset);
      expect(verified, isTrue);
    });

    test('rejects tampered signature', () async {
      const content = '{"nodes":[]}';
      final result = await service.registerAsset(
        name: 'test',
        kind: SemidaoAssetKind.workflow,
        content: content,
      );

      final tampered = result.asset.copyWith(
        signature: SemidaoSignature(
          signature: 'deadbeef',
          contentHash: result.asset.contentHash,
          signedAt: DateTime.now(),
          signerFingerprint: 'wrong',
        ),
      );
      final verified = await service.verifyAsset(tampered);
      expect(verified, isFalse);
    });
  });

  group('SemidaoService.verifyContentIntegrity', () {
    test('matches original content', () async {
      const content = '{"workflow":"v1"}';
      final result = await service.registerAsset(
        name: 'test',
        kind: SemidaoAssetKind.workflow,
        content: content,
      );

      final ok = await service.verifyContentIntegrity(result.asset, content);
      expect(ok, isTrue);
    });

    test('rejects modified content', () async {
      const content = '{"workflow":"v1"}';
      final result = await service.registerAsset(
        name: 'test',
        kind: SemidaoAssetKind.workflow,
        content: content,
      );

      final ok = await service.verifyContentIntegrity(
          result.asset, '{"workflow":"v2"}');
      expect(ok, isFalse);
    });
  });

  group('SemidaoService.derivation', () {
    test('registers derivative and links parent', () async {
      const parentContent = '{"v":1}';
      final parentResult = await service.registerAsset(
        name: '原創工作流',
        kind: SemidaoAssetKind.workflow,
        content: parentContent,
      );

      const childContent = '{"v":2,"improved":true}';
      final childResult = await service.registerAsset(
        name: '改良工作流',
        kind: SemidaoAssetKind.workflow,
        content: childContent,
        derivedFromAssetId: parentResult.asset.id,
      );

      expect(childResult.wasDerived, isTrue);
      expect(childResult.asset.derivedFromAssetId, parentResult.asset.id);
      expect(childResult.asset.isOriginal, isFalse);

      // parent 的 derivativeAssetIds 應包含 child
      final parentUpdated = await service.getAsset(parentResult.asset.id);
      expect(parentUpdated!.derivativeAssetIds, contains(childResult.asset.id));
    });

    test('getDerivationChain traces ancestors', () async {
      final r1 = await service.registerAsset(
        name: 'A',
        kind: SemidaoAssetKind.workflow,
        content: '{"a":1}',
      );
      final r2 = await service.registerAsset(
        name: 'B',
        kind: SemidaoAssetKind.workflow,
        content: '{"b":1}',
        derivedFromAssetId: r1.asset.id,
      );
      final r3 = await service.registerAsset(
        name: 'C',
        kind: SemidaoAssetKind.workflow,
        content: '{"c":1}',
        derivedFromAssetId: r2.asset.id,
      );

      final chain = await service.getDerivationChain(r3.asset.id);
      expect(chain.length, 2);
      expect(chain[0].id, r2.asset.id);
      expect(chain[1].id, r1.asset.id);
    });

    test('getDerivatives lists direct children', () async {
      final r1 = await service.registerAsset(
        name: 'parent',
        kind: SemidaoAssetKind.workflow,
        content: '{"p":1}',
      );
      await service.registerAsset(
        name: 'child1',
        kind: SemidaoAssetKind.workflow,
        content: '{"c1":1}',
        derivedFromAssetId: r1.asset.id,
      );
      await service.registerAsset(
        name: 'child2',
        kind: SemidaoAssetKind.workflow,
        content: '{"c2":1}',
        derivedFromAssetId: r1.asset.id,
      );

      final children = await service.getDerivatives(r1.asset.id);
      expect(children.length, 2);
    });
  });

  group('SemidaoService.retrieveContent', () {
    test('retrieves pinned content from IPFS mock', () async {
      const content = '{"hello":"world"}';
      final result = await service.registerAsset(
        name: 'test',
        kind: SemidaoAssetKind.workflow,
        content: content,
      );

      final retrieved = await service.retrieveContent(result.asset);
      expect(retrieved, content);
    });
  });

  group('SemidaoService.getAllAssets', () {
    test('lists all registered assets sorted by creation time', () async {
      await service.registerAsset(
        name: 'first',
        kind: SemidaoAssetKind.workflow,
        content: '{"1":1}',
      );
      await service.registerAsset(
        name: 'second',
        kind: SemidaoAssetKind.playbook,
        content: '{"2":2}',
      );

      final all = await service.getAllAssets();
      expect(all.length, 2);
    });
  });

  group('SemidaoService.updateLicense', () {
    test('updates license and preserves other fields', () async {
      final result = await service.registerAsset(
        name: 'test',
        kind: SemidaoAssetKind.workflow,
        content: '{"x":1}',
      );

      const newLicense = SemidaoLicense(
        licenseType: SemidaoLicenseType.commercial,
        price: 100,
        commercialSplit: 8000,
      );
      final updated = await service.updateLicense(
          result.asset.id, newLicense);

      expect(updated!.license.licenseType, SemidaoLicenseType.commercial);
      expect(updated.license.price, 100);
      expect(updated.contentHash, result.asset.contentHash);
      expect(updated.isSigned, isTrue);
    });
  });

  group('SignatureService', () {
    test('generates stable keypair', () async {
      final s1 = await service.signatureService.getCreator();
      final s2 = await service.signatureService.getCreator();
      expect(s1.publicKeyFingerprint, s2.publicKeyFingerprint);
      expect(s1.publicKeyFingerprint.length, 64); // SHA-256 hex
    });

    test('content hash is deterministic', () {
      final hash1 =
          service.signatureService.computeContentHash('hello');
      final hash2 =
          service.signatureService.computeContentHash('hello');
      expect(hash1, hash2);
      expect(hash1.length, 64);
    });
  });
}
