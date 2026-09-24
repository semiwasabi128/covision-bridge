import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// macOS 本機 WAV/MP3 播放器。
///
/// 以系統 `afplay` 播放暫存音檔，避免額外引入尚未使用的 audio plugin。
/// 目前只在 desktop/macOS 使用；其他平台安全地回傳未支援錯誤。
class NativeAudioBytesPlayer {
  Process? _process;
  File? _currentFile;

  bool get isPlaying => _process != null;

  Future<void> play(Uint8List bytes, {String extension = 'wav'}) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('NativeAudioBytesPlayer 目前只支援 macOS');
    }
    await stop();
    final tempDir = await Directory.systemTemp.createTemp('bridge_tts_');
    final file = File('${tempDir.path}/speech.$extension');
    await file.writeAsBytes(bytes, flush: true);
    _currentFile = file;
    _process = await Process.start('afplay', [file.path]);
    final process = _process!;
    unawaited(process.exitCode.then((_) async {
      if (identical(_process, process)) {
        _process = null;
        await _cleanup();
      }
    }));
    await process.exitCode;
  }

  Future<void> stop() async {
    final process = _process;
    _process = null;
    process?.kill(ProcessSignal.sigterm);
    await _cleanup();
  }

  Future<void> dispose() => stop();

  Future<void> _cleanup() async {
    final file = _currentFile;
    _currentFile = null;
    if (file == null) return;
    try {
      await file.parent.delete(recursive: true);
    } catch (_) {
      // 暫存檔清理失敗不應影響對話。
    }
  }
}
