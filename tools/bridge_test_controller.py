#!/usr/bin/env python3
"""
橋樑 App Agent 測試控制器
讓 AI Agent 像真人一樣操控 iOS 模擬器上的 Bridge App。

核心能力：
  1. screenshot()        — 截圖，回傳檔案路徑
  2. tap(x, y)           — 點擊座標
  3. tap_text(text)      — 點擊包含指定文字的元素
  4. swipe(x1,y1,x2,y2) — 滑動
  5. type_text(text)     — 輸入文字
  6. launch()            — 啟動 app
  7. wait(ms)            — 等待
  8. scroll_down/up()    — 向下/上捲動

使用方式（CLI）：
  python3 bridge_test_controller.py screenshot
  python3 bridge_test_controller.py tap 100 200
  python3 bridge_test_controller.py tap_text "預覽草稿"
  python3 bridge_test_controller.py swipe 200 600 200 100
  python3 bridge_test_controller.py type "你好"
  python3 bridge_test_controller.py launch
  python3 bridge_test_controller.py scroll down

使用方式（Python import）：
  from bridge_test_controller import BridgeTestController
  bot = BridgeTestController()
  bot.launch()
  bot.screenshot("/tmp/screen.png")
  bot.tap_text("預覽草稿")

依賴：
  - xcrun simctl（Xcode 內建，截圖 + app 安裝）
  - maestro（YAML flow 驅動，負責 tap/swipe/type）
  - cliclick（座標精準點擊，備用）

環境變數：
  MAESTRO_BIN   — maestro bin 路徑（預設 ~/.maestro/bin）
  JAVA_HOME     — Java 路徑（預設 /opt/homebrew/opt/openjdk@17）
"""

import subprocess
import sys
import os
import json
import time
import tempfile

# ─── 環境設定 ───
HOME = os.path.expanduser("~")
MAESTRO_BIN = os.environ.get("MAESTRO_BIN", f"{HOME}/.maestro/bin")
JAVA_HOME = os.environ.get("JAVA_HOME", "/opt/homebrew/opt/openjdk@17")

def _env():
    """回傳帶有 maestro + java 的 PATH 環境"""
    env = os.environ.copy()
    env["PATH"] = f"{JAVA_HOME}/bin:{MAESTRO_BIN}:{env.get('PATH', '')}"
    env["MAESTRO_CLI_NO_ANALYTICS"] = "1"
    return env

# ─── 模擬器工具 ───

def _run(cmd, timeout=30):
    """執行命令，回傳 (stdout, stderr, returncode)"""
    result = subprocess.run(
        cmd, shell=True, capture_output=True, text=True,
        timeout=timeout, env=_env()
    )
    return result.stdout.strip(), result.stderr.strip(), result.returncode

def get_booted_simulator():
    """取得目前 booted 的模擬器 UDID"""
    out, _, _ = _run("xcrun simctl list devices booted -j")
    data = json.loads(out)
    for runtime, devices in data.get("devices", {}).items():
        for dev in devices:
            if dev.get("state") == "Booted":
                return dev["udid"]
    return None

# ─── Maestro flow 生成 ───

def _maestro_flow(commands, app_id="farm.semiwasabi.bridgeApp"):
    """生成 Maestro YAML flow 內容"""
    lines = [f"appId: {app_id}", "---"]
    for cmd in commands:
        lines.append(f"- {cmd}")
    return "\n".join(lines) + "\n"

def _run_maestro(commands, timeout=60):
    """執行 Maestro flow"""
    flow_content = _maestro_flow(commands)
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".yaml", delete=False, prefix="maestro_flow_"
    ) as f:
        f.write(flow_content)
        flow_path = f.name
    
    try:
        out, err, rc = _run(f"maestro test {flow_path}", timeout=timeout)
        return {
            "success": rc == 0,
            "output": out,
            "error": err,
            "flow": flow_content,
        }
    finally:
        os.unlink(flow_path)

# ─── cliclick 工具（座標精準控制）───

def _cliclick(args, timeout=10):
    """執行 cliclick 命令"""
    out, err, rc = _run(f"cliclick {args}", timeout=timeout)
    return {"success": rc == 0, "output": out, "error": err}

# ─── 主控制器 ───

