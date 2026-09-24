/// AppRetina — 全域視網膜
///
/// [教練 Agent 2026-08-22 使用者] 「無論我停在哪邊你都可以看得很清楚」——
/// 整個 App 的畫面（不只畫布）都包在 app.dart 根部的 RepaintBoundary
/// 裡。任何頁面：首頁、畫布、大腦圖譜、設定、對話——都能拍。
///
/// 與畫布視網膜（/screenshot、/render_layer）的關係：
/// - /render_layer：畫布渲染層的「向量版」（ActualSizeCache 直讀）
/// - /app_view：整個 App 的「像素版」（全域 RepaintBoundary）
/// - 未來：全 App 的結構化感知（widget 樹摘要）可再加

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';

class AppRetina {
  AppRetina._();

  static final GlobalKey rootKey = GlobalKey();

  /// 拍下整個 App 畫面（base64 PNG）
  ///
  /// 回傳 null 表示 App 尚未渲染。
  static Future<String?> capture({double pixelRatio = 1.5}) async {
    final ctx = rootKey.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    final boundary = ro;
    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      image.dispose();
      return base64Of(byteData);
    } catch (_) {
      return null;
    }
  }

  static String base64Of(ByteData data) {
    return base64Encode(data.buffer.asUint8List());
  }
}
