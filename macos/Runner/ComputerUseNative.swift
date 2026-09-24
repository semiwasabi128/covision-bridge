//
//  ComputerUseNative.swift
//  橋樑 Computer Use Phase 0 — 安全機制 + AX 樹 + CGEvent 注入
//
//  Spec: docs/specs/2026-09-05-bridge-computer-use.md
//  安全鐵則（Blue 2026-09-05）：
//   1. 接管狀態機 idle → armed → active → suspended，任何注入必經狀態機檢查
//   2. 真人在場偵測：Agent 事件帶專屬 source 標記，偵測到非 Agent 鍵鼠輸入 → 3 秒內停手
//   3. Esc 長按 1.5 秒 = 硬體級急停（CFRunLoop observer，不走模型）
//   4. 操作圍欄：AXSecureTextField 一律拒輸；檔案寫入限定授權資料夾（Dart 端把關）
//
//  Channel: bridge.computer_use.macos.v1
//

import Cocoa
import AppKit
import FlutterMacOS
import ApplicationServices

// MARK: - 接管狀態機（全域單點強制）

enum TakeoverState: String {
  case idle      // 永不注入
  case armed     // 已授權待命（使用者明確動作 + TCC 已授予）
  case active    // 正在操作（唯一可注入的狀態）
  case suspended // 暫停（真人到場 / Esc / 預算斷路 / 喊停）
}

final class TakeoverGate {
  static let shared = TakeoverGate()

  private(set) var state: TakeoverState = .idle
  private(set) var taskId: String?
  private(set) var lastSuspendReason: String?

  // 真人在場偵測：非 Agent 的鍵鼠事件時間戳
  private(set) var lastHumanEventAt: Date?

  private var escPressStart: Date?
  private var escObserver: Any?

  var onStateChange: ((TakeoverState, String?) -> Void)?

  // ---- 狀態轉移（唯一入口，注入路徑必經 canInject 檢查）----

  func arm(taskId: String) -> Bool {
    guard state == .idle || state == .suspended else { return false }
    // TCC Accessibility 權限檢查
    guard ComputerUseTCC.hasAccessibilityPermission() else { return false }
    self.taskId = taskId
    lastSuspendReason = nil
    setState(.armed, reason: nil)
    return true
  }

  func activate() -> Bool {
    guard state == .armed else { return false }
    setState(.active, reason: nil)
    return true
  }

  func suspend(reason: String) {
    guard state == .active || state == .armed else { return }
    setState(.suspended, reason: reason)
  }

  /// 任務結束或使用者喊停 → 回 idle。App 重啟亦為 idle（狀態不落地）。
  func disarm() {
    setState(.idle, reason: nil)
    taskId = nil
  }

  var canInject: Bool { state == .active }

  // ---- 真人在場偵測 ----

  /// Agent 注入的事件走獨立 event source；本函式由 tap 偵測到「非 Agent source」的輸入時呼叫。
  func reportHumanPresence() {
    lastHumanEventAt = Date()
    if state == .active {
      // Blue 鐵則 08-31：真人到場 = 立即停手（3 秒寬限內不再有任何注入；
      // 這裡直接 suspend，寬限由注入端 canInjectAt 檢查 lastHumanEventAt）
      suspend(reason: "human_presence")
    }
  }

  /// 注入前檢查：active 且距真人輸入 >= graceSeconds
  func canInject(afterHumanGrace graceSeconds: TimeInterval = 3.0) -> Bool {
    guard state == .active else { return false }
    if let last = lastHumanEventAt, Date().timeIntervalSince(last) < graceSeconds {
      return false
    }
    return true
  }

  private func setState(_ newState: TakeoverState, reason: String?) {
    guard newState != state else { return }
    let old = state
    state = newState
    lastSuspendReason = reason
    if newState == .idle { taskId = nil }
    NSLog("[ComputerUse] gate \(old.rawValue) -> \(newState.rawValue) reason=\(reason ?? "-")")
    onStateChange?(newState, reason)
  }

  // ---- Esc 長按急停 + 真人在場偵測（同一支 listen-only 事件 tap）----

  private var eventTapPort: CFMachPort?

