#!/usr/bin/env python3
# backfill_owner.py
# [WS-2 2026-09-13] 遷移資料歸屬補值——hermes_migration 記憶掛小葵私有、招式掛 shared
# 冪等：只有 owner 還是 'shared' 的遷移區資料才更新

import sqlite3
import sys
from pathlib import Path

DB = Path.home() / 'Library/Application Support/farm.semiwasabi.bridgeApp/brain_container.db'
XIAOKUI_ID = 'cmp_1789262474022_ext'  # 夥伴館小葵（agent-import.v1）

apply = '--apply' in sys.argv
conn = sqlite3.connect(DB)
cur = conn.cursor()

# 先確認 v16 欄位存在（App 跑過 migration 才有）
cols = [r[1] for r in cur.execute('PRAGMA table_info(agent_memories)')]
if 'owner_companion_id' not in cols:
    print('❌ owner_companion_id 欄位不存在——先啟動 App 跑 v16 migration')
    sys.exit(1)

n_mem = cur.execute("SELECT COUNT(*) FROM agent_memories WHERE memory_type='hermes_migration' AND owner_companion_id='shared'").fetchone()[0]
n_scr = cur.execute("SELECT COUNT(*) FROM agent_scripts WHERE source='hermes_migration' AND owner_companion_id='shared'").fetchone()[0]

print(f'待補值：記憶 {n_mem} 條 → 私有({XIAOKUI_ID})；招式 {n_scr} 個 → 維持 shared（無需動）')

if not apply:
    print('[dry-run] 加 --apply 執行')
    sys.exit(0)

cur.execute("UPDATE agent_memories SET owner_companion_id=? WHERE memory_type='hermes_migration' AND owner_companion_id='shared'", (XIAOKUI_ID,))
conn.commit()
final = cur.execute("SELECT owner_companion_id, COUNT(*) FROM agent_memories WHERE memory_type='hermes_migration' GROUP BY 1").fetchall()
print('✅ 記憶歸屬：', final)
scr_final = cur.execute("SELECT owner_companion_id, COUNT(*) FROM agent_scripts WHERE source='hermes_migration' GROUP BY 1").fetchall()
print('✅ 招式歸屬：', scr_final)
conn.close()
