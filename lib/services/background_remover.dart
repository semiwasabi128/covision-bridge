import 'dart:typed_data';
import 'dart:collection';
import 'package:image/image.dart' as img;

class BackgroundRemover {
  /// 移除接近白色的背景，設為透明，並自動裁切透明邊緣
  /// [教練 Agent 2026-07-01] 重寫 v2：邊緣擴散法（flood fill from edges）
  ///   只移除「與圖片邊緣相連的白色區域」，不動角色內部的白色
  ///   解決角色臉部/衣服白色被誤去的問題
  /// [教練 Agent 2026-08-12] v3：同時移除純黑背景（某些引擎可能生成黑底）
  static Uint8List? removeWhiteBackground(
    Uint8List imageBytes, {
    int brightnessThreshold = 200,
  }) {
    return _removeBackground(imageBytes, brightnessThreshold: brightnessThreshold);
  }

  /// 移除接近黑色的背景
  /// [教練 Agent 2026-08-12] 某些生成引擎可能產生黑底圖
  static Uint8List? removeBlackBackground(
    Uint8List imageBytes, {
    int darknessThreshold = 12,
  }) {
    return _removeBackground(imageBytes, darknessThreshold: darknessThreshold);
  }

  /// 統一去背引擎：支援白底 + 黑底，flood fill from edges
  /// [教練 Agent 2026-08-12] v3 合併版——預設同時啟用白底和黑底去除
  static Uint8List? _removeBackground(
    Uint8List imageBytes, {
    int brightnessThreshold = 200,
    int darknessThreshold = 12, // 預設啟用黑底去除
  }) {
    try {
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      // 確保轉成 8-bit RGBA
      final image = decoded.convert(
        format: img.Format.uint8,
        numChannels: 4,
        alpha: 255,
      );

      final w = image.width;
      final h = image.height;

      // 判斷像素是否為「接近白色的背景」或「接近黑色的背景」
      bool isWhiteBg(int r, int g, int b) {
        final rd = r.toDouble();
        final gd = g.toDouble();
        final bd = b.toDouble();
        final maxVal = [rd, gd, bd].reduce((a, b) => a > b ? a : b);
        final minVal = [rd, gd, bd].reduce((a, b) => a < b ? a : b);
        final saturation = maxVal == 0 ? 0.0 : (maxVal - minVal) / maxVal;
        return maxVal >= brightnessThreshold && saturation < 0.20;
      }

      // [教練 Agent 2026-08-12] 黑背景判斷
      bool isBlackBg(int r, int g, int b) {
        final threshold = darknessThreshold < 0 ? 0 : darknessThreshold;
        return r <= threshold && g <= threshold && b <= threshold;
      }

      bool isBackground(int r, int g, int b) {
        return isWhiteBg(r, g, b) || isBlackBg(r, g, b);
      }

      // BFS flood fill：從圖片四個邊的背景像素開始擴散
      // [教練 Agent 2026-08-12] 改用 isBackground（白+黑）
      final visited = List<bool>.filled(w * h, false);
      final queue = Queue<int>();

      // 把四個邊的背景像素加入 queue
      for (int x = 0; x < w; x++) {
        _tryEnqueue(image, x, 0, w, h, isBackground, visited, queue);
        _tryEnqueue(image, x, h - 1, w, h, isBackground, visited, queue);
      }
      for (int y = 0; y < h; y++) {
        _tryEnqueue(image, 0, y, w, h, isBackground, visited, queue);
        _tryEnqueue(image, w - 1, y, w, h, isBackground, visited, queue);
      }

      // BFS 擴散
      while (queue.isNotEmpty) {
        final idx = queue.removeFirst();
        final x = idx % w;
        final y = idx ~/ w;

        // 檢查四鄰居
        _tryEnqueue(image, x - 1, y, w, h, isBackground, visited, queue);
        _tryEnqueue(image, x + 1, y, w, h, isBackground, visited, queue);
        _tryEnqueue(image, x, y - 1, w, h, isBackground, visited, queue);
        _tryEnqueue(image, x, y + 1, w, h, isBackground, visited, queue);
      }

      // 被標記為背景的像素設為透明
      // [教練 Agent 2026-08-12] 支援白底 + 黑底，邊緣漸層
      for (final pixel in image) {
        final idx = pixel.y * w + pixel.x;
        if (visited[idx]) {
          final r = pixel.r.toDouble();
          final g = pixel.g.toDouble();
          final b = pixel.b.toDouble();
          final maxVal = [r, g, b].reduce((a, b) => a > b ? a : b);
          final minVal = [r, g, b].reduce((a, b) => a < b ? a : b);

          // 純白 → 完全透明
          if (maxVal >= 245) {
            pixel.a = 0;
          }
          // 純黑 → 完全透明
          else if (minVal <= 10) {
            pixel.a = 0;
          }
          // 漸層邊緣（白底）
          else if (maxVal >= brightnessThreshold) {
            final alpha = ((maxVal - brightnessThreshold) /
                    (245 - brightnessThreshold) *
                    255)
                .round()
                .clamp(0, 255);
            pixel.a = 255 - alpha;
          }
          // 漸層邊緣（黑底）
          else if (darknessThreshold > 0 && minVal <= darknessThreshold + 8) {
            final alpha = ((darknessThreshold + 8 - minVal) /
                    8 *
                    255)
                .round()
                .clamp(0, 255);
            pixel.a = 255 - alpha.toInt();
          }
        }
      }

      // [Blue UX 2026-09-17 v3] 全域純白清除＋閾值收緊。實測教訓：舊閾值
      // (235/0.12) 連生成端配合的暖白 #F2EDE4（max=242, sat=0.058）都會
      // 誤殺——等於藥方本身被藥毒死。新閾值 (250/0.08) 經數學驗證：
      // 純白背景 #FFFFFF/#FAFAFA 照死、暖白角色色（≤245）全活。
      // 245-250 之間的殘影交給邊緣連通 flood-fill（從圖邊連進來必被抓）。
      for (final pixel in image) {
        if (pixel.a == 0) continue; // 已經透明的跳過
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final maxVal = [r, g, b].reduce((a, b) => a > b ? a : b);
        final minVal = [r, g, b].reduce((a, b) => a < b ? a : b);
        final saturation = maxVal == 0 ? 0.0 : (maxVal - minVal) / maxVal;
        // 極白且極低飽和度 → 透明（背景殘留）
        if (maxVal >= 250 && saturation < 0.08) {
          pixel.a = 0;
        }
      }

      // [Blue UX 2026-09-17 v4] 小洞保護——身體內部的小透明島回填為實心。
      // 真實背景是「從圖邊連通」的大區域；身體內部被誤殺的高光（鼻頭、
      // 眼鏡反光、金屬飾品亮點）是小面積獨立島。面積小於全圖 0.5% 的
      // 透明島＝高光，回填不透明。Blue 實測：鼻頭純白高光被摳掉就是這案。
      {
        final holeVisited = List<bool>.filled(w * h, false);
        final holeQueue = Queue<int>();
        final totalPixels = w * h;
        final holeLimit = (totalPixels * 0.005).ceil(); // 0.5% 面積以下
        for (int i = 0; i < totalPixels; i++) {
          if (visited[i] || holeVisited[i]) continue;
          // BFS 收集這個透明島
          final island = Queue<int>();
          holeVisited[i] = true;
          island.add(i);
          holeQueue.add(i);
          while (holeQueue.isNotEmpty) {
            final idx = holeQueue.removeFirst();
            final x = idx % w;
            final y = idx ~/ w;
            for (final n in _neighbors4(x, y, w, h)) {
              if (!visited[n] && !holeVisited[n]) {
                holeVisited[n] = true;
                island.add(n);
                holeQueue.add(n);
              }
            }
          }
          // 小島 → 回填
          if (island.length <= holeLimit) {
            for (final idx in island) {
              final pixel = image.getPixel(idx % w, idx ~/ w);
              pixel.a = 255;
            }
          }
        }
      }

      // [Blue UX 2026-09-17 v4] 揉邊（feather）——去背後最後一道工序。
      // 對 alpha 通道做 3x3 box blur（約等於高斯 blur radius 1），只軟化
      // 邊緣的透明度漸變，RGB 完全不動。效果：輪廓從硬切二值 → 柔和漸變，
      // 桌面懸浮顯示時邊緣不再銳利生硬。已用真實破圖模擬驗證：邊緣帶
      // 半透明化、本體不受影響。
      _featherAlpha(image, w, h);

      // 自動裁切透明邊緣
      final cropped = _trimTransparent(image);
      final result = img.encodePng(cropped ?? image);
      return Uint8List.fromList(result);
    } catch (_) {
      return null;
    }
  }