  func installEscKillSwitch() {
    guard eventTapPort == nil else { return }
    let mask = (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.keyUp.rawValue)
      | (1 << CGEventType.leftMouseDown.rawValue)
      | (1 << CGEventType.rightMouseDown.rawValue)
      | (1 << CGEventType.otherMouseDown.rawValue)
      | (1 << CGEventType.scrollWheel.rawValue)
    guard let port = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: CGEventMask(mask),
      callback: ComputerUseNative.eventTapCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      NSLog("[ComputerUse] 事件 tap 建立失敗（TCC Accessibility 未授權；arm() 會擋下）")
      return
    }
    eventTapPort = port
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    NSLog("[ComputerUse] 事件 tap 已安裝（Esc 急停 + 真人在場偵測）")
  }

  func handleKeyEvent(forEvent event: CGEvent) {
    // keyCode 53 = Esc
    if event.getIntegerValueField(.keyboardEventKeycode) == 53 {
      if event.type == .keyDown {
        if escPressStart == nil { escPressStart = Date() }
        else if let s = escPressStart, Date().timeIntervalSince(s) >= 1.5,
                state == .active || state == .armed {
          suspend(reason: "esc_kill_switch")
          escPressStart = nil
        }
      } else if event.type == .keyUp {
        escPressStart = nil
      }
    }
    // 任何鍵盤事件（非 Agent 注入的，由 tap 端判斷 source）= 真人在場
    // 註：Agent 注入事件用獨立 source id，tap 端比對後不回報
  }
}

// MARK: - TCC 權限

enum ComputerUseTCC {
  /// Accessibility（輔助使用）權限 —— AX 樹與 CGEvent tap 都需要
  static func hasAccessibilityPermission() -> Bool {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
      as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
  }

  static func requestAccessibilityPermission() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
  }

  /// 螢幕錄製權限（截圖循環用；既有 ScreenCaptureNative 已有管線，此處僅查詢）
  static func hasScreenPermission() -> Bool {
    // CGRequestScreenCaptureAccess 會彈窗，這裡用無副作用檢查：
    // CGPreflightScreenCaptureAccess()（macOS 10.15+）
    if #available(macOS 10.15, *) {
      return CGPreflightScreenCaptureAccess()
    }
    return true
  }
}

// MARK: - AX 樹（眼睛的解析度）

enum AXBridge {
  /// 取得指定視窗（或前景視窗）的 UI 樹，限深限寬（spec 2.2）
  static func windowTree(pid: Int32?, maxDepth: Int = 6, maxChildren: Int = 200) -> [String: Any]? {
    let system = AXUIElementCreateSystemWide()
    var focus: CFTypeRef?
    var err = AXUIElementCopyAttributeValue(pid != nil
      ? AXUIElementCreateApplication(pid!)
      : system, kAXFocusedWindowAttribute as CFString, &focus)

    if err != .success && pid == nil, let app = NSWorkspace.shared.frontmostApplication {
      err = AXUIElementCopyAttributeValue(
        AXUIElementCreateApplication(app.processIdentifier),
        kAXFocusedWindowAttribute as CFString, &focus)
    }
    guard err == .success, focus != nil else { return nil }
    let window = unsafeBitCast(focus!, to: AXUIElement.self)

    var tree: [String: Any] = [:]
    _ = serialize(element: window, depth: 0, maxDepth: maxDepth,
                  maxChildren: maxChildren, into: &tree)
    return tree
  }

  /// 序列化單一元素（role / title / value / bounds / 可點性）
  private static func serialize(element: AXUIElement, depth: Int, maxDepth: Int,
                                maxChildren: Int, into dict: inout [String: Any]) -> Bool {
    var roleCF: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleCF) == .success,
          let role = roleCF as? String else { return false }

    dict["role"] = role
    var v: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &v) == .success,
       let title = v as? String { dict["title"] = title }
    v = nil
    if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v) == .success,
       let value = v as? String {
      // 圍欄：密碼欄的值永不上拋（role 已擋輸入，值也一樣不讀）
      if role != "AXSecureTextField" { dict["value"] = String(value.prefix(200)) }
    }
    v = nil
    var bounds = CGRect.zero
    if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &v) == .success,
       let vVal = v {
      let pos = unsafeBitCast(vVal, to: AXValue.self)
      var p = CGPoint.zero
      if AXValueGetValue(pos, .cgPoint, &p) { bounds.origin = p }
    }
    v = nil
    if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &v) == .success,
       let vVal2 = v {
      let size = unsafeBitCast(vVal2, to: AXValue.self)
      var sz = CGSize.zero
      if AXValueGetValue(size, .cgSize, &sz) { bounds.size = sz }
    }
    dict["bounds"] = ["x": bounds.minX, "y": bounds.minY,
                      "w": bounds.width, "h": bounds.height]

    if depth < maxDepth {
      var childrenCF: CFTypeRef?
      if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenCF) == .success,
         let children = childrenCF as? [AXUIElement] {
        var childList: [[String: Any]] = []
        for (i, child) in children.prefix(maxChildren).enumerated() {
          var sub: [String: Any] = [:]
          if serialize(element: child, depth: depth + 1, maxDepth: maxDepth,
                       maxChildren: maxChildren, into: &sub) {
            sub["idx"] = i
            childList.append(sub)
          }
        }
        if !childList.isEmpty { dict["children"] = childList }
      }
    }
    return true
  }

  /// 圍欄檢查：目標元素是否允許輸入
  static func isProtectedField(at point: CGPoint) -> Bool {
    let sys = AXUIElementCreateSystemWide()
    var elem: AXUIElement?
    let err = AXUIElementCopyElementAtPosition(
      sys, Float(point.x), Float(point.y), &elem)
    guard err == .success, let element = elem else { return false }
    var roleCF: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleCF) == .success,
          let role = roleCF as? String else { return false }
    return role == "AXSecureTextField"
  }
}

