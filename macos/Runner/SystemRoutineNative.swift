// SystemRoutineNative.swift
// [刀 5 延伸 SR.1 2026-09-09 Blue 令] 全電腦示範錄製——原生端。
//
// 「示範錄製只能錄橋樑 App 嗎？不。錄全電腦——agent 一學就會，
//   解決 MCP 不完備時的代操作問題。」
//
// 設計：
//   listen-only CGEventTap（不攔截不修改——純觀察）收
//   點擊/鍵盤/滾輪 → 點擊當下 AX 快照（哪個 App 的哪個元素）
//   → FlutterEventChannel 串流回 Dart。
//
// 隱私鐵則（設計稿 §5）：
//   - AXSecureTextField 值一律遮罩
//   - 一般輸入框值截 30 字
//   - 事件只在錄製中送出（start/stop 之外靜默）
//
// 設計稿：docs/specs/2026-09-09-system-routine.md

import Cocoa
import FlutterMacOS

// MARK: - Flutter 註冊（EventChannel 串流 + start/stop 控制）

enum SystemRoutineNative {
  static func register(with registrar: FlutterViewController) {
    let messenger = registrar.engine.binaryMessenger
    // 事件串流：bridge.system_routine.macos.v1/events
    let eventChannel = FlutterEventChannel(
      name: "bridge.system_routine.macos.v1/events",
      binaryMessenger: messenger)
    let streamHandler = RoutineStreamHandler()
    eventChannel.setStreamHandler(streamHandler)

    // 控制：bridge.system_routine.macos.v1（start/stop）
    let methodChannel = FlutterMethodChannel(
      name: "bridge.system_routine.macos.v1",
      binaryMessenger: messenger)
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        SystemRoutineListener.shared.setRecording(true)
        result(["ok": true])
      case "stop":
        SystemRoutineListener.shared.setRecording(false)
        result(["ok": true])
      case "isRecording":
        result(["recording": SystemRoutineListener.shared.isRecording()])

      // [刀 5 延伸 P2.1] AX 錨點重播——找元素＋精準動作
      case "ax.findElement":
        let args = call.arguments as? [String: Any] ?? [:]
        DispatchQueue.global(qos: .userInitiated).async {
          let r = AXActor.findElement(
            appName: args["app"] as? String ?? "",
            role: args["role"] as? String ?? "",
            title: args["title"] as? String ?? "")
          DispatchQueue.main.async { result(r) }
        }
      case "ax.press":
        // args: app/role/title——找到就按（AXPress）
        let args = call.arguments as? [String: Any] ?? [:]
        DispatchQueue.global(qos: .userInitiated).async {
          let ok = AXActor.pressOnElement(
            appName: args["app"] as? String ?? "",
            role: args["role"] as? String ?? "",
            title: args["title"] as? String ?? "")
          DispatchQueue.main.async { result(["ok": ok]) }
        }
      case "ax.setValue":
        // args: app/role/title/value——找到就填（AXSetValue）
        let args = call.arguments as? [String: Any] ?? [:]
        DispatchQueue.global(qos: .userInitiated).async {
          let ok = AXActor.setValueOnElement(
            appName: args["app"] as? String ?? "",
            role: args["role"] as? String ?? "",
            title: args["title"] as? String ?? "",
            value: args["value"] as? String ?? "")
          DispatchQueue.main.async { result(["ok": ok]) }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

final class RoutineStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?

  func onListen(withArguments arguments: Any?,
                eventSink: @escaping FlutterEventSink) -> FlutterError? {
    sink = eventSink
    SystemRoutineListener.shared.attach(sink: eventSink)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }
}

// MARK: - AX 動作執行者（重播的手）

/// [刀 5 延伸 P2.1] AX 錨點重播——按「app+role+title」找元素並精準動作。
/// 找元素：App focused window 起點 DFS（廣度優先迭代，避免深樹遞迴溢出）。
enum AXActor {
  struct Found {
    var frame: CGRect
  }

  /// 在指定 App 中找 role+title 匹配的元素——回傳 frame（找不到 nil）
  static func findElement(appName: String, role: String, title: String) -> [String: Any]? {
    guard let app = appElement(named: appName) else { return nil }
    guard let element = findIn(app: app, role: role, title: title) else { return nil }

    var pos: CFTypeRef?
    var size: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success
    else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pos as! AXValue, .cgPoint, &p)
    AXValueGetValue(size as! AXValue, .cgSize, &s)
    return ["x": Double(p.x + s.width / 2), "y": Double(p.y + s.height / 2)]
  }

  /// 找到就 AXPress（按鈕/選單項）
  static func pressOnElement(appName: String, role: String, title: String) -> Bool {
    guard let app = appElement(named: appName),
          let element = findIn(app: app, role: role, title: title) else { return false }
    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
  }

  /// 找到就 AXSetValue（輸入框填值）
  static func setValueOnElement(appName: String, role: String, title: String, value: String) -> Bool {
    guard let app = appElement(named: appName),
          let element = findIn(app: app, role: role, title: title) else { return false }
    return AXUIElementSetAttributeValue(
      element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
  }

  // ── 內部 ──

  private static func appElement(named name: String) -> AXUIElement? {
    let running = NSWorkspace.shared.runningApplications.first {
      $0.localizedName == name && $0.activationPolicy == .regular
    }
    guard let pid = running?.processIdentifier else { return nil }
    return AXUIElementCreateApplication(pid)
  }

  /// BFS 找元素：role 精確匹配 + title 精確或包含（title 常因動態內容微調）
  private static func findIn(app: AXUIElement, role: String, title: String) -> AXUIElement? {
    var queue: [AXUIElement] = [app]
    var visited = 0
    let maxNodes = 3000  // 防走不完的大樹（如 Xcode）

    while !queue.isEmpty && visited < maxNodes {
      let current = queue.removeFirst()
      visited += 1

      var roleCF: CFTypeRef?
      if AXUIElementCopyAttributeValue(current, kAXRoleAttribute as CFString, &roleCF) == .success,
         let r = roleCF as? String, r == role {
        var titleCF: CFTypeRef?
        if AXUIElementCopyAttributeValue(current, kAXTitleAttribute as CFString, &titleCF) == .success,
           let t = titleCF as? String {
          let titleOk = title.isEmpty ? true : (t == title || t.contains(title) || title.contains(t))
          if titleOk && !title.isEmpty { return current }
        }
      }

      // 子樹展開
      var kidsCF: CFTypeRef?
      if AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &kidsCF) == .success,
         let kids = kidsCF as? [AXUIElement] {
        queue.append(contentsOf: kids)
      }
    }
    return nil
  }
}

// MARK: - 錄製事件監聽器

final class SystemRoutineListener {
  static let shared = SystemRoutineListener()

