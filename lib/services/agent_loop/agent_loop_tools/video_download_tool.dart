// video_download_tool.dart
// 影片分析工具 #1：下載影片
//
// 讓原生 Agent能透過 yt-dlp 下載網路影片到本機，供後續截圖、轉文字等分析使用。
// 依賴：yt-dlp（brew install yt-dlp）
// 下載路徑：/tmp/bridge_video.<ext>
// 超時：300 秒

import 'dart:async';
import 'dart:io';

import '../agent_tool.dart';

class VideoDownloadTool extends AgentTool {
  @override
  String get name => 'video_download';

  @override
  String get description =>
      '使用 yt-dlp 下載網路影片到本機 /tmp/bridge_video.<ext>。'
      '支援 YouTube、Twitter/X、Instagram 等數百個平台。'
      '下載完成後回傳影片檔案路徑，可搭配 frame_extract 和 audio_transcribe 進行影片分析。'
      '依賴：yt-dlp（未安裝時提示 brew install yt-dlp）。'
      '超時：300 秒。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'url',
          description: '影片 URL（如 https://www.youtube.com/watch?v=...）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'quality',
          description: '影片畫質高度（像素），例如 720、1080、480',
          defaultValue: '720',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final url = args['url']?.toString() ?? '';
      if (url.isEmpty) {
        return AgentToolResult.failure('url 參數為必填');
      }

      final quality =
          int.tryParse(args['quality']?.toString() ?? '720') ?? 720;

      // 1. 檢查 yt-dlp 是否安裝
      final whichResult = await Process.run('which', ['yt-dlp']);
      if (whichResult.exitCode != 0) {
        return AgentToolResult.failure(
          'yt-dlp 未安裝。請先安裝：\n'
          '  brew install yt-dlp\n'
          '安裝後重新執行此工具。',
        );
      }

      // 2. 執行 yt-dlp 下載影片
      // --format：選擇最高畫質 ≤ 指定高度
      // --print after_move:filepath：下載完成後印出最終檔案路徑
      // --no-playlist：只下載單一影片，不抓整個播放清單
      final result = await Process.start(
        'yt-dlp',
        [
          '--no-playlist',
          '--format', 'bestvideo[height<=$quality]+bestaudio/best[height<=$quality]/best',
          '--merge-output-format', 'mp4',
          '--print', 'after_move:filepath',
          '-o', '/tmp/bridge_video.%(ext)s',
          url,
        ],
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      final stdoutSub = result.stdout
          .transform(const SystemEncoding().decoder)
          .listen(stdoutBuffer.write);
      final stderrSub = result.stderr
          .transform(const SystemEncoding().decoder)
          .listen(stderrBuffer.write);

      // 超時 300 秒
      final exitCode = await result.exitCode.timeout(
        const Duration(seconds: 300),
        onTimeout: () {
          result.kill(ProcessSignal.sigkill);
          return -1;
        },
      );

      await stdoutSub.cancel();
      await stderrSub.cancel();

      final stdout = stdoutBuffer.toString().trim();
      final stderr = stderrBuffer.toString().trim();

      if (exitCode == -1) {
        return AgentToolResult.failure('影片下載超時（300 秒）。影片可能過長或網路太慢。');
      }

      if (exitCode != 0) {
        return AgentToolResult.failure(
          'yt-dlp 下載失敗（exit code: $exitCode）。\nstderr: $stderr',
        );
      }

      // --print after_move:filepath 會在最後一行印出下載後的檔案路徑
      final lines = stdout.split('\n');
      final filePath = lines.isNotEmpty ? lines.last.trim() : '';

      if (filePath.isEmpty) {
        return AgentToolResult.failure(
          '下載完成但無法取得檔案路徑。stdout: $stdout',
        );
      }

      // 確認檔案存在
      final file = File(filePath);
      if (!await file.exists()) {
        return AgentToolResult.failure(
          '下載回報路徑但檔案不存在：$filePath\nstdout: $stdout',
        );
      }

      final fileSize = await file.length();

      return AgentToolResult.success(
        '影片下載完成。\n'
        '檔案路徑：$filePath\n'
        '檔案大小：${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB\n'
        '畫質：${quality}p',
        metadata: {
          'video_path': filePath,
          'file_size_bytes': fileSize,
          'quality': quality,
          'url': url,
        },
      );
    } catch (e) {
      return AgentToolResult.failure('影片下載失敗：$e');
    }
  }
}
