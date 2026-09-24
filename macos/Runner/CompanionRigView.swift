// CompanionRigView.swift — v4 NSImageView 架構
// [小葵 2026-09-12 深夜決戰版] 徹底放棄 CALayer 座標系——v1~v3 的教訓：
// ①backing layer 的 sublayerTransform 被 AppKit 每幀重置（圖被「無形黑框」裁切的真兇）
// ②CALayer y 軸語義在 view-backed 環境下混合，四種翻轉法全部互相打架
// 解法：NSImageView 子視圖 + frameCenterRotation（AppKit 佈局原生 y-down，
// 旋轉繞「視圖中心」——pivot 錨點用「視圖 frame 對齊」實現）。全座標 = 原圖 y-down。
import AppKit

// MARK: - 動畫參數（沿用 v3 實證值）
struct RigParams: Equatable {
    var breatheAmp: Double = 0.006
    var breatheSpeed: Double = 1.0
    var headNodAmp: Double = 0.05
    var headTiltAmp: Double = 0.04
    var headSpeed: Double = 0.7
    var armRAmp: Double = 0.0
    var armRSpeed: Double = 0.5
    var armRAbs: Double = 1.0
    var armLAmp: Double = 0.0
    var armLSpeed: Double = 0.45
    var bodySwayAmp: Double = 0.008
    var bodySwaySpeed: Double = 0.4

    static let idle = RigParams()
    static let reading = RigParams(breatheAmp: 0.006, breatheSpeed: 1.1, headNodAmp: 0.05, headTiltAmp: 0.03, headSpeed: 0.8, armRAmp: 0.25, armRSpeed: 0.5, armRAbs: 1.0, armLAmp: 0.12, armLSpeed: 0.45, bodySwayAmp: 0.008, bodySwaySpeed: 0.4)
    static let writing = RigParams(breatheAmp: 0.006, breatheSpeed: 1.1, headNodAmp: 0.04, headTiltAmp: 0.03, headSpeed: 1.2, armRAmp: 0.20, armRSpeed: 1.4, armRAbs: 0.0, armLAmp: 0.05, armLSpeed: 0.45, bodySwayAmp: 0.008, bodySwaySpeed: 0.4)
    static let stuck = RigParams(breatheAmp: 0.004, breatheSpeed: 0.6, headNodAmp: 0.02, headTiltAmp: 0.12, headSpeed: 0.25, armRAmp: 0.06, armRSpeed: 0.2, armRAbs: 1.0, armLAmp: 0.02, armLSpeed: 0.45, bodySwayAmp: 0.004, bodySwaySpeed: 0.4)
    static let idea = RigParams(breatheAmp: 0.010, breatheSpeed: 1.4, headNodAmp: 0.04, headTiltAmp: 0.03, headSpeed: 1.6, armRAmp: 0.35, armRSpeed: 1.0, armRAbs: 1.0, armLAmp: 0.12, armLSpeed: 0.45, bodySwayAmp: 0.008, bodySwaySpeed: 0.4)
    static let celebrating = RigParams(breatheAmp: 0.012, breatheSpeed: 1.8, headNodAmp: 0.08, headTiltAmp: 0.04, headSpeed: 1.8, armRAmp: 0.45, armRSpeed: 1.8, armRAbs: 0.0, armLAmp: 0.25, armLSpeed: 1.5, bodySwayAmp: 0.020, bodySwaySpeed: 1.2)

    static func forState(_ stateId: String) -> RigParams {
        switch stateId {
        case "writing": return .writing
        case "reading": return .reading
        case "stuck": return .stuck
        case "idea": return .idea
        case "celebrating": return .celebrating
        default: return .idle
        }
    }
}

// MARK: - 幾何表（原圖 y-down 座標）
struct RigGeometry {
    let name: String
    let fullW: CGFloat
    let fullH: CGFloat
    let headBox: CGRect
    let headPivot: CGPoint
    let armRBox: CGRect
    let armRPivot: CGPoint
    let armLBox: CGRect
    let armLPivot: CGPoint
    let headFactor: Double   // 素材可動度（頭髮與身體相連=0）
    let armFactor: Double    // 素材可動度（arm 切片含軀幹=0）