  private var tapPort: CFMachPort?
  private var recording = false
  private var eventSink: FlutterEventSink?

  // [層 1 SR.5 2026-09-13] 打字緩衝——連續可列印 key 重組為 type 事件
  private var typeBuffer = String()
  private var typeCtx: [String: Any?] = [:]  // 打字開始時 focused element 快照

  // ── 生命週期 ──

  func attach(sink: @escaping FlutterEventSink) {
    eventSink = sink
    installTapIfNeeded()
  }

  func setRecording(_ on: Bool) {
    recording = on
    NSLog("[SystemRoutine] 錄製 \(on ? "開始" : "停止")")
  }

  func isRecording() -> Bool { recording }

  private func installTapIfNeeded() {
    guard tapPort == nil else { return }
    let mask = (1 << CGEventType.leftMouseDown.rawValue)
      | (1 << CGEventType.leftMouseUp.rawValue)
      | (1 << CGEventType.keyDown.rawValue)
      | (1 << CGEventType.scrollWheel.rawValue)
    guard let port = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,   // 純觀察——不影響任何事件
      eventsOfInterest: CGEventMask(mask),
      callback: SystemRoutineListener.tapCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      NSLog("[SystemRoutine] tap 建立失敗（需輔助使用權限）")
      return
    }
    tapPort = port
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    NSLog("[SystemRoutine] listen tap 已安裝")
  }

