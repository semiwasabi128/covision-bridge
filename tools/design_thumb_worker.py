#!/usr/bin/env python3
"""專業製圖檔縮圖嵌入 worker（App 沙盒外執行）
流程：DB 撈 metadata 設計檔 → 抽縮圖(skp=PNG/dwg=BMP) → llama-server Vision 描述
     → EmbeddingGemma 嵌入 → UPDATE DB
用法: design_thumb_worker.py（冪等，可反覆跑）
"""
import sqlite3, subprocess, base64, json, os, struct, sys, time, urllib.request

DB = os.path.expanduser('~/Library/Containers/farm.semiwasabi.bridgeApp/Data/Library/Application Support/farm.semiwasabi.bridgeApp/brain_container.db')
LLAMA = 'http://127.0.0.1:18789/v1/chat/completions'
EXTS = ('.skp', '.skb', '.dwg')

def extract_skp_png(path):
    data = open(path, 'rb').read(3_000_000)
    i = data.find(b'\x89PNG\r\n\x1a\n')
    if i < 0: return None
    j = data.find(b'IEND', i)
    if j < 0: return None
    return data[i:j+8]

def extract_dwg_bmp(path):
    data = open(path, 'rb').read(2_000_000)
    i = data.find(b'\x28\x00\x00\x00')
    while i > 0:
        w, h = struct.unpack('<ii', data[i+4:i+12])
        planes, bpp = struct.unpack('<HH', data[i+12:i+16])
        if 32 <= w <= 4096 and 32 <= abs(h) <= 4096 and planes == 1 and bpp in (8,24,32):
            pal = 1024 if bpp == 8 else 0
            size = w*abs(h)*(bpp//8)
            off = 14+40+pal
            bmp = b'BM' + struct.pack('<IHHI', off+size, 0,0,off) + data[i:i+40+pal+size]
            # sips 轉 PNG
            import tempfile
            t = tempfile.NamedTemporaryFile(suffix='.bmp', delete=False)
            t.write(bmp); t.close()
            out = t.name + '.png'
            r = subprocess.run(['sips','-s','format','png',t.name,'--out',out], capture_output=True)
            if r.returncode == 0 and os.path.exists(out):
                png = open(out,'rb').read()
                os.unlink(t.name); os.unlink(out)
                return png
            return None
        i = data.find(b'\x28\x00\x00\x00', i+1)
    return None

def ensure_small_png(png_bytes):
    """llama mmproj 對大圖會 400（~100KB 上限）——超過就 sips 縮到 128 邊"""
    if len(png_bytes) < 60_000:
        return png_bytes
    import tempfile
    t = tempfile.NamedTemporaryFile(suffix='.png', delete=False)
    t.write(png_bytes); t.close()
    out = t.name + '.small.png'
    r = subprocess.run(['sips','-z','128','128',t.name,'--out',out], capture_output=True)
    if r.returncode == 0 and os.path.exists(out):
        small = open(out,'rb').read()
        os.unlink(t.name); os.unlink(out)
        return small
    return png_bytes

def vision_desc(png_bytes, title):
    png_bytes = ensure_small_png(png_bytes)
    b64 = base64.b64encode(png_bytes).decode()
    body = {
      'messages': [{'role':'user','content':[
        {'type':'text','text': f'這是「{title}」的設計圖縮圖。描述圖面內容：圖面類型、主要元素、材質或配色。繁體中文，120字內。'},
        {'type':'image_url','image_url':{'url':'data:image/png;base64,'+b64}},
      ]}],
      'max_tokens': 1024, 'temperature': 0.4,
    }
    req = urllib.request.Request(LLAMA, data=json.dumps(body).encode(),
                                 headers={'Content-Type':'application/json'})
    d = json.load(urllib.request.urlopen(req, timeout=180))
    m = d['choices'][0]['message']
    c = (m.get('content') or '').strip() or (m.get('reasoning_content') or '').strip()
    return c

def embed(text):
    # EmbeddingGemma 在 App 內（TFLite）——worker 不重訓。
    # 改用 llama-server /v1/embeddings？gemma 主模型非 embedding 模型。
    # 方案：描述寫入 DB（content_text + embed_source='vision_desc'），
    # App 內容重嵌服務會接手嵌入（content_text 有料 → embedOne）。
    return None

def main():
    db = sqlite3.connect(DB)
    rows = db.execute("""SELECT id, folder_root, file_path, file_name, display_title FROM asset_index
        WHERE COALESCE(embed_source,'') IN ('metadata','no_thumbnail')
        AND LOWER(COALESCE(file_ext,'')) IN ('.skp','.dwg','.skb')""").fetchall()
    print(f'待處理: {len(rows)}')
    ok = 0
    for rid, fr, fp, fn, dt in rows:
        full = os.path.join(fr, fp)
        try:
            if not os.path.exists(full):
                db.execute("UPDATE asset_index SET embed_source='no_thumbnail' WHERE id=?", (rid,))
                db.commit(); continue
            ext = os.path.splitext(fn)[1].lower()
            png = extract_skp_png(full) if ext in ('.skp','.skb') else extract_dwg_bmp(full)
            if not png:
                db.execute("UPDATE asset_index SET embed_source='no_thumbnail' WHERE id=?", (rid,))
                db.commit(); continue
            title = dt or fn
            desc = vision_desc(png, title)
            if not desc:
                print(f'  ⚠ vision 空: {fn}'); continue
            # 寫描述（embed_source='metadata' 觸發 App 內容重嵌服務接手嵌入）
            db.execute("""UPDATE asset_index SET content_text=?, summary=?, embed_source='metadata'
                          WHERE id=?""",
                       (f'{title}。設計圖：{desc}', desc[:200], rid))
            db.commit()
            ok += 1
            print(f'  ✓ {fn}: {desc[:40]}...')
        except Exception as e:
            print(f'  ✗ {fn}: {str(e)[:100]}')
        time.sleep(0.3)
    print(f'完成: {ok}/{len(rows)}')

if __name__ == '__main__':
    main()
