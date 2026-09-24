// llm_retry_utils.dart
// [2026-07-20] 移植 Hermes agent/retry_utils.py — GLM-5.2 實戰調校
//
// 設計原則（對齊 Hermes）：
// - jittered backoff：避免 thundering herd
// - Z.AI Coding Plan GLM-5.2 overload 429 專屬處理
// - 前 3 次短 retry，之後 30→60→90→120s 長 backoff
// - 不可重試的錯誤（400/401/403）直接丟出

import 'dart:math';

/// Z.AI Coding Plan GLM-5.2 overload 的長 backoff 時間表
const _zaiCodingOverloadLongBackoff = [30.0, 60.0, 90.0, 120.0];

/// 前 N 次用短 retry（正常 exponential），之後切到長 backoff
const _zaiCodingOverloadShortAttempts = 3;

/// 計算 jittered exponential backoff 延遲
///
/// 移植自 Hermes jittered_backoff()：
/// delay = min(base * 2^(attempt-1), max) + uniform(0, jitter_ratio * delay)
///
/// [attempt] 是 1-based 的重試次數
double jitteredBackoff(
  int attempt, {
  double baseDelay = 5.0,
  double maxDelay = 120.0,
  double jitterRatio = 0.5,
}) {
  final exponent = attempt - 1;
  if (exponent < 0) return baseDelay;

  double delay;
  if (exponent >= 63 || baseDelay <= 0) {
    delay = maxDelay;
  } else {
    delay = min(baseDelay * pow(2, exponent).toDouble(), maxDelay);
  }

  // Dart 沒有 global jitter counter，用 DateTime + Random seed
  final rng = Random(DateTime.now().microsecondsSinceEpoch ^ (attempt * 0x9E3779B9).toInt());
  final jitter = rng.nextDouble() * (jitterRatio * delay);

  return delay + jitter;
}

/// 判斷是否為 Z.AI Coding Plan GLM-5.2 overload 錯誤
///
/// 移植自 Hermes is_zai_coding_overload_error()：
/// HTTP 429 + body code 1305 + "temporarily overloaded"
/// + base_url 含 api.z.ai/api/coding/paas/v4 + model 含 glm-5.2
bool isZaiCodingOverloadError({
  required String baseUrl,
  required String model,
  required int statusCode,
  required String errorBody,
}) {
  final base = baseUrl.toLowerCase();
  final modelName = model.toLowerCase();
  final text = errorBody.toLowerCase();

  return statusCode == 429 &&
      base.contains('api.z.ai/api/coding/paas/v4') &&
      modelName.contains('glm-5.2') &&
      (text.contains('1305') || text.contains('temporarily overloaded'));
}

/// 計算 Z.AI overload 的 adaptive backoff
///
/// 移植自 Hermes adaptive_rate_limit_backoff()：
/// 前 shortAttempts 次用正常 exponential（短 retry）
/// 之後用長 backoff table：30→60→90→120s + 0.2 jitter
///
/// 回傳 (delaySeconds, reasonLabel)
({double delay, String? reason}) adaptiveRateLimitBackoff({
  required String baseUrl,
  required String model,
  required int statusCode,
  required String errorBody,
  required int attempt,
  double defaultWait = 5.0,
}) {
  if (!isZaiCodingOverloadError(
    baseUrl: baseUrl,
    model: model,
    statusCode: statusCode,
    errorBody: errorBody,
  )) {
    return (delay: defaultWait, reason: null);
  }

  if (attempt <= _zaiCodingOverloadShortAttempts) {
    return (delay: defaultWait, reason: 'zai_coding_overload_short');
  }

  final idx = min(
    attempt - _zaiCodingOverloadShortAttempts - 1,
    _zaiCodingOverloadLongBackoff.length - 1,
  );
  final baseDelay = _zaiCodingOverloadLongBackoff[idx];
  final jittered = jitteredBackoff(
    1,
    baseDelay: baseDelay,
    maxDelay: baseDelay,
    jitterRatio: 0.2,
  );
  return (delay: jittered, reason: 'zai_coding_overload_long');
}

/// Z.AI overload 的 retry 上限
/// 3 short + 4 long + 1 = 8 次
int zaiCodingOverloadRetryCeiling() {
  return _zaiCodingOverloadShortAttempts + _zaiCodingOverloadLongBackoff.length + 1;
}

/// 判斷錯誤是否可重試
///
/// 可重試：5xx、429、connection error、timeout
/// 不可重試：400（bad request）、401（unauthorized）、403（forbidden）
bool isRetryableError(int? statusCode, dynamic error) {
  // TimeoutException — 可重試
  if (error.toString().contains('TimeoutException')) return true;

  // DioException — 看 type
  final errorStr = error.toString();
  if (errorStr.contains('DioException')) {
    // connection error / receive timeout / send timeout → 可重試
    if (errorStr.contains('connectionError') ||
        errorStr.contains('receiveTimeout') ||
        errorStr.contains('sendTimeout') ||
        errorStr.contains('connectionTimeout')) {
      return true;
    }
    // 5xx → 可重試
    if (statusCode != null && statusCode >= 500) return true;
    // 429 → 可重試（rate limit）
    if (statusCode == 429) return true;
    // 400/401/403 → 不可重試
    if (statusCode == 400 || statusCode == 401 || statusCode == 403) return false;
  }

  // 有 status code 的情況
  if (statusCode != null) {
    if (statusCode >= 500) return true;
    if (statusCode == 429) return true;
    return false;
  }

  // 不確定 → 預設可重試（寧可重試一次也不要直接失敗）
  return true;
}