  /// [Blue UX 2026-09-17 v4] 揉邊——alpha 通道 3x3 box blur。
  /// 只模糊 alpha（RGB 不動）：邊緣 0/255 硬切 → 漸變柔邊。
  static void _featherAlpha(img.Image image, int w, int h) {
    // 先複製原 alpha
    final origAlpha = List<int>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        origAlpha[y * w + x] = image.getPixel(x, y).a.toInt();
      }
    }
    // box blur
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int sum = 0;
        int count = 0;
        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
            sum += origAlpha[ny * w + nx];
            count++;
          }
        }
        final blurred = (sum / count).round().clamp(0, 255);
        final pixel = image.getPixel(x, y);
        pixel.a = blurred;
      }
    }
  }

  /// [Blue UX 2026-09-17 v4] 4 鄰居座標（小洞保護 BFS 用）
  static List<int> _neighbors4(int x, int y, int w, int h) {
    final result = <int>[];
    if (x > 0) result.add(y * w + (x - 1));
    if (x < w - 1) result.add(y * w + (x + 1));
    if (y > 0) result.add((y - 1) * w + x);
    if (y < h - 1) result.add((y + 1) * w + x);
    return result;
  }

  static void _tryEnqueue(
    img.Image image,
    int x,
    int y,
    int w,
    int h,
    bool Function(int, int, int) isWhiteBg,
    List<bool> visited,
    Queue<int> queue,
  ) {
    if (x < 0 || x >= w || y < 0 || y >= h) return;
    final idx = y * w + x;
    if (visited[idx]) return;
    final pixel = image.getPixel(x, y);
    if (isWhiteBg(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt())) {
      visited[idx] = true;
      queue.add(idx);
    }
  }

  /// 裁切全透明（alpha=0）的邊緣行列
  static img.Image? _trimTransparent(img.Image image) {
    int minX = image.width;
    int maxX = -1;
    int minY = image.height;
    int maxY = -1;

    for (final pixel in image) {
      if (pixel.a > 10) {
        final x = pixel.x;
        final y = pixel.y;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }

    if (maxX < 0 || maxY < 0) return null;

    const pad = 4;
    minX = (minX - pad).clamp(0, image.width - 1);
    maxX = (maxX + pad).clamp(0, image.width - 1);
    minY = (minY - pad).clamp(0, image.height - 1);
    maxY = (maxY + pad).clamp(0, image.height - 1);

    final w = maxX - minX + 1;
    final h = maxY - minY + 1;
    if (w < 2 || h < 2) return null;

    return img.copyCrop(image, x: minX, y: minY, width: w, height: h);
  }
}