  // ── 事件處理（在 main runloop）──

  private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let listener = refcon.map({
      Unmanaged<SystemRoutineListener>.fromOpaque($0).takeUnretainedValue()
    }) else {
      return Unmanaged.passUnretained(event)
    }
    listener.handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
  }

  private func handle(type: CGEventType, event: CGEvent) {
    guard recording, let sink = eventSink else { return }
    // 忽略 Agent 自己注入的事件（重播時不錄——防回圈）
    if event.getIntegerValueField(.eventSourceUserData)
        == InputInjector.agentSourceID { return }

    let t = Date().timeIntervalSince1970
    let loc = event.location

    switch type {
    case .leftMouseDown:
      let ax = AXSnapshot.describe(at: loc)
      let payload: [String: Any?] = [
        "action": "click",
        "t": t,
        "x": Double(loc.x), "y": Double(loc.y),
        "app": ax.app, "window": ax.window, "role": ax.role,
        "title": ax.title, "value": ax.value, "masked": ax.masked,
      ]
      sink(payload)
    case .keyDown:
      let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
      let flags = event.flags
      var mods: [String] = []
      if flags.contains(.maskCommand) { mods.append("cmd") }
      if flags.contains(.maskShift) { mods.append("shift") }
      if flags.contains(.maskAlternate) { mods.append("alt") }
      if flags.contains(.maskControl) { mods.append("ctrl") }
      let payload: [String: Any?] = [
        "action": "key",
        "t": t,
        "keyCode": keyCode,
        "mods": mods,
        "app": AXSnapshot.frontmostApp(),
      ]
      sink(payload)
    case .scrollWheel:
      let dy = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
      let payload: [String: Any?] = [
        "action": "scroll",
        "t": t,
        "dy": dy,
        "x": Double(loc.x), "y": Double(loc.y),
        "app": AXSnapshot.frontmostApp(),
      ]
      sink(payload)
    default:
      break
    }
  }
}

// MARK: - AX 快照（游標下是什麼）

enum AXSnapshot {
  struct Desc {
    var app: String = ""
    var window: String = ""
    var role: String = ""
    var title: String = ""
    var value: String? = nil
    var masked = false
  }

  static func frontmostApp() -> String {
    NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
  }

  /// 游標座標 → 完整元素描述（app/視窗/角色/標題/值；密碼框遮罩）
  static func describe(at point: CGPoint) -> Desc {
    var d = Desc()
    let sys = AXUIElementCreateSystemWide()
    var elem: AXUIElement?
    let err = AXUIElementCopyElementAtPosition(
      sys, Float(point.x), Float(point.y), &elem)
    guard err == .success, let element = elem else { return d }

    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    d.app = NSRunningApplication(processIdentifier: pid)?.localizedName
      ?? "pid:\(pid)"

    var cf: CFTypeRef?
    if AXUIElementCopyAttributeValue(
        element, kAXRoleAttribute as CFString, &cf) == .success,
       let role = cf as? String { d.role = role }
    cf = nil
    if AXUIElementCopyAttributeValue(
        element, kAXTitleAttribute as CFString, &cf) == .success,
       let title = cf as? String { d.title = title }
    cf = nil

    // 隱私鐵則：密碼框值一律遮罩；一般值截 30 字
    if d.role == "AXSecureTextField" {
      d.masked = true
      d.value = "****"
    } else if AXUIElementCopyAttributeValue(
        element, kAXValueAttribute as CFString, &cf) == .success,
              let v = cf as? String, !v.isEmpty {
      d.value = v.count > 30 ? String(v.prefix(30)) + "…" : v
    }

    // 視窗標題：從所屬 App 的 focused window 拿
    if let appEl = AXUIElementCreateApplication(pid) as AXUIElement? {
      cf = nil
      if AXUIElementCopyAttributeValue(
          appEl, kAXFocusedWindowAttribute as CFString, &cf) == .success,
         let win = cf {
        var wcf: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            win as! AXUIElement, kAXTitleAttribute as CFString, &wcf) == .success,
           let wt = wcf as? String { d.window = wt }
      }
    }
    return d
  }
}