    static let xiaoqiao = RigGeometry(
        name: "xiaoqiao", fullW: 561, fullH: 914,
        headBox: CGRect(x: 233, y: 0, width: 194, height: 212),
        headPivot: CGPoint(x: 321, y: 200),
        armRBox: CGRect(x: 203, y: 183, width: 149, height: 189),
        armRPivot: CGPoint(x: 285, y: 215),
        armLBox: CGRect(x: 313, y: 223, width: 169, height: 209),
        armLPivot: CGPoint(x: 348, y: 250),
        headFactor: 1.0, armFactor: 1.0
    )

    static let mimemi = RigGeometry(
        name: "mimemi", fullW: 864, fullH: 1152,
        headBox: CGRect(x: 285, y: 0, width: 294, height: 286),  // +8 蓋住 body 挖洞縫
        headPivot: CGPoint(x: 371, y: 264),
        armRBox: CGRect(x: 552, y: 275, width: 108, height: 492),
        armRPivot: CGPoint(x: 518, y: 299),
        armLBox: CGRect(x: 212, y: 264, width: 90, height: 480),
        armLPivot: CGPoint(x: 319, y: 288),
        headFactor: 1.0, armFactor: 1.0
    )

    static func forCompanion(_ name: String) -> RigGeometry? {
        let n = name.lowercased()
        if n.contains("小橋") || n.contains("xiaoqiao") { return .xiaoqiao }
        if n.contains("mimemi") { return .mimemi }
        return nil
    }
}

// MARK: - rig 視圖 v4（NSImageView ×4，純 AppKit 佈局）
final class CompanionRigView: NSView {
    private let bodyView = NSImageView()
    private let torsoView = NSImageView()  // [小葵 2026-09-13] 胸口呼吸覆蓋層（同源裁切）
    private var torsoLoaded = false
    private let headView = NSImageView()
    private let armRView = NSImageView()
    private let armLView = NSImageView()
    private var displayTimer: Timer?
    private var t: Double = 0
    private var blend: Double = 1.0
    private var fromParams: RigParams = .idle
    private var targetParams: RigParams = .idle
    private var geo: RigGeometry = .xiaoqiao
    private var isLoaded = false
    private var stateId: String = "idle"
    // 構圖
    private var fitScale: CGFloat = 1
    private var fitDx: CGFloat = 0
    private var fitDy: CGFloat = 0
    // 部件的「基準 frame」（縮放後、未旋轉）——旋轉繞 pivot 用 frameCenterRotation 技巧
    private var headBase: CGRect = .zero
    private var armRBase: CGRect = .zero
    private var armLBase: CGRect = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for v in [bodyView, torsoView, armRView, armLView, headView] {
            v.imageScaling = .scaleProportionallyUpOrDown
            v.alphaValue = 1
            addSubview(v)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    deinit { displayTimer?.invalidate() }

    override var mouseDownCanMoveWindow: Bool { true }
    override var isFlipped: Bool { true }  // 我自己的佈局全用 y-down——NSView isFlipped 對 addSubview 的子視圖完全有效（AppKit 佈局原生支援）

    var currentParams: RigParams {
        RigParams(
            breatheAmp: fromParams.breatheAmp + (targetParams.breatheAmp - fromParams.breatheAmp) * blend,
            breatheSpeed: fromParams.breatheSpeed + (targetParams.breatheSpeed - fromParams.breatheSpeed) * blend,
            headNodAmp: fromParams.headNodAmp + (targetParams.headNodAmp - fromParams.headNodAmp) * blend,
            headTiltAmp: fromParams.headTiltAmp + (targetParams.headTiltAmp - fromParams.headTiltAmp) * blend,
            headSpeed: fromParams.headSpeed + (targetParams.headSpeed - fromParams.headSpeed) * blend,
            armRAmp: fromParams.armRAmp + (targetParams.armRAmp - fromParams.armRAmp) * blend,
            armRSpeed: fromParams.armRSpeed + (targetParams.armRSpeed - fromParams.armRSpeed) * blend,
            armRAbs: fromParams.armRAbs + (targetParams.armRAbs - fromParams.armRAbs) * blend,
            armLAmp: fromParams.armLAmp + (targetParams.armLAmp - fromParams.armLAmp) * blend,
            armLSpeed: fromParams.armLSpeed + (targetParams.armLSpeed - fromParams.armLSpeed) * blend,
            bodySwayAmp: fromParams.bodySwayAmp + (targetParams.bodySwayAmp - fromParams.bodySwayAmp) * blend,
            bodySwaySpeed: fromParams.bodySwaySpeed + (targetParams.bodySwaySpeed - fromParams.bodySwaySpeed) * blend
        )
    }

    func setState(_ id: String) {
        stateId = id
        fromParams = currentParams
        switch id {
        case "writing": targetParams = .writing
        case "reading": targetParams = .reading
        case "stuck": targetParams = .stuck
        case "idea": targetParams = .idea
        case "celebrating": targetParams = .celebrating
        default: targetParams = .idle
        }
        blend = 0
    }

    func load(geo: RigGeometry, assetDir: URL) {
        self.geo = geo
        func img(_ name: String) -> NSImage? { NSImage(contentsOfFile: assetDir.appendingPathComponent(name).path) }
        guard let body = img("body_full.png"),
              let head = img("head.png"),
              let armR = img("arm_R.png"),
              let armL = img("arm_L.png") else {
            isLoaded = false
            return
        }
        bodyView.image = body
        headView.image = head
        armRView.image = armR
        armLView.image = armL
        if let torso = img("torso.png") {
            torsoView.image = torso
            torsoLoaded = true
        } else {
            torsoView.image = nil
            torsoLoaded = false
        }
        isLoaded = true
        needsLayout = true
        if displayTimer == nil {
            displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.tickFrame()
            }
        }
    }

