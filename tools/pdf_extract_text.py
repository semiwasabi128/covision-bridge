#!/usr/bin/env python3
"""PDF 文字抽取 helper（bridge_app 嵌入管線用）
用法: pdf_extract_text.py <pdf路徑> [最大頁數]
輸出: JSON {"pages": N, "text": "...", "scanned": bool}
scanned=true 表示文字層極薄（掃描 PDF，需 Vision 路線）
"""
import sys, json
import fitz

def main():
    pdf_path = sys.argv[1]
    max_pages = int(sys.argv[2]) if len(sys.argv) > 2 else 50
    try:
        doc = fitz.open(pdf_path)
        n = min(len(doc), max_pages)
        texts = []
        for i in range(n):
            page = doc[i]
            texts.append(page.get_text())
        doc.close()
        full = "\n".join(texts).strip()
        # 掃描 PDF 判定：總文字 < 每頁 20 字
        scanned = len(full) < n * 20
        print(json.dumps({"pages": n, "text": full[:20000], "scanned": scanned}, ensure_ascii=False))
    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    main()