class BridgeTestController:
    """橋樑 App 測試控制器"""
    
    APP_ID = "farm.semiwasabi.bridgeApp"
    
    def __init__(self):
        self.udid = get_booted_simulator()
        if not self.udid:
            print("⚠️ 沒有 booted 模擬器，嘗試啟動 iPhone 17...")
            _run("xcrun simctl boot 'iPhone 17'", timeout=30)
            time.sleep(3)
            _run("open -a Simulator", timeout=10)
            time.sleep(2)
            self.udid = get_booted_simulator()
        
        if self.udid:
            print(f"📱 模擬器: {self.udid}")
        else:
            raise RuntimeError("無法取得 booted 模擬器")
    
    def launch(self):
        """啟動 Bridge App"""
        out, err, rc = _run(
            f"xcrun simctl launch booted {self.APP_ID}", timeout=15
        )
        time.sleep(2)  # 等待 app 載入
        return {"success": rc == 0, "output": out, "error": err}
    
    def terminate(self):
        """終止 Bridge App"""
        out, err, rc = _run(
            f"xcrun simctl terminate booted {self.APP_ID}", timeout=10
        )
        return {"success": rc == 0, "output": out, "error": err}
    
    def screenshot(self, path=None):
        """截圖，回傳檔案路徑"""
        if path is None:
            path = f"/tmp/bridge_screenshot_{int(time.time())}.png"
        out, err, rc = _run(
            f"xcrun simctl io booted screenshot {path}", timeout=15
        )
        if rc == 0:
            return {"success": True, "path": path}
        return {"success": False, "error": err}
    
    def tap(self, x, y):
        """點擊指定座標（百分比 0-100 或像素）"""
        result = _run_maestro([f"tapOn:\n    point: {x}%,{y}%"])
        return result
    
    def tap_pixel(self, x, y):
        """點擊指定像素座標"""
        result = _run_maestro([f"tapOn:\n    point: {x},{y}"])
        return result
    
    def tap_text(self, text):
        """點擊包含指定文字的元素"""
        result = _run_maestro([f'tapOn: "{text}"'])
        return result
    
    def tap_id(self, element_id):
        """點擊指定 accessibility ID 的元素"""
        result = _run_maestro([f"tapOn:\n    id: {element_id}"])
        return result
    
    def swipe(self, x1, y1, x2, y2, percentage=True):
        """滑動（百分比座標）"""
        unit = "%" if percentage else ""
        cmd = f"swipe:\n    start: {x1}{unit}, {y1}{unit}\n    end: {x2}{unit}, {y2}{unit}"
        return _run_maestro([cmd])
    
    def scroll_down(self, amount=40):
        """向下捲動（手指從下往上滑）"""
        return self.swipe(50, 50 + amount, 50, 50 - amount)
    
    def scroll_up(self, amount=40):
        """向上捲動（手指從上往下滑）"""
        return self.swipe(50, 50 - amount, 50, 50 + amount)
    
    def type_text(self, text):
        """輸入文字到目前焦點的輸入框"""
        return _run_maestro([f'inputText: "{text}"'])
    
    def wait(self, ms=2000):
        """等待指定毫秒"""
        return _run_maestro([f"waitForAnimationToEnd:\n    timeout: {ms}"])
    
    def back(self):
        """按返回鍵（iOS 沒有硬體返回鍵，用座點擊左上角）"""
        return self.tap_pixel(30, 60)
    
    def install(self, app_path):
        """安裝 app"""
        out, err, rc = _run(
            f"xcrun simctl install booted {app_path}", timeout=60
        )
        return {"success": rc == 0, "output": out, "error": err}
    
    def see(self, question="描述這個畫面的內容"):
        """截圖並回傳路徑，供 vision_analyze 使用"""
        result = self.screenshot()
        if result["success"]:
            return result["path"]
        return None
    
    def run_flow(self, commands):
        """執行自訂 Maestro flow 命令列表"""
        return _run_maestro(commands)


# ─── CLI 入口 ───

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    
    bot = BridgeTestController()
    cmd = sys.argv[1]
    
    if cmd == "screenshot":
        path = sys.argv[2] if len(sys.argv) > 2 else None
        result = bot.screenshot(path)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "launch":
        result = bot.launch()
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "terminate":
        result = bot.terminate()
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "tap":
        x, y = sys.argv[2], sys.argv[3]
        result = bot.tap(x, y)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "tap_text":
        text = sys.argv[2]
        result = bot.tap_text(text)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "tap_pixel":
        x, y = sys.argv[2], sys.argv[3]
        result = bot.tap_pixel(x, y)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "swipe":
        x1, y1, x2, y2 = sys.argv[2:6]
        result = bot.swipe(x1, y1, x2, y2)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "scroll":
        direction = sys.argv[2] if len(sys.argv) > 2 else "down"
        if direction == "down":
            result = bot.scroll_down()
        else:
            result = bot.scroll_up()
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "type":
        text = sys.argv[2]
        result = bot.type_text(text)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "wait":
        ms = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
        result = bot.wait(ms)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "install":
        app_path = sys.argv[2]
        result = bot.install(app_path)
        print(json.dumps(result, ensure_ascii=False))
    
    elif cmd == "see":
        path = bot.see()
        if path:
            print(f"SCREENSHOT:{path}")
        else:
            print("ERROR: 截圖失敗")
    
    else:
        print(f"未知命令: {cmd}")
        print(__doc__)

if __name__ == "__main__":
    main()
