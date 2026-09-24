#!/usr/bin/env python3
# import_agent_to_companions.py
# [Agent 整合平台 2026-09-13] 外部 Agent 匯入夥伴館——任何平台都能進
#
# Blue 願景：橋樑 App 成為使用者原本 AI Agent 系統的整合平台，
# Hermes/OpenClaw/Codex/任何 Agent 都能匯入無縫接軌（參考 Buzz 的
# agent-agnostic 精神：agent 是成員，不是插件）。
#
# 格式 agent-import.v1（通用中介）：
# {
#   "schema": "bridge.agent-import.v1",
#   "sourcePlatform": "hermes",          # hermes | openclaw | codex | custom
#   "name": "小葵",
#   "identity": {role, mbtiCode, personalityTags...},
#   "persona": {personality, speakingStyle, expertise, habit, relationship, freeform...},
#   "provenance": "匯入時間/來源備註"
# }
# → 映射到 Companion JSON（插入 plist flutter.bridge_companions_v1）
#
# 鐵則：dry-run 預設；冪等（name+sourcePlatform 去重）；備份優先；
# 不碰 active companion；skill/memory 已在 agent_memories/agent_scripts
# （memory_type/source=hermes_migration），人格在此接上。

import json
import plistlib
import sys
from datetime import datetime
from pathlib import Path

PLIST = Path.home() / ('Library/Containers/farm.semiwasabi.bridgeApp/Data/'
                       'Library/Preferences/farm.semiwasabi.bridgeApp.plist')
KEY = 'flutter.bridge_companions_v1'


def load_companions():
    with open(PLIST, 'rb') as f:
        pl = plistlib.load(f)
    raw = pl.get(KEY, '[]')
    return pl, json.loads(raw) if isinstance(raw, str) else raw


def save_companions(pl, companions):
    pl[KEY] = json.dumps(companions, ensure_ascii=False)
    # 備份
    bak = Path(f'/tmp/bridge_companions_backup_{datetime.now():%Y%m%d_%H%M%S}.json')
    bak.write_text(json.dumps(companions, ensure_ascii=False, indent=1))
    with open(PLIST, 'wb') as f:
        plistlib.dump(pl, f)
    return bak


def build_companion(spec, template):
    """從 spec 生成 Companion JSON——以現有夥伴為模板（結構保真）。"""
    c = json.loads(json.dumps(template))  # deep copy
    ts = int(datetime.now().timestamp() * 1000)
    c.update({
        'id': f'cmp_{ts}_ext',
        'name': spec['name'],
        'mbtiCode': spec.get('identity', {}).get('mbtiCode', 'ENFJ'),
        'role': spec.get('identity', {}).get('role', 'general'),
        'personalityTags': spec.get('identity', {}).get('personalityTags',
                                                        [f"from:{spec.get('sourcePlatform', 'custom')}"]),
        # 外匯 Agent 無頭像——清空形象欄
        'avatarImagePath': None,
        'avatarAnimationPath': None,
        'appearancePrompt': '',
        'appearanceDescription': '',
        'appearanceHistory': [],
        'stateImagePaths': {},
        'stateAnimationPaths': {},
        'stateTriggerKeywords': {},
        'totalConversations': 0,
        'totalTokens': 0,
        'createdAt': datetime.now().isoformat(),
        'updatedAt': datetime.now().isoformat(),
    })
    # 人格欄位（2026-08-14 設定文字欄位）
    persona = spec.get('persona', {})
    for field in ['inspiration', 'specialFunction', 'speakingStyle', 'personality',
                  'expertise', 'habit', 'relationship', 'artStyle', 'species', 'freeform']:
        if field in persona:
            c[field] = persona[field]
    # 溯源標記
    c['freeform'] = (persona.get('freeform', '') +
                     f"\n\n[來源] {spec.get('sourcePlatform', 'custom')} 匯入於 "
                     f"{datetime.now():%Y-%m-%d}（agent-import.v1）").strip()
    return c


def main():
    if len(sys.argv) < 2:
        print('用法：import_agent_to_companions.py <agent-import.json> [--apply]')
        sys.exit(1)
    apply_mode = '--apply' in sys.argv
    spec = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    if spec.get('schema') != 'bridge.agent-import.v1':
        print('❌ schema 必須是 bridge.agent-import.v1')
        sys.exit(1)

    pl, companions = load_companions()
    src = spec.get('sourcePlatform', 'custom')
    name = spec['name']
    dupe = [c for c in companions if c['name'] == name
            and f'from:{src}' in (c.get('personalityTags') or [])]
    if dupe:
        print(f'已存在同名同源夥伴：{name} ({dupe[0]["id"]})——冪等跳過')
        return

    template = companions[0]  # 以第一位當結構模板
    new_c = build_companion(spec, template)

    print(f'=== 待匯入 ===')
    print(f'  名稱：{new_c["name"]}（{new_c["role"]}, {new_c["mbtiCode"]}）')
    print(f'  來源：{src}')
    print(f'  ID：{new_c["id"]}')
    for k in ['speakingStyle', 'personality', 'expertise', 'specialFunction']:
        if new_c.get(k):
            print(f'  {k}: {new_c[k][:60]}…' if len(new_c[k]) > 60 else f'  {k}: {new_c[k]}')

    if not apply_mode:
        print('\n[dry-run] 未寫入。加 --apply 執行。')
        return

    companions.append(new_c)
    bak = save_companions(pl, companions)
    print(f'\n✅ 已匯入。備份：{bak}')
    print(f'夥伴館現有 {len(companions)} 位夥伴（active 未變動）')


if __name__ == '__main__':
    main()
