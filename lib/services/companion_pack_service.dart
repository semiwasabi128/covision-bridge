import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/companion.dart';
import 'companion_asset_manifest_service.dart';
import 'companion_store.dart';

class CompanionPackException implements Exception {
  final String message;

  const CompanionPackException(this.message);

  @override
  String toString() => message;
}

class CompanionPackPreview {
  final Map<String, dynamic> pack;
  final String id;
  final String version;
  final String name;
  final String summary;
  final String authorName;
  final String license;
  final List<String> tags;
  final String role;
  final String mbtiCode;
  final List<String> personalityTags;
  final String speakingStyle;
  final List<String> toneRules;
  final String specialFunction;
  final List<String> expertise;
  final String appearancePrompt;
  final String appearanceDescription;
  final List<String> palette;
  final String riskLevel;
  final List<String> requiredPermissions;
  final List<String> optionalPermissions;
  final bool containsUserMemory;
  final bool containsApiKeys;
  final bool containsExecutableCode;
  final bool localOnly;
  final bool localOnlyAllowed;
  final String reviewStatus;
  final List<String> contentWarnings;

  const CompanionPackPreview({
    required this.pack,
    required this.id,
    required this.version,
    required this.name,
    required this.summary,
    required this.authorName,
    required this.license,
    required this.tags,
    required this.role,
    required this.mbtiCode,
    required this.personalityTags,
    required this.speakingStyle,
    required this.toneRules,
    required this.specialFunction,
    required this.expertise,
    required this.appearancePrompt,
    required this.appearanceDescription,
    required this.palette,
    required this.riskLevel,
    required this.requiredPermissions,
    required this.optionalPermissions,
    required this.containsUserMemory,
    required this.containsApiKeys,
    required this.containsExecutableCode,
    required this.localOnly,
    required this.localOnlyAllowed,
    required this.reviewStatus,
    required this.contentWarnings,
  });

  bool get isSafe =>
      !containsUserMemory &&
      !containsApiKeys &&
      !containsExecutableCode &&
      (!localOnly || localOnlyAllowed);

  List<String> get unsafeReasons => [
    if (containsUserMemory) '含有使用者記憶',
    if (containsApiKeys) '含有 API Key',
    if (containsExecutableCode) '含有可執行程式碼',
    if (localOnly && !localOnlyAllowed) '本機限定角色包只能在原本裝置匯入',
  ];
}

class CompanionPackService {
  static const schema = 'bridge.companion-pack.v0.1';

  const CompanionPackService({
    String Function()? idFactory,
    String? localInstallId,
  }) : _idFactory = idFactory,
       _localInstallId = localInstallId;

  final String Function()? _idFactory;
  final String? _localInstallId;

