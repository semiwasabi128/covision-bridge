#!/usr/bin/env python3
"""
tool/fix_const_widget_bridge.py

[小葵 2026-08-04] 把任何 const widget 內含 BridgeDSColors.of(context) 的拿掉 const

策略：掃每個檔案，找 "const WidgetName(" 開頭的呼叫，找到對應的 ")"
中間包含 BridgeDSColors.of(context) → 拿掉這個 const
"""

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

FILES = [
    "lib/screens/companion_list_screen.dart",
    "lib/screens/companion_create_screen.dart",
    "lib/screens/companion_appearance_screen.dart",
]

WIDGET_NAMES = [
    "Icon", "Text", "BoxDecoration", "Border.all", "Border",
    "Expanded", "Row", "Column", "Container", "SizedBox",
    "Padding", "EdgeInsets", "Stack", "Positioned", "Wrap",
    "Flexible", "Align", "Center", "RichText", "TextStyle",
    "IconTheme", "DefaultTextStyle", "Theme",
]

WIDGET_PATTERN = "|".join(re.escape(w) for w in WIDGET_NAMES)


def find_matching_paren(content: str, start: int) -> int:
    """從 start（含左括號）找到對應的右括號位置。"""
    depth = 0
    i = start
    while i < len(content):
        c = content[i]
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return i
        elif c == '"' or c == "'":
            # 跳過字串
            quote = c
            i += 1
            while i < len(content):
                if content[i] == "\\":
                    i += 2
                    continue
                if content[i] == quote:
                    break
                i += 1
        i += 1
    return -1


def fix_file(path: Path) -> tuple[int, int]:
    content = path.read_text()
    original = content
    changes = 0

    # 找所有 "const WidgetName(" 的位置
    pattern = re.compile(rf"(?<![A-Za-z0-9_])const\s+(?:{WIDGET_PATTERN})\(")

    # 重複處理直到沒有變化
    while True:
        new_changes = 0
        out = []
        i = 0
        while i < len(content):
            m = pattern.search(content, i)
            if not m:
                out.append(content[i:])
                break
            # 找對應的 )
            paren_start = m.end() - 1  # "(" 的位置
            paren_end = find_matching_paren(content, paren_start)
            if paren_end < 0:
                out.append(content[i:m.end()])
                i = m.end()
                continue
            # 檢查內容中是否有 BridgeDSColors.of(context)
            inner = content[m.end():paren_end]
            if "BridgeDSColors.of(context)" in inner:
                # 拿掉 const
                # m.start() 到第一個空白 + 5個字元("const")
                const_end = m.start() + len("const")
                out.append(content[i:m.start()])
                out.append(content[const_end:m.end()])
                new_changes += 1
                # 跳到 ) 之後
                out.append(content[paren_end+1:])
                i = len(out[-1]) + len("".join(out[:-1]))
                break  # 重置掃描
            else:
                out.append(content[i:m.end()])
                i = m.end()
        content = "".join(out)
        if new_changes > 0:
            changes += new_changes
            # 重新掃描
            # 但要避免無限循環：限定最多 1000 次
            if changes > 1000:
                break
        else:
            break

    # 寫回
    if content != original:
        path.write_text(content)

    return changes, len(re.findall(r"const (?:Icon|Text|Expanded|Row|Column|Container)\(", original))


def main():
    for rel in FILES:
        path = PROJECT_ROOT / rel
        if not path.exists():
            continue
        print(f"=== 處理 {rel} ===")
        changes, before = fix_file(path)
        print(f"  修掉 const widget 數: {changes}")
        print(f"")


if __name__ == "__main__":
    main()