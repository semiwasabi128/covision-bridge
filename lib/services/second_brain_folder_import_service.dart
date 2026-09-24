import 'dart:io';

import '../models/second_brain_file_index.dart';
import 'second_brain_content_digest_service.dart';
import 'second_brain_file_index_store.dart';

class SecondBrainFolderImportResult {
  final String rootPath;
  final int scannedCount;
  final int indexedCount;
  final int digestedCount;
  final List<SecondBrainFileEntry> entries;

  const SecondBrainFolderImportResult({
    required this.rootPath,
    required this.scannedCount,
    required this.indexedCount,
    this.digestedCount = 0,
    required this.entries,
  });
}

class SecondBrainFolderImportService {
  final SecondBrainFileIndexStore store;
  final SecondBrainContentDigestService digestService;

  const SecondBrainFolderImportService({
    this.store = const SecondBrainFileIndexStore(),
    this.digestService = const SecondBrainContentDigestService(),
  });

  Future<SecondBrainFolderImportResult> importFolder(
    String rootPath, {
    SecondBrainRoom room = SecondBrainRoom.files,
    bool recursive = true,
    int maxFiles = 120,
    bool digestTextContent = true,
    bool autoClassifyRoom = true,
  }) async {
    final root = Directory(rootPath.trim());
    if (!await root.exists()) {
      return SecondBrainFolderImportResult(
        rootPath: rootPath,
        scannedCount: 0,
        indexedCount: 0,
        digestedCount: 0,
        entries: const [],
      );
    }

    var scanned = 0;
    var digested = 0;
    final entries = <SecondBrainFileEntry>[];
    final now = DateTime.now();
    await for (final entity in root.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entries.length >= maxFiles) break;
      if (entity is! File) continue;
      scanned++;
      final path = entity.path;
      if (_shouldSkip(path)) continue;

      final stat = await entity.stat();
      final extension = _extensionFor(path);
      final title = _basename(path);
      final parent = _parentName(path);
      final digest = digestTextContent
          ? await digestService.digestFile(
              entity,
              title: title,
              extension: extension,
              fallbackRoom: room,
            )
          : null;
      if (digest != null) digested++;
      final resolvedRoom = autoClassifyRoom && room == SecondBrainRoom.files
          ? digest?.room ?? room
          : room;
      final entry = SecondBrainFileEntry(
        id: '',
        title: title,
        path: path,
        room: resolvedRoom,
        summary:
            digest?.summary ??
            _summaryFor(
              title: title,
              extension: extension,
              parent: parent,
              size: stat.size,
            ),
        contentDigest: digest?.summary ?? '',
        contentExcerpt: digest?.excerpt ?? '',
        tags: [
          resolvedRoom.zhLabel,
          if (extension.isNotEmpty) extension,
          if (parent.isNotEmpty) parent,
          ...?digest?.keywords.take(5),
        ],
        keywords: digest?.keywords ?? const [],
        indexedAt: now,
        trustScore: digest == null ? 62 : 72,
      );
      entries.add(entry);
      await store.upsert(entry);
    }

    return SecondBrainFolderImportResult(
      rootPath: root.path,
      scannedCount: scanned,
      indexedCount: entries.length,
      digestedCount: digested,
      entries: entries,
    );
  }

  bool _shouldSkip(String path) {
    final parts = path.split(RegExp(r'[/\\]+'));
    if (parts.any((part) => part.startsWith('.'))) return true;
    final extension = _extensionFor(path);
    const supported = {
      'txt',
      'md',
      'markdown',
      'pdf',
      'doc',
      'docx',
      'rtf',
      'csv',
      'tsv',
      'json',
      'yaml',
      'yml',
      'png',
      'jpg',
      'jpeg',
      'webp',
      'gif',
    };
    return extension.isNotEmpty && !supported.contains(extension);
  }

  String _summaryFor({
    required String title,
    required String extension,
    required String parent,
    required int size,
  }) {
    final fileType = extension.isEmpty ? '檔案' : extension.toUpperCase();
    final location = parent.isEmpty ? '匯入資料夾' : '「$parent」';
    return '$fileType 檔案「$title」，位於 $location，已建立第二大腦索引 metadata，大小 ${_formatBytes(size)}。';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _basename(String path) {
    final parts = path.split(RegExp(r'[/\\]+'));
    return parts.isEmpty ? path : parts.last;
  }

  String _parentName(String path) {
    final parts = path.split(RegExp(r'[/\\]+'));
    if (parts.length < 2) return '';
    return parts[parts.length - 2];
  }

  String _extensionFor(String path) {
    final name = _basename(path);
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}
