#!/usr/bin/env python3
# import_hermes_skills.py
# [搬遷 2026-09-13] 小葵的技能行囊——Hermes skills → 橋樑 agent_scripts（招式庫）
#
# 來源：~/.hermes/skills/**/SKILL.md（YAML frontmatter + markdown）
# 目標：brain_container.db agent_scripts（source='hermes_migration'）
#
# 設計：
# - SKILL.md 正文截 8KB（檢索摘要用），references/ 只登記檔名索引
#   （原始檔仍在 Hermes 目錄——第一階段引用不改搬）
# - frontmatter: name→title, description→description+trigger_keywords
# - 冪等：skill:<sha8> 指紋（name+內容 hash）
# - dry-run 預設，--apply 才真寫；FTS 同步手動補

import hashlib
import re
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

HERMES_SKILLS = Path.home() / '.hermes/skills'
BRIDGE_DB = Path.home() / 'Library/Application Support/farm.semiwasabi.bridgeApp/brain_container.db'
MAX_CONTENT = 8192


def parse_frontmatter(text):
    m = re.match(r'^---\s*\n(.*?)\n---\s*\n', text, re.DOTALL)
    if not m:
        return {}, text
    fm_text, body = m.group(1), text[m.end():]
    meta = {}
    for line in fm_text.splitlines():
        mm = re.match(r'^(\w[\w-]*):\s*(.*)$', line)
        if mm:
            meta[mm.group(1)] = mm.group(2).strip().strip('"\'')
    return meta, body


def collect_skills():
    skills = []
    for skill_md in sorted(HERMES_SKILLS.rglob('SKILL.md')):
        rel = skill_md.relative_to(HERMES_SKILLS)
        category = rel.parts[0] if len(rel.parts) > 1 else 'general'
        text = skill_md.read_text(encoding='utf-8', errors='replace')
        meta, body = parse_frontmatter(text)
        name = meta.get('name') or rel.parent.name
        desc = meta.get('description') or body.strip()[:100]
        # references 索引
        refs_dir = skill_md.parent / 'references'
        refs = [f.name for f in sorted(refs_dir.iterdir())] if refs_dir.is_dir() else []
        content = body.strip()
        truncated = len(content) > MAX_CONTENT
        if truncated:
            content = content[:MAX_CONTENT] + '\n\n…（截斷——完整版在 Hermes skills 原目錄）'
        if refs:
            content += '\n\n## 參考檔案（references/）\n' + '\n'.join(f'- {r}' for r in refs)
        skills.append({
            'name': name,
            'title': f'[招式] {name}',
            'desc': desc[:500],
            'content': content,
            'category': f'hermes/{category}',
            'truncated': truncated,
            'rel': str(rel),
        })
    return skills


def keywords_from_desc(desc):
    # 從 description 抽觸發詞：引號內容 + 中文關鍵詞粗取
    kws = re.findall(r'[「「"]([^」」"]{2,12})[」」"]', desc)
    return ','.join(dict.fromkeys(kws))[:200]


def main():
    apply_mode = '--apply' in sys.argv
    conn = sqlite3.connect(BRIDGE_DB)
    cur = conn.cursor()

    existing = set()
    for (t,) in cur.execute("SELECT tags FROM agent_scripts WHERE source='hermes_migration'"):
        if t and t.startswith('skill:'):
            existing.add(t.split(',')[0])

    skills = collect_skills()
    plan = []
    for s in skills:
        fp = 'skill:' + hashlib.sha256((s['name'] + s['content'][:1024]).encode()).hexdigest()[:8]
        if fp in existing:
            continue
        s['fp'] = fp
        plan.append(s)

    if not plan:
        print('沒有新 skill 可匯入')
        return

    total_kb = sum(len(s['content']) for s in plan) // 1024
    print(f'=== 待匯入 {len(plan)}/{len(skills)} 個 skills（{total_kb} KB）===')
    for s in plan[:10]:
        print(f"  {s['category']:28s} {s['name'][:44]}{'（截斷）' if s['truncated'] else ''}")
    if len(plan) > 10:
        print(f'  … 及另外 {len(plan) - 10} 個')

    if not apply_mode:
        print('\n[dry-run] 未寫入。加 --apply 執行真正匯入。')
        return

    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    for s in plan:
        sid = f'skill_hermes_{s["fp"][6:]}'
        cur.execute(
            "INSERT INTO agent_scripts (id, title, description, content, content_type, "
            "tags, category, trigger_keywords, created_at, updated_at, source) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (sid, s['title'], s['desc'], s['content'], 'markdown',
             f'{s["fp"]},{s["rel"]}', s['category'], keywords_from_desc(s['desc']),
             now, now, 'hermes_migration'),
        )
        rowid = cur.execute("SELECT rowid FROM agent_scripts WHERE id=?", (sid,)).fetchone()[0]
        cur.execute(
            "INSERT INTO agent_scripts_fts(rowid, title, content, tags) VALUES (?,?,?,?)",
            (rowid, s['title'], s['content'], s['fp']),
        )
    conn.commit()
    n = cur.execute("SELECT COUNT(*) FROM agent_scripts WHERE source='hermes_migration'").fetchone()[0]
    print(f'\n✅ 已匯入 {len(plan)} 個；遷移區總計 {n} 個')
    conn.close()


if __name__ == '__main__':
    main()
