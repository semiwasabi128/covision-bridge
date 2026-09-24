// barrel.dart
// 大腦容器 model 統一匯出
// 建立日期: 2026-07-02

export 'package:bridge_app/models/brain_container/brain_room.dart';
export 'package:bridge_app/models/brain_container/room_categories.dart';
export 'package:bridge_app/models/brain_container/memory_source.dart';
export 'package:bridge_app/models/brain_container/memory.dart';
export 'package:bridge_app/models/brain_container/connection_type.dart';
export 'package:bridge_app/models/brain_container/connection.dart';
export 'package:bridge_app/models/brain_container/room_growth.dart';
export 'package:bridge_app/models/brain_container/project.dart';
export 'package:bridge_app/models/brain_container/intention.dart';

// ── services 匯出（P0 記憶寫入管線）─────────────────────────────
export 'package:bridge_app/services/brain_container/embedding/embedding_service.dart';
export 'package:bridge_app/services/brain_container/preprocessing/content_preprocessor.dart';
export 'package:bridge_app/services/brain_container/persistence/memory_draft.dart';
export 'package:bridge_app/services/brain_container/persistence/memory_writer.dart';
export 'package:bridge_app/services/brain_container/pipeline/memory_write_pipeline.dart';
export 'package:bridge_app/services/brain_container/pipeline/pipeline_exceptions.dart';

// ── services 匯出（P1 規則分類 + 連結偵測）──────────────────────
export 'package:bridge_app/services/brain_container/classification/room_rules.dart';
export 'package:bridge_app/services/brain_container/classification/room_classifier.dart';
export 'package:bridge_app/services/brain_container/connections/connection_repository.dart';
export 'package:bridge_app/services/brain_container/connections/connection_detector.dart';
