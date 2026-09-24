// data_path_interceptor.dart
// [資料主權 P0-b 2026-09-14] Dio interceptor——把 DataPathGate 掛到 HTTP 咽喉
// 提案：docs/specs/2026-09-14-data-sovereignty-design.md §4.1
//
// 設計：
// - onRequest：發請求前過 DataPathGate.checkAndLog——red 直接攔截
//   （DioException(requestOptions) 往上拋，請求根本不發出）
// - 判定 fail-open：gate 內部錯誤（如 DB 開不了）時放行但記 lastError
//   （gate 本體已是 fail-open 設計；這裡再包一層防禦，任何未預期例外
//   不得弄斷使用者的對話——閘門壞了≠App 不能用，但錯誤必留痕跡）
// - ledger 記帳是 fire-and-forget（unawaited）：記帳慢不得拖慢請求
// - payload 大小：content-length 有就用，沒有就 0（透明度足夠）
//
// 掛法：dio.interceptors.add(SovereigntyInterceptor(
//   dataClass: DataPathClass.text, purpose: DataPathPurpose.mainChat));

import 'package:dio/dio.dart';

import 'data_path_gate.dart';

/// 資料主權閘門 interceptor。
///
/// [dataClass] / [purpose] 由掛載處聲明（主對話=text/mainChat、
/// 視覺=image/vision…）——同一個 Dio 若服務多種流量，掛多個 Dio 各自聲明。
class SovereigntyInterceptor extends Interceptor {
  final DataPathClass dataClass;
  final DataPathPurpose purpose;

  SovereigntyInterceptor({
    this.dataClass = DataPathClass.text,
    this.purpose = DataPathPurpose.mainChat,
  });

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _check(options, handler);
  }

  Future<void> _check(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final url = options.uri.toString();
    try {
      final payloadBytes = options.headers['content-length'] is int
          ? options.headers['content-length'] as int
          : 0;
      await DataPathGate.instance.checkAndLog(
        url: url,
        dataClass: dataClass,
        purpose: purpose,
        payloadBytes: payloadBytes,
      );
      handler.next(options);
    } on DataPathViolationException catch (e) {
      // 紅燈：攔截。請求不發出，呼叫端收到明確的 DioException。
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: e,
          message: e.toString(),
        ),
        true,
      );
    } catch (e) {
      // gate 本身出錯（不應發生，但防禦性放行）——錯誤留痕，不弄斷對話。
      DataPathGate.instance.lastError = 'interceptor: $e';
      handler.next(options);
    }
  }
}