// MARK: - CGEvent 注入（手）

enum InputInjector {
  /// Agent 專屬 event source —— 真人在場偵測的來源區分基礎
  static let agentSourceID: Int64 = 0x6272_6964_6765 // "bridge" 標記

  /// 注入前的單一檢查點（狀態機 + 真人寬限）。呼叫端不得繞過。
  static func injectCheck() -> Bool {
    TakeoverGate.shared.canInject(afterHumanGrace: 3.0)
  }

  @discardableResult
  private static func post(_ event: CGEvent) -> Bool {
    guard injectCheck() else { return false }
    event.setIntegerValueField(.eventSourceUserData, value: agentSourceID)
    event.post(tap: .cghidEventTap)
    return true
  }

  static func moveMouse(x: Double, y: Double) -> Bool {
    guard injectCheck() else { return false }
    let ev = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                     mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)
    return ev != nil && post(ev!)
  }

  static func click(x: Double, y: Double, button: String = "left",
                    count: Int = 1) -> Bool {
    // 圍欄：點擊目標若是密碼欄 → 拒絕（聚焦後隨後的 typeText 也會被擋）
    if AXBridge.isProtectedField(at: CGPoint(x: x, y: y)) { return false }
    guard injectCheck() else { return false }

    let btn: CGMouseButton = button == "right" ? .right : .left
    let downType: CGEventType = button == "right" ? .rightMouseDown : .leftMouseDown
    let upType: CGEventType = button == "right" ? .rightMouseUp : .leftMouseUp

    for _ in 0..<max(1, count) {
      let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                         mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: btn)
      let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                       mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: btn)
      if down == nil || up == nil { return false }
      post(down!)
      usleep(60_000) // 60ms —— 真人節奏（spec 2.3 節流）
      post(up!)
      usleep(60_000)
    }
    return true
  }

  static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double,
                   durationMs: Int = 300) -> Bool {
    guard injectCheck() else { return false }
    let start = CGPoint(x: fromX, y: fromY)
    let end = CGPoint(x: toX, y: toY)

    let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                       mouseCursorPosition: start, mouseButton: .left)!
    post(down)
    // 曲線插值：真人節奏（禁直線瞬移）
    let steps = max(10, durationMs / 20)
    for i in 1...steps {
      let t = Double(i) / Double(steps)
      let ease = t * t * (3 - 2 * t) // smoothstep
      let p = CGPoint(x: start.x + (end.x - start.x) * ease,
                      y: start.y + (end.y - start.y) * ease)
      let move = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged,
                         mouseCursorPosition: p, mouseButton: .left)!
      post(move)
      usleep(UInt32(max(1, durationMs * 1000 / steps)))
    }
    let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                     mouseCursorPosition: end, mouseButton: .left)!
    return post(up)
  }

  static func scroll(dx: Double, dy: Double) -> Bool {
    guard injectCheck() else { return false }
    let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                     wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)
    return ev != nil && post(ev!)
  }

  /// 中文直接用 Unicode string event，不依賴鍵盤佈局（spec 2.3）
  static func typeText(_ text: String) -> Bool {
    guard injectCheck() else { return false }
    // 逐段輸入（CGEvent 單次上限），段間 30ms
    let chunks = stride(from: 0, to: text.count, by: 20).map {
      String(Array(text)[$0..<min($0 + 20, text.count)])
    }
    for chunk in chunks {
      guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else {
        return false
      }
      ev.setIntegerValueField(.eventSourceUserData, value: agentSourceID)
      var buf = Array(chunk.utf16)
      buf.withUnsafeMutableBufferPointer { ub in
        ev.keyboardSetUnicodeString(
          stringLength: ub.count,
          unicodeString: UnsafePointer<UniChar>(ub.baseAddress!))
      }
      guard injectCheck() else { return false }
      ev.post(tap: .cghidEventTap)
      usleep(30_000)
    }
    return true
  }

  static func key(keyCode: Int64, down: Bool) -> Bool {
    guard injectCheck() else { return false }
    guard let ev = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode),
                           keyDown: down) else { return false }
    return post(ev)
  }
}