    private func tickFrame() {
        t += 1.0 / 60.0
        if blend < 1 { blend = min(1, blend + 0.025) }  // ~0.6s 狀態過渡
        render()
    }

    override func layout() {
        super.layout()
        guard isLoaded else { return }
        let W = geo.fullW, H = geo.fullH
        // 全身構圖：等比縮放置中
        let scale = min(bounds.width / W, bounds.height / H)
        fitScale = scale
        fitDx = (bounds.width - W * scale) / 2
        fitDy = (bounds.height - H * scale) / 2

        func place(_ v: NSImageView, box: CGRect) -> CGRect {
            let f = NSRect(x: fitDx + box.minX * scale,
                           y: fitDy + box.minY * scale,
                           width: box.width * scale,
                           height: box.height * scale)
            v.frame = f
            return f
        }
        place(bodyView, box: CGRect(x: 0, y: 0, width: W, height: H))
        if torsoLoaded { place(torsoView, box: CGRect(x: 0, y: 290, width: W, height: 530)) }  // y290-820 不含頭
        // [診斷] superview 座標系確認
        if let sv = superview {
            let d = "rigView frame=\(frame) bounds=\(bounds) isFlipped=\(isFlipped) super=\(sv.classForCoder) superFrame=\(sv.frame) superFlipped=\(sv.isFlipped)\n"
            let dp = NSTemporaryDirectory() + "/rig_diag2.txt"
            try? d.write(toFile: dp, atomically: true, encoding: .utf8)
        }
        headBase = place(headView, box: geo.headBox)
        armRBase = place(armRView, box: geo.armRBox)
        armLBase = place(armLView, box: geo.armLBox)
    }

