// audio_transcribe_tool.dart
// 影片分析工具 #3：語音轉文字
//
// 讓原生 Agent能從影片中提取音訊並轉為逐字稿，用於理解影片中的對話和旁白。
// 流程：
//   1. ffmpeg 提取音訊（16kHz 單聲道 PCM WAV）
//   2. whisper 轉文字（base 模型）
//   3. 讀取逐字稿回傳
// 依賴：ffmpeg + whisper（brew install ffmpeg whisper）
// 超時：600 秒（Whisper 較慢）

import 'dart:async';
import 'dart:io';

import '../agent_tool.dart';

class AudioTranscribeTool extends AgentTool {
  @override
  String get name => 'audio_transcribe';

  @override
  String get description =>
      '從影片提取音訊並轉為逐字稿。先使用 ffmpeg 提取音訊，再用 OpenAI Whisper 轉文字。'
      '適用於理解影片中的對話、旁白、演講內容。'
      '依賴：ffmpeg + whisper（未安裝時提示安裝方式）。'
      '超時：600 秒（Whisper 處理較慢）。';

  @override
  List<AgentToolParamSpec> get paramSpecs => const [
        AgentToolParamSpec(
          name: 'video_path',
          description: '影片檔案路徑（如 /tmp/bridge_video.mp4）',
          required: true,
        ),
        AgentToolParamSpec(
          name: 'language',
          description: '音訊語言（如 Chinese、English、Japanese），傳給 Whisper --language',
          defaultValue: 'Chinese',
        ),
      ];

  @override
  Future<AgentToolResult> execute(Map<String, dynamic> args) async {
    try {
      final videoPath = args['video_path']?.toString() ?? '';
      if (videoPath.isEmpty) {
        return AgentToolResult.failure('video_path 參數為必填');
      }

      final language = (args['language']?.toString().isNotEmpty == true)
          ? args['language'].toString()
          : 'Chinese';

      // 確認影片檔案存在
      final videoFile = File(videoPath);
      if (!await videoFile.exists()) {
        return AgentToolResult.failure('影片檔案不存在：$videoPath');
      }

      // 1. 檢查 ffmpeg 是否安裝
      final ffmpegCheck = await Process.run('which', ['ffmpeg']);
      if (ffmpegCheck.exitCode != 0) {
        return AgentToolResult.failure(
          'ffmpeg 未安裝。請先安裝：\n  brew install ffmpeg',
        );
      }

      // 2. 檢查 whisper 是否安裝
      final whisperCheck = await Process.run('which', ['whisper']);
      if (whisperCheck.exitCode != 0) {
        return AgentToolResult.failure(
          'whisper 未安裝。請先安裝：\n'
          '  pip install openai-whisper\n'
          '或參考 https://github.com/openai/whisper 安裝說明',
        );
      }

      // 3. 用 ffmpeg 提取音訊（16kHz 單聲道 PCM WAV）
      const audioPath = '/tmp/audio.wav';
      final extractResult = await Process.start(
        'ffmpeg',
        [
          '-i', videoPath,
          '-vn', // 不要影片
          '-acodec', 'pcm_s16le',
          '-ar', '16000', // 16kHz
          '-ac', '1', // 單聲道
          '-y', // 覆蓋
          audioPath,
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
        const Duration(seconds: 60),
        onTimeout: () {
          extractResult.kill(ProcessSignal.sigkill);
          return -1;
        },
      );

      await extractStdoutSub.cancel();
      await extractStderrSub.cancel();

      if (extractExitCode == -1) {
        return AgentToolResult.failure('音訊提取超時（60 秒）。');
      }

      if (extractExitCode != 0) {
        return AgentToolResult.failure(
          'ffmpeg 音訊提取失敗（exit code: $extractExitCode）。\n'
          'stderr: ${extractStderrBuffer.toString()}',
        );
      }

      // 確認音訊檔案存在
      if (!await File(audioPath).exists()) {
        return AgentToolResult.failure('音訊提取失敗——輸出檔案不存在：$audioPath');
      }

      // 4. 用 whisper 轉文字
      // whisper /tmp/audio.wav --model base --language {language} --output_format txt --output_dir /tmp/
      final transcribeResult = await Process.start(
        'whisper',
        [
          audioPath,
          '--model', 'base',
          '--language', language,
          '--output_format', 'txt',
          '--output_dir', '/tmp/',
        ],
      );

      final transcribeStdoutBuffer = StringBuffer();
      final transcribeStderrBuffer = StringBuffer();
      final transcribeStdoutSub = transcribeResult.stdout
          .transform(const SystemEncoding().decoder)
          .listen(transcribeStdoutBuffer.write);
      final transcribeStderrSub = transcribeResult.stderr
          .transform(const SystemEncoding().decoder)
          .listen(transcribeStderrBuffer.write);

      // 超時 600 秒（Whisper 較慢）
      final transcribeExitCode = await transcribeResult.exitCode.timeout(
        const Duration(seconds: 600),
        onTimeout: () {
          transcribeResult.kill(ProcessSignal.sigkill);
          return -1;
        },
      );

      await transcribeStdoutSub.cancel();
      await transcribeStderrSub.cancel();

      if (transcribeExitCode == -1) {
        return AgentToolResult.failure(
          'Whisper 轉文字超時（600 秒）。影片可能過長，建議分段處理。',
        );
      }

      if (transcribeExitCode != 0) {
        return AgentToolResult.failure(
          'Whisper 轉文字失敗（exit code: $transcribeExitCode）。\n'
          'stderr: ${transcribeStderrBuffer.toString()}',
        );
      }

      // 5. 讀取逐字稿
      const transcriptPath = '/tmp/audio.txt';
      final transcriptFile = File(transcriptPath);
      if (!await transcriptFile.exists()) {
        return AgentToolResult.failure(
          'Whisper 執行完成但逐字稿檔案不存在：$transcriptPath\n'
          'stdout: ${transcribeStdoutBuffer.toString()}',
        );
      }

      final transcript = await transcriptFile.readAsString();

      if (transcript.trim().isEmpty) {
        return AgentToolResult.failure(
          '逐字稿為空——影片可能沒有可辨識的語音內容，或音訊品質太差。',
        );
      }

      return AgentToolResult.success(
        transcript.trim(),
        metadata: {
          'video_path': videoPath,
          'language': language,
          'transcript_length': transcript.length,
          'audio_path': audioPath,
        },
      );
    } catch (e) {
      return AgentToolResult.failure('語音轉文字失敗：$e');
    }
  }
}