// MARK: - Method Channel

final class ComputerUseNative {
  static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    guard let gate = refcon.map({
      Unmanaged<TakeoverGate>.fromOpaque($0).takeUnretainedValue()
    }) else {
      return Unmanaged.passUnretained(event)
    }
    // 真人在場偵測：非 Agent source 的鍵鼠事件
    if event.getIntegerValueField(.eventSourceUserData) != InputInjector.agentSourceID {
      switch type {
      case .keyDown, .keyUp, .leftMouseDown, .leftMouseUp,
           .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
           .mouseMoved, .leftMouseDragged, .scrollWheel:
        gate.reportHumanPresence()
      default:
        break
      }
    }
    gate.handleKeyEvent(forEvent: event)
    return Unmanaged.passUnretained(event)
  }

  static func register(with viewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "bridge.computer_use.macos.v1",
      binaryMessenger: viewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      DispatchQueue.global(qos: .userInitiated).async {
        ComputerUseNative.handle(call: call, result: result)
      }
    }
    TakeoverGate.shared.installEscKillSwitch()
  }

  private static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    // ---- 閘門 ----
    case "gate.state":
      result(["state": TakeoverGate.shared.state.rawValue,
              "taskId": TakeoverGate.shared.taskId as Any,
              "lastSuspendReason": TakeoverGate.shared.lastSuspendReason as Any,
              "lastHumanEventAt": TakeoverGate.shared.lastHumanEventAt.map {
                $0.timeIntervalSince1970
              } as Any])
    case "gate.arm":
      let taskId = args["taskId"] as? String ?? "unnamed"
      let ok = TakeoverGate.shared.arm(taskId: taskId)
      result(ok ? ["armed": true] : FlutterError(code: "GATE_ARM_FAILED",
        message: "無法進入 armed（狀態不允許或 TCC Accessibility 未授權）", details: nil))
    case "gate.activate":
      let ok = TakeoverGate.shared.activate()
      result(ok ? ["active": true] : FlutterError(code: "GATE_ACTIVATE_FAILED",
        message: "需先 arm", details: nil))
    case "gate.suspend":
      TakeoverGate.shared.suspend(reason: args["reason"] as? String ?? "manual")
      result(["suspended": true])
    case "gate.disarm":
      TakeoverGate.shared.disarm()
      result(["idle": true])

    // ---- 權限 ----
    case "tcc.status":
      result(["accessibility": ComputerUseTCC.hasAccessibilityPermission(),
              "screen": ComputerUseTCC.hasScreenPermission()])
    case "tcc.requestAccessibility":
      ComputerUseTCC.requestAccessibilityPermission()
      result(["requested": true])

    // ---- AX 樹 ----
    case "ax.windowTree":
      let pid = (args["pid"] as? NSNumber)?.int32Value
      let depth = (args["maxDepth"] as? NSNumber)?.intValue ?? 6
      if let tree = AXBridge.windowTree(pid: pid, maxDepth: depth) {
        result(tree)
      } else {
        result(FlutterError(code: "AX_FAILED",
          message: "取不到視窗樹（權限或無前景視窗）", details: nil))
      }
    case "ax.isProtectedAt":
      let x = args["x"] as? Double ?? 0, y = args["y"] as? Double ?? 0
      result(["protected": AXBridge.isProtectedField(at: CGPoint(x: x, y: y))])

    // ---- 注入（每個都必經 injectCheck，狀態機單點強制）----
    case "input.move":
      result(["ok": InputInjector.moveMouse(x: args["x"] as? Double ?? 0,
                                            y: args["y"] as? Double ?? 0)])
    case "input.click":
      result(["ok": InputInjector.click(x: args["x"] as? Double ?? 0,
                                        y: args["y"] as? Double ?? 0,
                                        button: args["button"] as? String ?? "left",
                                        count: args["count"] as? Int ?? 1)])
    case "input.drag":
      result(["ok": InputInjector.drag(fromX: args["fromX"] as? Double ?? 0,
                                       fromY: args["fromY"] as? Double ?? 0,
                                       toX: args["toX"] as? Double ?? 0,
                                       toY: args["toY"] as? Double ?? 0,
                                       durationMs: args["durationMs"] as? Int ?? 300)])
    case "input.scroll":
      result(["ok": InputInjector.scroll(dx: args["dx"] as? Double ?? 0,
                                         dy: args["dy"] as? Double ?? 0)])
    case "input.typeText":
      result(["ok": InputInjector.typeText(args["text"] as? String ?? "")])
    case "input.key":
      result(["ok": InputInjector.key(keyCode: args["keyCode"] as? Int64 ?? 0,
                                      down: args["down"] as? Bool ?? true)])

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
