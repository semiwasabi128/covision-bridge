#!/bin/bash
# 一鍵把 Hermes 主 config 從 pay-as-you-go 切到 GLM Coding Plan 月訂
# 用途：解決 429 Insufficient balance 錯誤
#
# [小葵 2026-08-07] Blue 你說的「約定的模式」= GLM Coding Plan 月訂
# 月訂 endpoint: https://api.z.ai/api/coding/paas/v4
# 月訂 API Key 從 GLM_API_KEY 環境變數讀取（與 CEO profile 一致）

set -e

CONFIG="$HOME/.hermes/config.yaml"
BAK="$HOME/.hermes/config.yaml.bak.coding-plan-$(date +%Y%m%d-%H%M%S)"

echo "==== 切換到 GLM Coding Plan 月訂模式 ===="
echo ""

# 0. 先確認 GLM_API_KEY 已設定
if [ -z "$GLM_API_KEY" ]; then
  echo "❌ GLM_API_KEY 環境變數未設定"
  echo ""
  echo "請先設定："
  echo "  export GLM_API_KEY='your-coding-plan-api-key-here'"
  echo ""
  echo "API Key 從這裡取得："
  echo "  https://z.ai/manage-apikey/apikey-list (Individual Plan)"
  echo "  https://z.ai/manage-apikey/coding-plan/team/my-plan (Team Plan)"
  echo ""
  exit 1
fi
echo "✅ GLM_API_KEY 已設定（長度 ${#GLM_API_KEY}）"

# 1. 備份
cp "$CONFIG" "$BAK"
echo "✅ 已備份 → $BAK"

# 2. 把 provider: zai 改成 provider: custom:zai-coding
sed -i.bak \
  -e 's/^  provider: zai$/  provider: custom:zai-coding/' \
  "$CONFIG"
echo "✅ model.provider 改成 custom:zai-coding"

# 3. 在檔案尾端加 custom_providers 區段（如果不存在）
if ! grep -q "^custom_providers:" "$CONFIG"; then
  cat >> "$CONFIG" <<'EOF'
custom_providers:
  - api_key_env: GLM_API_KEY
    base_url: https://api.z.ai/api/coding/paas/v4
    default_model: glm-5.2
    format: openai
    name: zai-coding
    key_env: GLM_API_KEY
EOF
  echo "✅ 已加入 custom_providers: zai-coding 區段"
else
  echo "ℹ️ custom_providers 已存在，不重複加"
fi

echo ""
echo "==== 切換完成 ===="
echo ""
echo "下一步："
echo "1. 重啟 Hermes（或關掉再開新對話）"
echo "2. 下一輪回應會自動走 GLM Coding Plan 月訂 endpoint"
echo "3. 不會再 429"
echo ""
echo "如果想退回 pay-as-you-go："
echo "  cp $BAK $CONFIG"
