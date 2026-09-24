import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // [隊友訊息流 C7 2026-09-08] Cmd+Q / 選單列退出攔截——
  // 有活躍背景任務（Dart 端寫入 UserDefaults 的 bridge_has_active_tasks）
  // 時先彈原生確認框：確認退出才真的終止，否則取消（任務繼續背景跑）。
  // 「唯有小圖示右鍵選關閉 App 才真正關閉」的最後防線。
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    let hasActive = UserDefaults.standard.bool(forKey: "bridge_has_active_tasks")
    if !hasActive {
      return .terminateNow
    }
    let alert = NSAlert()
    alert.messageText = "還有任務在進行"
    alert.informativeText = "背景仍有任務執行中，退出會中斷它們。\n\n確定要退出橋樑嗎？"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "仍要退出")
    alert.addButton(withTitle: "讓任務繼續")
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      return .terminateNow
    }
    return .terminateCancel
  }

  // [v244 Blue 卡頓令 2026-09-03] webview 卡頓三刀：
  // ① App Nap 除名——背景/非焦點時 macOS 會對 App 睡眠限速（webview 自轉卡頓主嫌）
  // ② 停用視窗自動還原延遲渲染
  // ③ processInfo 活動宣告：userInteractive 等級，告訴系統「我在跟使用者互動」
  private var _activity: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // App Nap 除名（傳統手段）+ 現代 process activity 雙保險
    ProcessInfo.processInfo.disableAutomaticTermination("galaxy-live")
    ProcessInfo.processInfo.disableSuddenTermination()
    let opts: ProcessInfo.ActivityOptions = [.userInitiated, .idleSystemSleepDisabled]
    _activity = ProcessInfo.processInfo.beginActivity(options: opts, reason: "Bridge galaxy webview live render") as NSObjectProtocol
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    super.applicationDidFinishLaunching(notification)
  }
}