    private func render() {
        guard isLoaded else { return }
        let p = currentParams

        // [小葵 2026-09-13 最後一搏] 胸口呼吸模式（Blue 拍板：只做胸口，不搖頭擺手）
        // 結構：body_full 靜態墊底（永遠不動）＋ torso 覆蓋層以胸口點縮放。
        // torso 與底圖同源（同張圖的裁切）——縮放時邊緣外露的是底下相同內容，
        // 數學上不可能出現縫或破圖。頭/臂切片隱藏（靜態模式下不需要）。
        if torsoLoaded {
            let breathe = 1.0 + Foundation.sin(t * 0.7) * 0.018  // 2.8s 呼吸、1.8% 幅度（局部覆蓋層可感知）
            let chestX = fitDx + geo.fullW * fitScale / 2          // 胸口 x（畫面中央）
            let chestY = fitDy + 430 * fitScale                     // 胸口 y（原圖 y≈430）
            let base = NSRect(x: fitDx + 0, y: fitDy + 290 * fitScale, width: geo.fullW * fitScale, height: 530 * fitScale)
            let b = CGFloat(breathe)
            torsoView.frame = NSRect(x: chestX - (chestX - base.minX) * b,
                                     y: chestY - (chestY - base.minY) * b,
                                     width: base.width * b,
                                     height: base.height * b)
            headView.isHidden = true
            armRView.isHidden = true
            armLView.isHidden = true
            return
        }

        // （舊動態 rig 路徑——保留供重啟）
        let breathe = 1.0 + Foundation.sin(t * p.breatheSpeed) * p.breatheAmp
        let cx = fitDx + geo.fullW * fitScale / 2
        let cy = fitDy + geo.fullH * fitScale / 2
        func scaled(_ base: CGRect) -> CGRect {
            let w = base.width * CGFloat(breathe), h = base.height * CGFloat(breathe)
            return CGRect(x: cx - (cx - base.minX) * CGFloat(breathe),
                          y: cy - (cy - base.minY) * CGFloat(breathe),
                          width: w, height: h)
        }
        let swayX = CGFloat(Foundation.sin(t * p.bodySwaySpeed) * p.bodySwayAmp * Double(geo.fullW) * Double(fitScale))

        bodyView.frame = scaled(NSRect(x: fitDx, y: fitDy, width: geo.fullW * fitScale, height: geo.fullH * fitScale)).offsetBy(dx: swayX, dy: 0)

        let nod = Foundation.sin(t * p.headSpeed) * p.headNodAmp * geo.headFactor
        let tilt = Foundation.sin(t * 0.13) * p.headTiltAmp * geo.headFactor
        rotateAroundPivot(headView, base: headBase, pivot: geo.headPivot, angle: -(nod + tilt), swayX: swayX, breathe: breathe, center: (cx, cy))

        let waveR = Foundation.sin(t * p.armRSpeed)
        let armR = (waveR * (1 - p.armRAbs) + abs(waveR) * p.armRAbs) * p.armRAmp * geo.armFactor
        rotateAroundPivot(armRView, base: armRBase, pivot: geo.armRPivot, angle: -armR, swayX: swayX, breathe: breathe, center: (cx, cy))

        let armL = (Foundation.sin(t * p.armLSpeed) * 0.5 + abs(Foundation.sin(t * 0.23))) * p.armLAmp * geo.armFactor
        rotateAroundPivot(armLView, base: armLBase, pivot: geo.armLPivot, angle: armL, swayX: swayX, breathe: breathe, center: (cx, cy))
    }

    /// 繞「原圖座標 pivot」旋轉視圖：把 pivot 當視圖中心（frame 往反方向偏移 half-size），
    /// 用 frameCenterRotation（AppKit 原生：繞視圖中心旋轉，y-down 佈局下 angle 正=順時針）
    private func rotateAroundPivot(_ v: NSImageView, base: CGRect, pivot: CGPoint, angle: Double, swayX: CGFloat, breathe: Double, center: (CGFloat, CGFloat)) {
        // 呼吸縮放後的 pivot 螢幕位置
        let cx = center.0, cy = center.1
        let px = cx - (cx - (fitDx + pivot.x * fitScale)) * CGFloat(breathe) + swayX
        let py = cy - (cy - (fitDy + pivot.y * fitScale)) * CGFloat(breathe)
        // 呼吸後的部件尺寸
        let w = base.width * CGFloat(breathe), h = base.height * CGFloat(breathe)
        // 「讓 pivot 落在視圖中心」的 frame——contents 用 imageAlignment 補償：
        // NSImageView 把圖填滿 frame（scaleProportionallyUpOrDown）→ 圖會跟 frame 一起轉，
        // 圖中的 pivot 點（相對 box）就會在視圖中心 → 旋轉繞到圖中 pivot ✓
        // 補償：視圖中心=pivot → frame.origin = pivot - half(w,h)（圖中 pivot 相對 box 的偏移）
        // 視圖 frame 中心對齊「圖中 pivot 的縮放位置」——圖填滿視圖，故：
        let boxMinX = (base.origin.x - fitDx) / fitScale  // 反推原圖 box minX
        let boxMinY = (base.origin.y - fitDy) / fitScale
        let relX = (pivot.x - boxMinX) * fitScale * CGFloat(breathe)  // pivot 在圖內的偏移（縮放後）
        let relY = (pivot.y - boxMinY) * fitScale * CGFloat(breathe)
        v.frame = NSRect(x: px - relX, y: py - relY, width: w, height: h)
        v.frameCenterRotation = CGFloat(angle * 180 / .pi)
    }
}
