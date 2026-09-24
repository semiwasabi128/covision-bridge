// frame_extract_tool.dart
// 影片分析工具 #2：場景偵測截圖
//
// 讓原生 Agent能從影片中擷取關鍵場景截圖，供視覺分析使用。
// 流程：
//   1. ffmpeg 場景偵測取得時間戳列表
//   2. 每個時間戳 +1 秒截圖（scale=512 寬度）
//   3. 回傳所有截圖路徑
// 依賴：ffmpeg（brew install ffmpeg）
// 超時：120 秒

import 'dart:async';
import 'dart:io';

import '../agent_tool.dart';

class FrameExtractTool extends AgentTool {
  @override
  String get name => 'frame_extract';

  @override
  String get description =>
      '從影片中擷取關鍵場景截圖。使用 ffmpeg 場景偵測（scene detection）自動找出畫面變化點，'
      '在每個場景變化處 +1 秒截圖。回傳所有截圖檔案路徑列表，可搭配 local_vision_analyze 逐張分析。'
      '依賴：ffmpeg（未安裝時提示 brew install ffmpeg）。'
      '超時：120 秒。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'video_path',
          description: '影片檔案路徑（如 /tmp/bridge_video.mp4）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'threshold',
          description: '場景偵測靈敏度（0.0~1.0），值越低偵測越靈敏、截圖越多',
          defaultValue: '0.5',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final videoPath = args['video_path']?.toString() ?? '';
      if (videoPath.isEmpty) {
        return AgentToolResult.failure('video_path 參數為必填');
      }

      final threshold =
          double.tryParse(args['threshold']?.toString() ?? '0.5') ?? 0.5;

      // 確認影片檔案存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        return AgentToolResult.failure('影片檔案不存在：$videoPath');
      }

      // 1. 檢查 ffmpeg 是否安裝
      final whichResult = await Process.run('which', ['ffmpeg']);
      if (whichResult.exitCode != 0) {
        return AgentToolResult.failure(
          'ffmpeg 未安裝。請先安裝：\n'
          '  brew install ffmpeg\n'
          '安裝後重新執行此工具。',
        );
      }

      // 2. 場景偵測——取得時間戳列表
      // ffmpeg -i {video} -vf "select='gt(scene,{threshold})',showinfo" -vsync vfr -f null - 2>&1
      // showinfo 會在 stderr 輸出 "pts_time:123.456" 格式的時間戳
      final sceneResult = await Process.start(
        'ffmpeg',
        [
          '-i', videoPath,
          '-vf', "select='gt(scene,$threshold)',showinfo",
          '-vsync', 'vfr',
          '-f', 'null',
          '-',
        ],
      );

      final sceneStderrBuffer = StringBuffer();
      final sceneStdoutSub = sceneResult.stdout
          .transform(const SystemEncoding().decoder)
          .listen((_) {}); // stdout 通常為空
      final sceneStderrSub = sceneResult.stderr
          .transform(const SystemEncoding().decoder)
          .listen(sceneStderrBuffer.write);

      final sceneExitCode = await sceneResult.exitCode.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          sceneResult.kill(ProcessSignal.sigkill);
          return -1;
        },
      );

      await sceneStdoutSub.cancel();
      await sceneStderrSub.cancel();

      if (sceneExitCode == -1) {
        return AgentToolResult.failure('場景偵測超時（60 秒）。影片可能過長。');
      }

      // 3. 解析 showinfo 輸出取得 pts_time 時間戳
      // showinfo 輸出格式範例：
      //   [Parsed_showinfo_1 @ 0x...] n: 0 pts: 0 pts_time:0.000000 ...
      final sceneOutput = sceneStderrBuffer.toString();
      final timestamps = <double>[];
      final ptsTimeRegex = RegExp(r'pts_time:(\d+\.?\d*)');

      for (final match in ptsTimeRegex.allMatches(sceneOutput)) {
        final ts = double.tryParse(match.group(1) ?? '');
        if (ts != null) {
          timestamps.add(ts);
        }
      }

      // 如果沒有偵測到場景變化，至少截第 0 秒
      if (timestamps.isEmpty) {
        timestamps.add(0.0);
      }

      // 4. 每個時間戳 +1 秒截圖
      final framePaths = <String>[];
      for (var i = 0; i < timestamps.length; i++) {
        final captureTime = timestamps[i] + 1.0;
        final outputNum = (i + 1).toString().padLeft(3, '0');
        final outputPath = '/tmp/frame_$outputNum.jpg';

        final extractResult = await Process.start(
          'ffmpeg',
          [
            '-ss', captureTime.toStringAsFixed(3),
            '-i', videoPath,
            '-frames:v', '1',
            '-q:v', '2',
            '-vf', 'scale=512:-1',
            '-y', // 覆蓋已存在檔案
            outputPath,
          ],
        );

        final extractStderrBuffer = StringBuffer();
        final extractStdoutSub = extractResult.stdout
            .transform(const SystemEncoding().decoder)
            .listen((_) {});
        final extractStderrSub = extractResult.stderr
            .transform(const SystemEncoding().decoder)
            .listen(extractStderrBuffer.write);

        final extractExitCode = await extractResult.exitCode.timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            extractResult.kill(ProcessSignal.sigkill);
            return -1;
          },
        );

        await extractStdoutSub.cancel();
        await extractStderrSub.cancel();

        if (extractExitCode == 0 && await File(outputPath).exists()) {
          framePaths.add(outputPath);
        }
        // 個別截圖失敗不中斷，繼續處理下一個時間戳
      }

      if (framePaths.isEmpty) {
        return AgentToolResult.failure(
          '截圖失敗——所有時間戳都無法截圖。請檢查影片檔案是否有效。\n'
          '場景偵測到 ${timestamps.length} 個時間戳。',
        );
      }

      return AgentToolResult.success(
        '截圖完成：${framePaths.length} 張，路徑：${framePaths.join(', ')}',
        metadata: {
          'frame_count': framePaths.length,
          'frame_paths': framePaths,
          'threshold': threshold,
          'video_path': videoPath,
          'scene_count': timestamps.length,
        },
      );
    } catch (e) {
      return AgentToolResult.failure('截圖失敗：$e');
    }
  }
}
