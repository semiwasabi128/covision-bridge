import 'package:dio/dio.dart';

import '../../models/bridge_action.dart';
import 'bridge_action_adapter.dart';
import 'gemini_image_adapter.dart';
import 'local_desktop_files_adapter.dart';
import 'local_document_adapter.dart';
import 'minimax_image_adapter.dart';
import 'minimax_music_adapter.dart';
import 'minimax_tts_adapter.dart';
import 'minimax_video_adapter.dart';
import 'openai_browse_adapter.dart';
import 'openai_image_adapter.dart';
import 'openai_vision_adapter.dart';
import 'replicate_image_adapter.dart';

class BridgeAdapterRegistry {
  BridgeAdapterRegistry({List<BridgeActionAdapter>? adapters})
    : _adapters =
          adapters ??
          [
            OpenAiBrowseAdapter(),
            OpenAiImageAdapter(),
            OpenAiVisionAdapter(),
            ReplicateImageAdapter(),
            MinimaxImageAdapter(),
            GeminiImageAdapter(),
            MinimaxVideoAdapter(),
            MinimaxMusicAdapter(),
            MinimaxTtsAdapter(),
            LocalDocumentAdapter(),
            LocalDesktopFilesAdapter(),
          ];

  factory BridgeAdapterRegistry.withSharedDio(Dio dio) {
    return BridgeAdapterRegistry(
      adapters: [
        OpenAiBrowseAdapter(dio: dio),
        OpenAiImageAdapter(dio: dio),
        OpenAiVisionAdapter(dio: dio),
        ReplicateImageAdapter(dio: dio),
        MinimaxImageAdapter(dio: dio),
        GeminiImageAdapter(dio: dio),
        MinimaxVideoAdapter(dio: dio),
        MinimaxMusicAdapter(dio: dio),
        MinimaxTtsAdapter(dio: dio),
        LocalDocumentAdapter(),
        LocalDesktopFilesAdapter(),
      ],
    );
  }

  final List<BridgeActionAdapter> _adapters;

  BridgeActionAdapter? findAdapter(BridgeAction action, String provider) {
    for (final adapter in _adapters) {
      if (adapter.canHandle(action, provider)) {
        return adapter;
      }
    }
    return null;
  }

  List<BridgeActionAdapter> adaptersFor(BridgeActionType type) {
    return _adapters
        .where((adapter) => adapter.supportedTypes.contains(type))
        .toList();
  }

  BridgeActionAdapter? adapterById(String id) {
    final normalizedId = id.trim().toLowerCase();
    for (final adapter in _adapters) {
      if (adapter.id == normalizedId) return adapter;
    }
    return null;
  }
}