  String exportToJson(
    Companion companion, {
    String authorName = '',
    String summary = '',
    String license = 'CC-BY-SA-4.0',
    List<CompanionAssetStateSpec>? assetStates,
    String? primaryImagePath,
    String? primaryAnimationPath,
    bool? commercialUseAllowed,
  }) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(
      toPackJson(
        companion,
        authorName: authorName,
        summary: summary,
        license: license,
        assetStates: assetStates,
        primaryImagePath: primaryImagePath,
        primaryAnimationPath: primaryAnimationPath,
        commercialUseAllowed: commercialUseAllowed,
      ),
    );
  }

  /// [教練 Agent 2026-06-28] ZIP 格式匯出
  /// 結構：manifest.json + images/ + animations/ + voice/
  /// 圖片用獨立檔案，不再 base64 嵌入 JSON
  Future<List<int>> exportToZip(
    Companion companion, {
    String authorName = '',
    String summary = '',
    String license = 'CC-BY-SA-4.0',
    List<CompanionAssetStateSpec>? assetStates,
    String? primaryImagePath,
    String? primaryAnimationPath,
    bool? commercialUseAllowed,
  }) async {
    final pack = toPackJson(
      companion,
      authorName: authorName,
      summary: summary,
      license: license,
      assetStates: assetStates,
      primaryImagePath: primaryImagePath,
      primaryAnimationPath: primaryAnimationPath,
      commercialUseAllowed: commercialUseAllowed,
    );

    final archive = Archive();

    // --- 收集所有圖片路徑，建立相對路徑映射 ---
    final imageEntries = <_ZipImageEntry>[];
    var skippedImages = 0;

    // 主形象圖
    final appearance = _mapAt(pack, 'appearance');
    final avatarPath = _stringAt(appearance, 'avatarImagePath');
    if (avatarPath.isNotEmpty && !avatarPath.startsWith('data:image/')) {
      final file = File(avatarPath);
      if (await file.exists()) {
        final ext = _fileExtension(avatarPath);
        final relPath = 'images/avatar.$ext';
        imageEntries.add(_ZipImageEntry(file, relPath));
        appearance['avatarImagePath'] = relPath;
      } else {
        debugPrint('[ExportZip] 主形象圖檔案不存在: $avatarPath');
        skippedImages++;
      }
    } else if (avatarPath.startsWith('data:image/')) {
      // [教練 Agent 2026-06-29] data URL 直接解碼寫入 ZIP
      try {
        final bytes = base64Decode(avatarPath.substring(avatarPath.indexOf(',') + 1));
        final relPath = 'images/avatar.png';
        archive.addFile(ArchiveFile.bytes(relPath, bytes));
        appearance['avatarImagePath'] = relPath;
      } catch (e) {
        debugPrint('[ExportZip] data URL 解碼失敗: $e');
        skippedImages++;
      }
    }

    // portraitImagePath（如果有且不同於 avatar）
    final portraitPath = _stringAt(appearance, 'portraitImagePath');
    if (portraitPath.isNotEmpty &&
        portraitPath != avatarPath &&
        !portraitPath.startsWith('data:image/')) {
      final file = File(portraitPath);
      if (await file.exists()) {
        final ext = _fileExtension(portraitPath);
        final relPath = 'images/portrait.$ext';
        imageEntries.add(_ZipImageEntry(file, relPath));
        appearance['portraitImagePath'] = relPath;
      }
    }

    // 動畫路徑（未來 Lottie/GIF）
    final avatarAnimPath = _stringAt(appearance, 'avatarAnimationPath');
    if (avatarAnimPath.isNotEmpty && !avatarAnimPath.startsWith('data:')) {
      final file = File(avatarAnimPath);
      if (await file.exists()) {
        final ext = _fileExtension(avatarAnimPath);
        final relPath = 'animations/avatar.$ext';
        imageEntries.add(_ZipImageEntry(file, relPath));
        appearance['avatarAnimationPath'] = relPath;
      }
    }

    // 狀態圖
    final manifest = _manifestFromPack(pack);
    final states = manifest['states'];
    if (states is List) {
      for (var i = 0; i < states.length; i++) {
        final state = states[i];
        if (state is! Map) continue;
        final stateMap = state is Map<String, dynamic>
            ? state
            : Map<String, dynamic>.from(state);
        final stateId = _stringAt(stateMap, 'stateId').trim();
        if (stateId.isEmpty) continue;

        // 狀態圖片
        final imgPath = _stateImagePath(stateMap);
        if (imgPath.isNotEmpty && !imgPath.startsWith('data:image/')) {
          final file = File(imgPath);
          if (await file.exists()) {
            final ext = _fileExtension(imgPath);
            final relPath = 'images/state_$stateId.$ext';
            imageEntries.add(_ZipImageEntry(file, relPath));
            // 更新 pack 裡的路徑
            _setStateImagePath(stateMap, relPath);
          } else {
            debugPrint('[ExportZip] 狀態圖 $stateId 檔案不存在: $imgPath');
            skippedImages++;
          }
        } else if (imgPath.startsWith('data:image/')) {
          // [教練 Agent 2026-06-29] data URL 直接解碼寫入 ZIP
          try {
            final bytes = base64Decode(imgPath.substring(imgPath.indexOf(',') + 1));
            final relPath = 'images/state_$stateId.png';
            archive.addFile(ArchiveFile.bytes(relPath, bytes));
            _setStateImagePath(stateMap, relPath);
          } catch (e) {
            debugPrint('[ExportZip] 狀態圖 $stateId data URL 解碼失敗: $e');
            skippedImages++;
          }
        }

        // 狀態動畫
        final animMap = _mapAt(stateMap, 'animation');
        final animPath = _stringAt(animMap, 'path');
        if (animPath.isNotEmpty && !animPath.startsWith('data:')) {
          final file = File(animPath);
          if (await file.exists()) {
            final ext = _fileExtension(animPath);
            final relPath = 'animations/state_$stateId.$ext';
            imageEntries.add(_ZipImageEntry(file, relPath));
            animMap['path'] = relPath;
          }
        }
      }
    }

    // --- 寫入 manifest.json ---
    const encoder = JsonEncoder.withIndent('  ');
    final manifestJson = encoder.convert(pack);
    final manifestBytes = utf8.encode(manifestJson);
    archive.addFile(ArchiveFile.bytes('manifest.json', manifestBytes));

    debugPrint('[ExportZip] manifest.json 已加入 archive (${manifestBytes.length} bytes)');
    debugPrint('[ExportZip] archive 內檔案數量：${archive.numberOfFiles()}');
    for (var i = 0; i < archive.numberOfFiles(); i++) {
      debugPrint('[ExportZip]   [$i] ${archive.fileName(i)} (${archive.fileSize(i)} bytes)');
    }

    // --- 寫入圖片檔 ---
    for (final entry in imageEntries) {
      final bytes = await entry.file.readAsBytes();
      archive.addFile(ArchiveFile.bytes(entry.zipPath, bytes));
    }

    debugPrint('[ExportZip] 完成：${imageEntries.length} 張圖片寫入 ZIP，$skippedImages 張跳過');

    // --- 壓縮成 ZIP ---
    final zipBytes = ZipEncoder().encode(archive);

    // [教練 Agent 2026-06-29] 驗證 ZIP 可被正確讀回
    try {
      final verifyArchive = ZipDecoder().decodeBytes(zipBytes);
      final verifyFile = verifyArchive.findFile('manifest.json');
      if (verifyFile == null) {
        final allNames = <String>[];
        for (var i = 0; i < verifyArchive.numberOfFiles(); i++) {
          allNames.add(verifyArchive.fileName(i));
        }
        debugPrint('[ExportZip] ❌ 驗證失敗！ZIP 內找不到 manifest.json。實際內容：${allNames.join(', ')}');
      } else {
        debugPrint('[ExportZip] ✅ 驗證成功，manifest.json 在 ZIP 中 (${verifyFile.size} bytes)');
      }
    } catch (e) {
      debugPrint('[ExportZip] ❌ 驗證時發生例外：$e');
    }

    return zipBytes;
  }

  /// [教練 Agent 2026-06-28] ZIP 格式匯入
  /// 解壓 → 讀 manifest.json → 圖片存到 app documents → 回傳 Companion
  Future<Companion> importFromZip(List<int> zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    // [教練 Agent 2026-06-29] 改進 manifest.json 搜尋：支援目錄前綴
    ArchiveFile? manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      // 嘗試在子目錄中找 manifest.json
      for (final file in archive) {
        if (!file.isDirectory && file.name.endsWith('manifest.json')) {
          manifestFile = file;
          break;
        }
      }
    }
    if (manifestFile == null) {
      // 列出所有檔案名稱幫助除錯
      final allNames = archive
          .where((f) => !f.isDirectory)
          .map((f) => f.name)
          .toList();
      throw CompanionPackException(
        'ZIP 包缺少 manifest.json。找到的檔案：${allNames.join(', ')}',
      );
    }

    // [教練 Agent 2026-06-29] 除錯：列出 ZIP 內容
    final allFiles = archive
        .where((f) => !f.isDirectory)
        .map((f) => '${f.name} (${f.size} bytes)')
        .toList();
    debugPrint('[ImportZip] ZIP 內容：${allFiles.join('\n')}');

    final manifestJson = utf8.decode(manifestFile.content as List<int>);
    final pack = jsonDecode(manifestJson) as Map<String, dynamic>;
    final packCopy = Map<String, dynamic>.from(pack);

    // [教練 Agent 2026-06-29] 記錄匯入時圖片路徑，用於除錯
    final debugAppearance = _mapAt(packCopy, 'appearance');
    debugPrint('[ImportZip] avatarImagePath in manifest: "${_stringAt(debugAppearance, 'avatarImagePath')}"');

    // 準備圖片目錄
    final imagesDir = await _getImagesDir();

    // 處理 avatarImagePath
    final appearance = _mapAt(packCopy, 'appearance');
    final avatarPath = _stringAt(appearance, 'avatarImagePath');
    if (avatarPath.isNotEmpty && !avatarPath.startsWith('data:image/')) {
      final newPath = await _extractZipFile(
        archive, avatarPath, imagesDir,
      );
      if (newPath != null) {
        appearance['avatarImagePath'] = newPath;
      }
    }

    // 處理 portraitImagePath
    final portraitPath = _stringAt(appearance, 'portraitImagePath');
    if (portraitPath.isNotEmpty &&
        portraitPath != avatarPath &&
        !portraitPath.startsWith('data:image/')) {
      final newPath = await _extractZipFile(
        archive, portraitPath, imagesDir,
      );
      if (newPath != null) {
        appearance['portraitImagePath'] = newPath;
      }
    }

    // 處理 avatarAnimationPath
    final avatarAnimPath = _stringAt(appearance, 'avatarAnimationPath');
    if (avatarAnimPath.isNotEmpty && !avatarAnimPath.startsWith('data:')) {
      final animDir = await _getAnimationsDir();
      final newPath = await _extractZipFile(
        archive, avatarAnimPath, animDir,
      );
      if (newPath != null) {
        appearance['avatarAnimationPath'] = newPath;
      }
    }

    // 處理狀態圖
    final manifest = _manifestFromPack(packCopy);
    final states = manifest['states'];
    if (states is List) {
      for (final state in states) {
        if (state is! Map) continue;
        final stateMap = state is Map<String, dynamic>
            ? state
            : Map<String, dynamic>.from(state);
        final stateId = _stringAt(stateMap, 'stateId').trim();
        if (stateId.isEmpty) continue;

        // 狀態圖片
        final imgPath = _stateImagePath(stateMap);
        if (imgPath.isNotEmpty && !imgPath.startsWith('data:image/')) {
          final newPath = await _extractZipFile(
            archive, imgPath, imagesDir,
          );
          if (newPath != null) {
            _setStateImagePath(stateMap, newPath);
          }
        }

        // 狀態動畫
        final animMap = _mapAt(stateMap, 'animation');
        final animPath = _stringAt(animMap, 'path');
        if (animPath.isNotEmpty && !animPath.startsWith('data:')) {
          final animDir = await _getAnimationsDir();
          final newPath = await _extractZipFile(
            archive, animPath, animDir,
          );
          if (newPath != null) {
            animMap['path'] = newPath;
          }
        }
      }
    }

    return importFromPackJson(packCopy);
  }

  /// 從 ZIP 中解壓單一檔案到目標目錄
  /// [教練 Agent 2026-06-29] 改進：findFile 精確比對失敗時，用 endsWith 寬容搜尋
  Future<String?> _extractZipFile(
    Archive archive,
    String relPath,
    String targetDirPath,
  ) async {
    var file = archive.findFile(relPath);
    if (file == null) {
      // 寬容搜尋：找 endsWith(relPath) 的檔案
      final cleanRelPath = relPath.startsWith('./')
          ? relPath.substring(2)
          : relPath;
      for (final f in archive) {
        if (!f.isDirectory && f.name.endsWith(cleanRelPath)) {
          file = f;
          break;
        }
      }
    }
    if (file == null) return null;
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final ext = _fileExtension(relPath);
    final outPath = '$targetDirPath/pack_$timestamp.$ext';
    final outFile = File(outPath);
    await outFile.writeAsBytes(file.content as List<int>, flush: true);
    return outPath;
  }

  Future<String> _getImagesDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/bridge_media/images');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<String> _getAnimationsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/bridge_media/animations');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  static String _fileExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'png';
    return path.substring(dot + 1).toLowerCase();
  }

  static void _setStateImagePath(Map<String, dynamic> state, String newPath) {
    state['imagePath'] = newPath;
    final still = _mapAt(state, 'still');
    if (still.isNotEmpty) {
      still['path'] = newPath;
    }
  }

  Map<String, dynamic> toPackJson(
    Companion companion, {
    String authorName = '',
    String summary = '',
    String license = 'CC-BY-SA-4.0',
    List<CompanionAssetStateSpec>? assetStates,
    String? primaryImagePath,
    String? primaryAnimationPath,
    bool? commercialUseAllowed,
  }) {
    final mbti = companion.mbtiType;
    final assetManifest = const CompanionAssetManifestService()
        .buildForCompanion(
          companion,
          assetStates: assetStates,
          primaryImagePath: primaryImagePath,
          primaryAnimationPath: primaryAnimationPath,
        );
    final includedAssets = (assetManifest['includedAssets'] as List<dynamic>)
        .whereType<String>()
        .toList();
    final stateAssets = (assetManifest['states'] as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .toList();
    return {
      'schema': schema,
      'id': 'local.${companion.id}',
      'version': '0.1.0',
      'name': companion.name,
      'summary': summary.isEmpty
          ? '${companion.roleName}，${mbti?.description ?? '橋樑電子夥伴'}'
          : summary,
      'author': {'name': authorName, 'url': '', 'publicKey': ''},
      'license': license,
      'language': ['zh-Hant'],
      'tags': [
        companion.role.name,
        ...companion.personalityTags.map((tag) => tag.name),
      ],
      'compatibility': {'bridgeApp': '>=0.1.0', 'packSpec': '0.1'},
      'identity': {
        'role': companion.role.name,
        'species': '',
        'relationship': '使用者的 Bridge Brain 角色外殼',
        'inspiration': '',
        'mbtiCode': companion.mbtiCode,
        'personalityTags': companion.personalityTags
            .map((tag) => tag.name)
            .toList(),
      },
      'voice': {
        'speakingStyle': _speakingStyleFor(companion),
        'toneRules': _toneRulesFor(companion),
        'sampleLines': <String>[],
      },
      'capabilities': {
        'specialFunction': companion.roleName,
        'expertise': [companion.role.name],
        'preferredModes': _preferredModesFor(companion.role),
      },
      'appearance': {
        'artStyle': '',
        'appearancePrompt': companion.appearancePrompt,
        'generatedDescription': companion.appearanceDescription,
        // [教練 Agent 2026-08-04] appearanceSeed 已刪除
        // 'appearanceSeed': companion.appearanceSeed,
        'avatar': assetManifest['primaryAvatar'],
        'avatarImagePath': primaryImagePath ?? companion.avatarImagePath ?? '',
        'avatarAnimationPath':
            primaryAnimationPath ?? companion.avatarAnimationPath ?? '',
        'portrait': stateAssets.isEmpty ? '' : stateAssets.first['id'],
        'portraitImagePath':
            primaryImagePath ?? companion.avatarImagePath ?? '',
        'portraitAnimationPath':
            primaryAnimationPath ?? companion.avatarAnimationPath ?? '',
        'palette': [if (mbti != null) mbti.colorHex],
      },
      'activitySet': {
        'moods': {
          for (final state in stateAssets) state['stateId']: state['mood'],
        },
        'actions': {
          for (final state in stateAssets) state['stateId']: state['action'],
        },
        'labels': {
          for (final state in stateAssets) state['stateId']: state['label'],
        },
        'triggers': {
          for (final state in stateAssets) state['stateId']: state['trigger'],
        },
      },
      'desktopBehavior': {
        'idleBehaviors': ['wander', 'lookAround'],
        'workBehaviors': ['reading', 'pointing'],
        'celebrationBehaviors': ['bounce'],
        'maxDistractionLevel': 'low',
      },
      'transurfingProfile': {
        'attentionStyle': '先收束注意力，再接工具。',
        'pendulumWarnings': ['urgency', 'comparison', 'platformPull'],
        'doorPreference': '優先尋找使用者自己的門。',
        'flowGuidance': '先找最低阻力下一步。',
      },
      'gamification': {
        'unlockableCosmetics': <String>[],
        'achievementHints': <String>[],
        'xpAffinity': [companion.role.name],
      },
      'permissions': {
        'riskLevel': 'L0',
        'requires': <String>[],
        'optional': <String>[],
        'forbidden': [
          'memory.private.read',
          'apiKey.read',
          'chatHistory.export',
          'browser.session.read',
        ],
      },
      'safety': {
        'containsUserMemory': false,
        'containsApiKeys': false,
        'containsExecutableCode': false,
        'reviewStatus': 'local-export',
        ...?(commercialUseAllowed == null
            ? null
            : {
                'commercialUseAllowed': commercialUseAllowed,
                'commercialUsePolicy': commercialUseAllowed
                    ? 'user_allows_commercial_use'
                    : 'user_does_not_allow_commercial_use',
              }),
        if (companion.rightsPassport != null)
          'rightsPassport': companion.rightsPassport!.toJson(),
        if (_isLocalOnlyPassport(companion.rightsPassport)) 'localOnly': true,
        if (_isLocalOnlyPassport(companion.rightsPassport))
          'localOnlyOwnerId': _localInstallId,
        'contentWarnings': <String>[],
      },
      'assets': {
        'included': includedAssets,
        'external': <String>[],
        'manifest': assetManifest,
      },
      'exportedAt': DateTime.now().toIso8601String(),
    };
  }

  bool _isLocalOnlyPassport(CompanionRightsPassport? passport) {
    return passport?.signal == CompanionRightsSignal.watching ||
        passport?.signal == CompanionRightsSignal.blocked;
  }

  Companion importFromJson(String jsonString) {
    final pack = previewFromJson(jsonString).pack;
    // [教練 Agent 2026-06-28] OOM 修復：匯入時把 base64 data URI 圖片存到 app 檔案系統
    // 不在記憶體裡保留 base64 字串
    return importFromPackJson(pack);
  }

  /// [教練 Agent 2026-06-28] 把 pack 裡的 base64 data URI 圖片存到 app documents，
  /// 替換成 file path。降低 Companion 物件在記憶體中的大小。
  Future<Companion> importFromJsonAsync(String jsonString) async {
    final preview = previewFromJson(jsonString);
    final pack = Map<String, dynamic>.from(preview.pack);

    // 處理 avatarImagePath
    final appearance = _mapAt(pack, 'appearance');
    final avatarPath = _stringAt(appearance, 'avatarImagePath');
    if (avatarPath.startsWith('data:image/')) {
      try {
        final newPath = await _saveDataUriToFile(avatarPath);
        appearance['avatarImagePath'] = newPath;
      } catch (_) {}
    }

    // 處理 stateImagePaths
    final states = pack['states'];
    if (states is List) {
      for (final state in states) {
        if (state is Map<String, dynamic>) {
          final imgPath = _stringAt(state, 'imagePath');
          if (imgPath.startsWith('data:image/')) {
            try {
              final newPath = await _saveDataUriToFile(imgPath);
              state['imagePath'] = newPath;
            } catch (_) {}
          }
        }
      }
    }

    return importFromPackJson(pack);
  }

  /// [教練 Agent 2026-06-28] 把 data URI 解碼存到 app documents/images/
  Future<String> _saveDataUriToFile(String dataUri) async {
    final commaIndex = dataUri.indexOf(',');
    if (commaIndex < 0) return dataUri;
    final encoded = dataUri.substring(commaIndex + 1);
    final bytes = base64Decode(encoded);
    final dir = await _getImagesDir();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('$dir/companion_img_$timestamp.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Companion importFromPackJson(Map<String, dynamic> pack) {
    if (pack['schema'] != schema) {
      throw const CompanionPackException('角色包 schema 不支援。');
    }
    _assertSafe(pack);

    final identity = _mapAt(pack, 'identity');
    final appearance = _mapAt(pack, 'appearance');
    final safety = _mapAt(pack, 'safety');
    final stateImagePaths = _stateImagePathsFromPack(pack);
    final stateAnimationPaths = _stateAnimationPathsFromPack(pack);
    final name = _stringAt(pack, 'name', fallback: '').trim();
    if (name.isEmpty) {
      throw const CompanionPackException('角色包缺少 name。');
    }

    final mbtiCode = _stringAt(
      identity,
      'mbtiCode',
      fallback: 'ENFJ',
    ).toUpperCase();

    return Companion(
      id: _idFactory?.call() ?? CompanionStore.generateId(),
      name: name,
      mbtiCode: MBTIType.fromCode(mbtiCode)?.code ?? 'ENFJ',
      role: _roleFrom(_stringAt(identity, 'role', fallback: 'general')),
      personalityTags: _personalityTagsFrom(identity['personalityTags']),
      appearancePrompt: _stringAt(appearance, 'appearancePrompt'),
      appearanceDescription: _stringAt(appearance, 'generatedDescription'),
      // [教練 Agent 2026-08-04] appearanceSeed 已刪除，固定為 0
      // appearanceSeed: _intAt(appearance, 'appearanceSeed'),
      avatarImagePath: _stringAt(appearance, 'avatarImagePath'),
      avatarAnimationPath: _stringAt(appearance, 'avatarAnimationPath'),
      stateImagePaths: stateImagePaths,
      stateAnimationPaths: stateAnimationPaths,
      rightsPassport: safety['rightsPassport'] is Map
          ? CompanionRightsPassport.fromJson(
              Map<String, dynamic>.from(safety['rightsPassport'] as Map),
            )
          : null,
      trustBoundary: const TrustBoundary(
        autoExecute: false,
        confirmBeforeSend: true,
        dataRetentionDays: 30,
        allowFileAccess: false,
      ),
    );
  }

  CompanionPackPreview previewFromJson(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is Map<String, dynamic>) {
      return previewFromPackJson(decoded);
    }
    if (decoded is Map) {
      return previewFromPackJson(Map<String, dynamic>.from(decoded));
    }
    throw const CompanionPackException('角色包格式錯誤：根節點必須是物件。');
  }

  CompanionPackPreview previewFromPackJson(Map<String, dynamic> pack) {
    if (pack['schema'] != schema) {
      throw const CompanionPackException('角色包 schema 不支援。');
    }

    final identity = _mapAt(pack, 'identity');
    final voice = _mapAt(pack, 'voice');
    final capabilities = _mapAt(pack, 'capabilities');
    final appearance = _mapAt(pack, 'appearance');
    final permissions = _mapAt(pack, 'permissions');
    final safety = _mapAt(pack, 'safety');
    final author = _mapAt(pack, 'author');
    final name = _stringAt(pack, 'name', fallback: '').trim();
    if (name.isEmpty) {
      throw const CompanionPackException('角色包缺少 name。');
    }

    return CompanionPackPreview(
      pack: pack,
      id: _stringAt(pack, 'id'),
      version: _stringAt(pack, 'version', fallback: '0.1.0'),
      name: name,
      summary: _stringAt(pack, 'summary'),
      authorName: _stringAt(author, 'name'),
      license: _stringAt(pack, 'license'),
      tags: _stringListAt(pack['tags']),
      role: _stringAt(identity, 'role', fallback: 'general'),
      mbtiCode: _stringAt(identity, 'mbtiCode', fallback: 'ENFJ'),
      personalityTags: _stringListAt(identity['personalityTags']),
      speakingStyle: _stringAt(voice, 'speakingStyle'),
      toneRules: _stringListAt(voice['toneRules']),
      specialFunction: _stringAt(capabilities, 'specialFunction'),
      expertise: _stringListAt(capabilities['expertise']),
      appearancePrompt: _stringAt(appearance, 'appearancePrompt'),
      appearanceDescription: _stringAt(appearance, 'generatedDescription'),
      palette: _stringListAt(appearance['palette']),
      riskLevel: _stringAt(permissions, 'riskLevel', fallback: 'L0'),
      requiredPermissions: _stringListAt(permissions['requires']),
      optionalPermissions: _stringListAt(permissions['optional']),
      containsUserMemory: safety['containsUserMemory'] == true,
      containsApiKeys: safety['containsApiKeys'] == true,
      containsExecutableCode: safety['containsExecutableCode'] == true,
      localOnly: safety['localOnly'] == true,
      localOnlyAllowed: _localOnlyAllowed(safety),
      reviewStatus: _stringAt(safety, 'reviewStatus', fallback: 'unreviewed'),
      contentWarnings: _stringListAt(safety['contentWarnings']),
    );
  }

  void _assertSafe(Map<String, dynamic> pack) {
    final safety = _mapAt(pack, 'safety');
    final unsafeReasons = <String>[
      if (safety['containsUserMemory'] == true) '含有使用者記憶',
      if (safety['containsApiKeys'] == true) '含有 API Key',
      if (safety['containsExecutableCode'] == true) '含有可執行程式碼',
      if (safety['localOnly'] == true && !_localOnlyAllowed(safety))
        '本機限定角色包只能在原本裝置匯入',
    ];
    if (unsafeReasons.isNotEmpty) {
      throw CompanionPackException('角色包未通過安全檢查：${unsafeReasons.join('、')}。');
    }
  }

  bool _localOnlyAllowed(Map<String, dynamic> safety) {
    if (safety['localOnly'] != true) return true;
    final ownerId = _stringAt(safety, 'localOnlyOwnerId');
    return ownerId.isNotEmpty && ownerId == _localInstallId;
  }

  static String _speakingStyleFor(Companion companion) {
    final tags = companion.personalityTags.map((tag) => tag.name).join(', ');
    return tags.isEmpty ? companion.roleName : '${companion.roleName}，$tags';
  }

  static List<String> _toneRulesFor(Companion companion) {
    final rules = <String>[];
    for (final tag in companion.personalityTags) {
      switch (tag) {
        case PersonalityTag.concise:
          rules.add('保持簡潔，先給重點。');
        case PersonalityTag.detailed:
          rules.add('補足背景、步驟與推理。');
        case PersonalityTag.humorous:
          rules.add('在不干擾任務時加入輕鬆語氣。');
        case PersonalityTag.precise:
          rules.add('用詞精準，避免模糊承諾。');
        case PersonalityTag.warm:
          rules.add('保持溫暖與同理心。');
        case PersonalityTag.direct:
          rules.add('直接指出下一步。');
      }
    }
    return rules;
  }

  static List<String> _preferredModesFor(CompanionRole role) {
    return switch (role) {
      CompanionRole.research => ['review', 'document', 'chat'],
      CompanionRole.writing => ['creative', 'document', 'chat'],
      CompanionRole.translation => ['document', 'chat'],
      CompanionRole.farmManager => ['reminder', 'document', 'chat'],
      CompanionRole.general => ['chat'],
      CompanionRole.custom => ['chat'],
    };
  }

  static CompanionRole _roleFrom(String value) {
    return CompanionRole.values.firstWhere(
      (role) => role.name == value,
      orElse: () => CompanionRole.general,
    );
  }

  static List<PersonalityTag> _personalityTagsFrom(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map(
          (name) => PersonalityTag.values.firstWhere(
            (tag) => tag.name == name,
            orElse: () => PersonalityTag.warm,
          ),
        )
        .toList();
  }

  static Map<String, String> _stateImagePathsFromPack(
    Map<String, dynamic> pack,
  ) {
    final manifest = _manifestFromPack(pack);
    final states = manifest['states'];
    if (states is! List) return const {};
    final paths = <String, String>{};
    for (final state in states) {
      final stateMap = state is Map<String, dynamic>
          ? state
          : state is Map
          ? Map<String, dynamic>.from(state)
          : null;
      if (stateMap == null) continue;
      final stateId = _stringAt(stateMap, 'stateId').trim();
      final imagePath = _stateImagePath(stateMap).trim();
      if (stateId.isNotEmpty && imagePath.isNotEmpty) {
        paths[stateId] = imagePath;
      }
    }
    return paths;
  }

  static Map<String, String> _stateAnimationPathsFromPack(
    Map<String, dynamic> pack,
  ) {
    final manifest = _manifestFromPack(pack);
    final states = manifest['states'];
    if (states is! List) return const {};
    final paths = <String, String>{};
    for (final state in states) {
      final stateMap = state is Map<String, dynamic>
          ? state
          : state is Map
          ? Map<String, dynamic>.from(state)
          : null;
      if (stateMap == null) continue;
      final stateId = _stringAt(stateMap, 'stateId').trim();
      final animation = _mapAt(stateMap, 'animation');
      final animationPath = _stringAt(animation, 'path').trim();
      if (stateId.isNotEmpty && animationPath.isNotEmpty) {
        paths[stateId] = animationPath;
      }
    }
    return paths;
  }

  static String _stateImagePath(Map<String, dynamic> state) {
    final direct = _stringAt(state, 'imagePath').trim();
    if (direct.isNotEmpty) return direct;
    final still = _mapAt(state, 'still');
    return _stringAt(still, 'path');
  }

  static Map<String, dynamic> _manifestFromPack(Map<String, dynamic> pack) {
    final assets = _mapAt(pack, 'assets');
    return _mapAt(assets, 'manifest');
  }

  static Map<String, dynamic> _mapAt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _stringAt(
    Map<String, dynamic> json,
    String key, {
    String fallback = '',
  }) {
    final value = json[key];
    return value is String ? value : fallback;
  }

  static int _intAt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static List<String> _stringListAt(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }
}

/// [教練 Agent 2026-06-28] ZIP 匯出用的圖片檔案映射
class _ZipImageEntry {
  final File file;
  final String zipPath;
  _ZipImageEntry(this.file, this.zipPath);
}
