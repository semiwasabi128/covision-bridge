#!/usr/bin/env python3
# import_hermes_memories.py
# [搬遷前置 2026-09-13] 小葵的行囊打包——Hermes 記憶 → 橋樑 agent_memories
#
# 來源：~/.hermes/memories/{MEMORY,USER}.md + ~/.hermes/SOUL.md（§ 分隔條目）
# 目標：brain_container.db agent_memories（memory_type='hermes_migration'）
#
# 鐵則：
# - 預設 dry-run（只預覽不寫入）；--apply 才真寫
# - 冪等：以 hermes:<sha8> 指紋去重，重跑不重複匯入
# - 每條帶來源檔名+行號 tags，可溯源可回滾（刪 tag 即全清）
# - SOUL.md 不拆條——整檔一條（身份不可分割）

import hashlib
import sqlite3
import sys
from pathlib import Path

HERMES = Path.home() / '.hermes'
BRIDGE_DB = Path.home() / 'Library/Application Support/farm.semiwasabi.bridgeApp/brain_container.db'

SOURCES = [
    HERMES / 'memories/MEMORY.md',
    HERMES / 'memories/USER.md',
    HERMES / 'SOUL.md',
]


def parse_entries(md_path: Path):
    """解析 § 分隔條目，回傳 (text, line_no) 列表；SOUL.md 整檔一條。"""
    if not md_path.exists():
        return []
    text = md_path.read_text(encoding='utf-8')
    if md_path.name == 'SOUL.md':
        return [(text.strip(), 1)]
    entries = []
    line_no = 1
    for chunk in text.split('§'):
        c = chunk.strip('\n').strip()
        if c:
            entries.append((c, line_no))
        line_no += chunk.count('\n') + 1
    return entries


def main():
    apply_mode = '--apply' in sys.argv
    conn = sqlite3.connect(BRIDGE_DB)
    cur = conn.cursor()

    # 已匯入指紋（冪等）
    existing = set()
    for (t,) in cur.execute("SELECT tags FROM agent_memories WHERE memory_type='hermes_migration'"):
        if t and t.startswith('hermes:'):
            existing.add(t.split(',')[0])

    plan = []  # (fingerprint, title, content, tags)
    for src in SOURCES:
        for text, line_no in parse_entries(src):
            fp = 'hermes:' + hashlib.sha256(text.encode('utf-8')).hexdigest()[:8]
            if fp in existing:
                continue
            src_label = src.name.replace('.md', '')
            title = f'[遷移] {src_label}：{text[:30]}…' if len(text) > 30 else f'[遷移] {src_label}：{text}'
            tags = f'{fp},{src_label},L{line_no}'
            plan.append((fp, title, text, tags))

    if not plan:
        print('沒有新條目可匯入（全部已存在或來源為空）')
        return

    print(f'=== 待匯入 {len(plan)} 條 ===')
    for fp, title, _, tags in plan:
        print(f'  {tags:32s} {title[:60]}')

    if not apply_mode:
        print('\n[dry-run] 未寫入。加 --apply 執行真正匯入。')
        return

    for fp, title, content, tags in plan:
        cur.execute(
            "INSERT INTO agent_memories (id, title, content, tags, memory_type, created_at, is_archived) "
            "VALUES (?,?,?,?,?,?,0)",
            (f'mem_hermes_{fp[7:]}', title, content, tags, 'hermes_migration',
             __import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M:%S')),
        )
        # FTS 同步（App 層手動維護 _syncMemoryFts，繞過 App 寫入時必須自己補）
        rowid = cur.execute(
            "SELECT rowid FROM agent_memories WHERE id = ?", (f'mem_hermes_{fp[7:]}',)
        ).fetchone()[0]
        cur.execute(
            "INSERT INTO agent_memories_fts(rowid, title, content, tags) VALUES (?,?,?,?)",
            (rowid, title, content, tags),
        )
    conn.commit()
    n = cur.execute("SELECT COUNT(*) FROM agent_memories WHERE memory_type='hermes_migration'").fetchone()[0]
    print(f'\n✅ 已匯入 {len(plan)} 條；遷移區總計 {n} 條')
    conn.close()


if __name__ == '__main__':
    main()
