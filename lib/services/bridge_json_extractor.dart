String extractFirstJsonObject(String raw) {
  final start = raw.indexOf('{');
  if (start < 0) return raw.trim();

  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = start; index < raw.length; index += 1) {
    final char = raw.codeUnitAt(index);
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char == 0x5C) {
      escaped = inString;
      continue;
    }
    if (char == 0x22) {
      inString = !inString;
      continue;
    }
    if (inString) continue;
    if (char == 0x7B) depth += 1;
    if (char == 0x7D) {
      depth -= 1;
      if (depth == 0) return raw.substring(start, index + 1);
    }
  }

  return raw.substring(start).trim();
}
