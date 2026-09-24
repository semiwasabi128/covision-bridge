#!/usr/bin/env bash
# 啟動 Kokoro TTS Server
# 用途：建立/啟動 Python venv，安裝依賴，啟動 kokoro_server.py
#
# 使用：
#   scripts/start_kokoro.sh          # 前景執行（Ctrl+C 停止）
#   scripts/start_kokoro.sh &        # 背景執行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_DIR="$PROJECT_ROOT/python"
VENV_DIR="$PYTHON_DIR/.venv"

echo "🔧 Kokoro TTS Server 啟動程序"
echo "專案路徑：$PROJECT_ROOT"

# 1. 建立 venv（如果不存在）— 用 Python 3.11（misaki[zh] 需要 >=3.10）
if [ ! -d "$VENV_DIR" ]; then
    echo "📦 建立 Python venv (Python 3.11)..."
    /opt/homebrew/opt/python@3.11/bin/python3.11 -m venv "$VENV_DIR"
fi

# 2. 啟動 venv
echo "⚙️  啟動 venv..."
source "$VENV_DIR/bin/activate"

# 3. 安裝/更新依賴
echo "📥 安裝依賴 (requirements.txt)..."
pip install --upgrade pip >/dev/null 2>&1
pip install -r "$PYTHON_DIR/requirements.txt"

# 4. 檢查 Kokoro 模型是否已下載
KOKORO_MODEL_PATH="$HOME/.local/share/kokoro/models"
if [ ! -d "$KOKORO_MODEL_PATH" ]; then
    echo "⚠️  警告：Kokoro 模型路徑 $KOKORO_MODEL_PATH 不存在"
    echo "   首次啟動時 kokoro 套件會自動下載模型（約 100MB）"
fi

# 5. 啟動 server
echo "🚀 啟動 Kokoro TTS Server (port 18900)..."
cd "$PYTHON_DIR"
python3 kokoro_server.py --host 127.0.0.1 --port 18900
