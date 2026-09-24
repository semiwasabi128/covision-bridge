// Voice Settings Screen — 夥伴語音設定頁
//
// [教練 Agent 2026-08-03] Phase 1 (C2)
//
// 對應設計稿 Part 3.3

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../../services/voice/companion_voice_settings.dart';
import '../../services/voice/companion_voice_settings_store.dart';
import '../../services/companion_store.dart';
import '../../services/tts/kokoro_tts_service.dart';
import '../../services/voice/native_audio_bytes_player.dart';
import '../../theme/bridge_design_system.dart';
import '../../theme/tier.dart';
import '../../theme/tier_style.dart';
import '../../widgets/adaptive_scaffold.dart';

class VoiceSettingsScreen extends StatefulWidget {
  final String companionId;
  final String? returnTo;
  final bool hideAppBar; // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏
  final VoidCallback? onBack; // [教練 Agent 2026-08-04 Phase E+] 內嵌模式返回 callback

  const VoiceSettingsScreen({
    super.key,
    required this.companionId,
    this.returnTo,
    this.hideAppBar = false,
    this.onBack,
  });

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  CompanionVoiceSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;

  // [小葵 2026-09-08] 測試播放改走 Kokoro 完整管線（主聲音+副聲音+混合比例+語速+情緒）。
  // 舊 flutter_tts 只套語速、完全忽略混合設定——使用者怎麼調聽起來都一樣。
  // 現在與 companion_create_screen._testVoicePlayback / 三個聊天 UI 同一路徑。
  final KokoroTtsService _kokoroTtsService = KokoroTtsService();
  final NativeAudioBytesPlayer _testPlayer = NativeAudioBytesPlayer();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await CompanionVoiceSettingsStore.load(widget.companionId);
    if (mounted) {
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_settings == null) return;
    setState(() => _isSaving = true);
    try {
      await CompanionVoiceSettingsStore.save(_settings!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('語音設定已儲存')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('儲存失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testPlay() async {
    if (_settings == null || _isTesting) return;
    setState(() => _isTesting = true);

    // [教練 Agent 2026-08-03] R2: 找不到 companion 直接返，不要 .first.first crash
    final allCompanions = CompanionStore().all;
    if (allCompanions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到任何夥伴')),
        );
        context.pop();
      }
      return;
    }
    final companion = allCompanions.firstWhere(
      (c) => c.id == widget.companionId,
      orElse: () => allCompanions.first,
    );
    final s = _settings!;
    final testText = '你好！我是${companion.name}，很高興見到你！';
    final blendDesc = s.secondaryVoice == null || s.voiceBlend >= 0.99
        ? s.primaryVoice
        : '${s.primaryVoice} ${(s.voiceBlend * 100).toStringAsFixed(0)}% + '
            '${s.secondaryVoice!} ${((1 - s.voiceBlend) * 100).toStringAsFixed(0)}%';

    try {
      // Kokoro 完整管線：混合聲音真正生效
      if (!_kokoroTtsService.isRunning) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎙 語音引擎啟動中（首次約需數秒）…'),
              duration: Duration(seconds: 10),
            ),
          );
        }
        final started = await _kokoroTtsService.startServer();
        if (!started) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Kokoro server 啟動失敗：${_kokoroTtsService.lastError}'),
              ),
            );
          }
          return;
        }
      }

      final result = await _kokoroTtsService.synthesize(
        KokoroTtsRequest(
          text: testText,
          voice: s.primaryVoice,
          secondaryVoice: s.secondaryVoice,
          voiceBlend: s.voiceBlend,
          speed: s.baseSpeed,
          emotion: s.emotionEnabled ? 'amused' : null,
          emotionSensitivity: s.emotionSensitivity,
        ),
      );
      await _testPlayer.play(result.audioBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ 播放完成，聲音：$blendDesc')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('測試播放失敗: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  void dispose() {
    unawaited(_testPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final s = _settings!;
    final ds = BridgeDSColors.of(context);
    // [教練 Agent 2026-08-03] R2: 找不到 companion 顯示「找不到夥伴」狀態，不要 crash
    final allCompanions = CompanionStore().all;
    if (allCompanions.isEmpty) {
      return Scaffold(
        backgroundColor: ds.canvas,
        // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏 AppBar
        appBar: widget.hideAppBar
            ? null
            : AppBar(
                title: const Text('語音設定'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48),
              SizedBox(height: 16),
              Text('找不到任何夥伴'),
              SizedBox(height: 8),
              Text('請先建立夥伴再開啟語音設定', style: TextStyle(color: BridgeDS.grey600)),
            ],
          ),
        ),
      );
    }
    final companion = allCompanions.firstWhere(
      (c) => c.id == widget.companionId,
      orElse: () => allCompanions.first,
    );

    return Scaffold(
      backgroundColor: ds.canvas,
      // [教練 Agent 2026-08-04 Phase E+] BridgeDesktop 內嵌時隱藏 AppBar
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('語音設定'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  // [教練 Agent 2026-08-04 Phase E+] 優先 callback → returnTo → pop → 預設
                  if (widget.onBack != null) {
                    widget.onBack!();
                  } else if (widget.returnTo != null) {
                    context.go(widget.returnTo!);
                  } else if (context.canPop()) {
                    // [小葵 2026-09-08] push 進來的（如夥伴設定→進階語音）返回就 pop 回原頁
                    context.pop();
                  } else {
                    context.go('/companion/control?id=${widget.companionId}');
                  }
                },
              ),
              actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('儲存'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 夥伴資訊
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ds.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: ds.accentMiro),
                const SizedBox(width: 12),
                Text(
                  companion.name,
                  style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: ds.textPrimary,
                    fontWeight: FontWeight.w600,),
                ),
                const Spacer(),
                Text(
                  kVoiceLabels[s.primaryVoice] ?? s.primaryVoice,
                  style: TierStyle.of(context, Tier.cardBody).toTextStyle().copyWith(color: ds.textTertiary,),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 🎙️ 聲音選擇
          _buildSection(
            icon: Icons.mic,
            title: '聲音選擇',
            children: [
              _buildVoiceDropdown(
                label: '主聲音',
                value: s.primaryVoice,
                excludeId: s.secondaryVoice,
                onChanged: (v) {
                  setState(() => _settings = s.copyWith(primaryVoice: v));
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('混合聲音'),
                subtitle: const Text('兩種聲音混合創造獨特音色'),
                value: s.secondaryVoice != null,
                onChanged: (v) {
                  setState(() => _settings = s.copyWith(
                    secondaryVoice: v ? (s.secondaryVoice ?? 'zf_xiaobei') : null,
                    voiceBlend: v ? 0.7 : 1.0,
                  ));
                },
              ),
              if (s.secondaryVoice != null) ...[
                const SizedBox(height: 8),
                _buildVoiceDropdown(
                  label: '副聲音',
                  value: s.secondaryVoice!,
                  excludeId: s.primaryVoice,
                  onChanged: (v) {
                    setState(() => _settings = s.copyWith(secondaryVoice: v));
                  },
                ),
                const SizedBox(height: 8),
                _buildSlider(
                  label: '混合比例',
                  value: s.voiceBlend,
                  min: 0.0, max: 1.0,
                  divisions: 10,
                  displayValue: '${(s.voiceBlend * 100).toStringAsFixed(0)}% 主聲音',
                  onChanged: (v) {
                    setState(() => _settings = s.copyWith(voiceBlend: v));
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // ⚡ 語速
          _buildSection(
            icon: Icons.speed,
            title: '語速',
            children: [
              _buildSlider(
                label: '基礎語速',
                value: s.baseSpeed,
                min: 0.5, max: 2.0,
                divisions: 15,
                displayValue: '${s.baseSpeed.toStringAsFixed(1)}x',
                onChanged: (v) {
                  setState(() => _settings = s.copyWith(baseSpeed: v));
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('情緒連動語速'),
                subtitle: const Text('開心自動 +10%，放鬆自動 -15%'),
                value: s.emotionSpeedCoupling,
                onChanged: (v) {
                  setState(() => _settings = s.copyWith(emotionSpeedCoupling: v));
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 😊 情緒表達
          _buildSection(
            icon: Icons.mood,
            title: '情緒表達',
            children: [
              SwitchListTile(
                title: const Text('情緒總開關'),
                value: s.emotionEnabled,
                onChanged: (v) {
                  setState(() => _settings = s.copyWith(emotionEnabled: v));
                },
              ),
              const SizedBox(height: 8),
              _buildSlider(
                label: '情緒敏感度',
                value: s.emotionSensitivity,
                min: 0.0, max: 1.0,
                divisions: 10,
                displayValue: _sensitivityLabel(s.emotionSensitivity),
                onChanged: s.emotionEnabled ? (v) {
                  setState(() => _settings = s.copyWith(emotionSensitivity: v));
                } : null,
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('可用情緒', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              ...kSupportedEmotions.map((emotion) {
                final isEnabled = s.enabledEmotions.contains(emotion);
                return CheckboxListTile(
                  title: Text(kEmotionLabels[emotion] ?? emotion),
                  value: isEnabled,
                  onChanged: s.emotionEnabled ? (v) {
                    final newSet = Set<String>.from(s.enabledEmotions);
                    if (v == true) {
                      newSet.add(emotion);
                    } else if (newSet.length > 1) {
                      newSet.remove(emotion);
                    }
                    setState(() => _settings = s.copyWith(enabledEmotions: newSet));
                  } : null,
                );
              }),
            ],
          ),
          const SizedBox(height: 16),

          // 進階
          _buildSection(
            icon: Icons.tune,
            title: '進階',
            children: [
              SwitchListTile(
                title: const Text('時間感知'),
                subtitle: const Text('22:00-06:00 自動放鬆語氣'),
                value: s.timeAware,
                onChanged: (v) {
                  setState(() => _settings = s.copyWith(timeAware: v));
                },
              ),
              SwitchListTile(
                title: const Text('情緒記憶'),
                subtitle: const Text('保持對話情緒連貫'),
                value: s.emotionMemory,
                onChanged: (v) {
                  setState(() => _settings = s.copyWith(emotionMemory: v));
                },
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 測試播放
          FilledButton.icon(
            onPressed: _isTesting ? null : _testPlay,
            icon: _isTesting
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow),
            label: const Text('測試播放'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ─── 輔助元件 ───

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    final ds = BridgeDSColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: ds.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Icon(icon, size: 18, color: ds.accentMiro),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TierStyle.of(context, Tier.cardTitle).toTextStyle().copyWith(color: ds.textPrimary,
                    fontWeight: FontWeight.w600,),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildVoiceDropdown({
    required String label,
    required String value,
    String? excludeId,
    required ValueChanged<String> onChanged,
  }) {
    final available = kAvailableVoices
        .where((id) => id != excludeId)
        .map((id) => kVoiceLabels[id] ?? id)
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              items: kAvailableVoices
                  .where((id) => id != excludeId)
                  .map((id) => DropdownMenuItem<String>(
                        value: id,
                        child: Text(kVoiceLabels[id] ?? id),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(width: 80, child: Text(label)),
              Expanded(child: Text(displayValue)),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  String _sensitivityLabel(double v) {
    if (v < 0.3) return '低 (${v.toStringAsFixed(1)})';
    if (v < 0.7) return '中 (${v.toStringAsFixed(1)})';
    return '高 (${v.toStringAsFixed(1)})';
  }
}
