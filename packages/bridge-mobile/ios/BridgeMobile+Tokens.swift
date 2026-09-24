// BridgeMobile+Tokens.swift — iOS Swift Design Tokens
// 自動生成於 2026-08-06T03:12:35.941592
// 從 lib/theme/bridge_design_system.dart 提取
// 共 **85 個 UIColor bridge() token**
//
// 用法：
//   view.backgroundColor = .bridge(.canvas)
//   label.textColor = .bridge(.textPrimary)
//
// 重新生成：`dart run tool/gen_bridge_swift_tokens.dart`

#if canImport(UIKit)
import UIKit

public extension UIColor {
    /// Bridge Design System 枚舉
    enum BridgeDS {}

    /// 把 UIColor.bridge(.tokenName) 對應到 BridgeDS token
    static func bridge(_ token: BridgeDS) -> UIColor {
        switch token {

        // MARK: - Surface (6)
        case .canvas: return UIColor(red: 7/255.0, green: 8/255.0, blue: 10/255.0, alpha: 1.000)
        case .surface: return UIColor(red: 16/255.0, green: 17/255.0, blue: 17/255.0, alpha: 1.000)
        case .surfaceElevated: return UIColor(red: 27/255.0, green: 28/255.0, blue: 30/255.0, alpha: 1.000)
        case .surfaceHover: return UIColor(red: 37/255.0, green: 40/255.0, blue: 41/255.0, alpha: 1.000)
        case .darkPanel: return UIColor(red: 30/255.0, green: 30/255.0, blue: 46/255.0, alpha: 1.000)
        case .darkCanvas: return UIColor(red: 13/255.0, green: 13/255.0, blue: 26/255.0, alpha: 1.000)

        // MARK: - Text (6)
        case .textPrimary: return UIColor(red: 249/255.0, green: 249/255.0, blue: 249/255.0, alpha: 1.000)
        case .textSecondary: return UIColor(red: 206/255.0, green: 206/255.0, blue: 206/255.0, alpha: 1.000)
        case .textTertiary: return UIColor(red: 156/255.0, green: 156/255.0, blue: 157/255.0, alpha: 1.000)
        case .textMuted: return UIColor(red: 106/255.0, green: 107/255.0, blue: 108/255.0, alpha: 1.000)
        case .textQuaternary: return UIColor(red: 67/255.0, green: 67/255.0, blue: 69/255.0, alpha: 1.000)
        case .textOnAccent: return UIColor(red: 1/255, green: 1/255, blue: 1/255, alpha: 1.000)

        // MARK: - Border (6)
        case .borderSubtle: return UIColor(red: 1/255, green: 1/255, blue: 1/255, alpha: 0.059)
        case .borderDefault: return UIColor(red: 1/255, green: 1/255, blue: 1/255, alpha: 0.102)
        case .borderStrong: return UIColor(red: 1/255, green: 1/255, blue: 1/255, alpha: 0.200)
        case .surfaceGlass: return UIColor(red: 1/255, green: 1/255, blue: 1/255, alpha: 0.051)
        case .surfaceGlassHover: return UIColor(red: 1/255, green: 1/255, blue: 1/255, alpha: 0.078)
        case .dividerIndigo: return UIColor(red: 42/255.0, green: 42/255.0, blue: 74/255.0, alpha: 1.000)

        // MARK: - Accent (12)
        case .accentRed: return UIColor(red: 1/255, green: 99/255.0, blue: 99/255.0, alpha: 1.000)
        case .accentBlue: return UIColor(red: 85/255.0, green: 179/255.0, blue: 1/255, alpha: 1.000)
        case .accentYellow: return UIColor(red: 1/255, green: 188/255.0, blue: 51/255.0, alpha: 1.000)
        case .accentPurple: return UIColor(red: 83/255.0, green: 58/255.0, blue: 253/255.0, alpha: 1.000)
        case .accentNavy: return UIColor(red: 6/255.0, green: 27/255.0, blue: 49/255.0, alpha: 1.000)
        case .accentMagenta: return UIColor(red: 249/255.0, green: 107/255.0, blue: 238/255.0, alpha: 1.000)
        case .accentRuby: return UIColor(red: 234/255.0, green: 34/255.0, blue: 97/255.0, alpha: 1.000)
        case .accentMiro: return UIColor(red: 91/255.0, green: 118/255.0, blue: 254/255.0, alpha: 1.000)
        case .toolPurple: return UIColor(red: 124/255.0, green: 77/255.0, blue: 1/255, alpha: 1.000)
        case .toolPurpleLight: return UIColor(red: 179/255.0, green: 136/255.0, blue: 1/255, alpha: 1.000)
        case .brightCyan: return UIColor(red: 0/255, green: 212/255.0, blue: 1/255, alpha: 1.000)
        case .goldAccent: return UIColor(red: 1/255, green: 215/255.0, blue: 0/255, alpha: 1.000)

        // MARK: - Status (14)
        case .successGreen: return UIColor(red: 107/255.0, green: 142/255.0, blue: 107/255.0, alpha: 1.000)
        case .successDark: return UIColor(red: 46/255.0, green: 125/255.0, blue: 50/255.0, alpha: 1.000)
        case .softGreen: return UIColor(red: 129/255.0, green: 199/255.0, blue: 132/255.0, alpha: 1.000)
        case .accentGreen: return UIColor(red: 95/255.0, green: 201/255.0, blue: 146/255.0, alpha: 1.000)
        case .errorRed: return UIColor(red: 239/255.0, green: 83/255.0, blue: 80/255.0, alpha: 1.000)
        case .alertRed: return UIColor(red: 1/255, green: 23/255.0, blue: 68/255.0, alpha: 1.000)
        case .red500: return UIColor(red: 244/255.0, green: 67/255.0, blue: 54/255.0, alpha: 1.000)
        case .red400: return UIColor(red: 239/255.0, green: 83/255.0, blue: 80/255.0, alpha: 1.000)
        case .red700mat: return UIColor(red: 211/255.0, green: 47/255.0, blue: 47/255.0, alpha: 1.000)
        case .red700: return UIColor(red: 211/255.0, green: 47/255.0, blue: 47/255.0, alpha: 1.000)
        case .berlinRed: return UIColor(red: 200/255.0, green: 16/255.0, blue: 46/255.0, alpha: 1.000)
        case .green500: return UIColor(red: 76/255.0, green: 175/255.0, blue: 80/255.0, alpha: 1.000)
        case .green400: return UIColor(red: 102/255.0, green: 187/255.0, blue: 106/255.0, alpha: 1.000)
        case .green700: return UIColor(red: 56/255.0, green: 142/255.0, blue: 60/255.0, alpha: 1.000)

        // MARK: - Tag (10)
        case .tagSuccessBg: return UIColor(red: 14/255.0, green: 27/255.0, blue: 18/255.0, alpha: 1.000)
        case .tagSuccessFg: return UIColor(red: 184/255.0, green: 232/255.0, blue: 204/255.0, alpha: 1.000)
        case .tagErrorBg: return UIColor(red: 27/255.0, green: 14/255.0, blue: 14/255.0, alpha: 1.000)
        case .tagErrorFg: return UIColor(red: 1/255, green: 173/255.0, blue: 173/255.0, alpha: 1.000)
        case .tagInfoBg: return UIColor(red: 14/255.0, green: 21/255.0, blue: 27/255.0, alpha: 1.000)
        case .tagInfoFg: return UIColor(red: 179/255.0, green: 220/255.0, blue: 1/255, alpha: 1.000)
        case .tagBrainBg: return UIColor(red: 14/255.0, green: 10/255.0, blue: 27/255.0, alpha: 1.000)
        case .tagBrainFg: return UIColor(red: 185/255.0, green: 185/255.0, blue: 249/255.0, alpha: 1.000)
        case .tagWarnBg: return UIColor(red: 27/255.0, green: 22/255.0, blue: 14/255.0, alpha: 1.000)
        case .tagWarnFg: return UIColor(red: 1/255, green: 213/255.0, blue: 128/255.0, alpha: 1.000)

        // MARK: - Background (3)
        case .bgLightRed: return UIColor(red: 1/255, green: 243/255.0, blue: 242/255.0, alpha: 1.000)
        case .bgLightGreen: return UIColor(red: 241/255.0, green: 248/255.0, blue: 233/255.0, alpha: 1.000)
        case .bgVeryLightRed: return UIColor(red: 1/255, green: 248/255.0, blue: 247/255.0, alpha: 1.000)

        // MARK: - Node (7)
        case .fileBlue: return UIColor(red: 74/255.0, green: 158/255.0, blue: 1/255, alpha: 1.000)
        case .sopOrange: return UIColor(red: 1/255, green: 180/255.0, blue: 84/255.0, alpha: 1.000)
        case .pinkAccent: return UIColor(red: 1/255, green: 107/255.0, blue: 157/255.0, alpha: 1.000)
        case .slate: return UIColor(red: 142/255.0, green: 154/255.0, blue: 175/255.0, alpha: 1.000)
        case .teal: return UIColor(red: 78/255.0, green: 205/255.0, blue: 196/255.0, alpha: 1.000)
        case .deepPurple: return UIColor(red: 124/255.0, green: 137/255.0, blue: 1/255, alpha: 1.000)
        case .lightBlue: return UIColor(red: 66/255.0, green: 165/255.0, blue: 245/255.0, alpha: 1.000)

        // MARK: - Particle (5)
        case .particle1: return UIColor(red: 83/255.0, green: 58/255.0, blue: 253/255.0, alpha: 1.000)
        case .particle2: return UIColor(red: 249/255.0, green: 107/255.0, blue: 238/255.0, alpha: 1.000)
        case .particle3: return UIColor(red: 85/255.0, green: 179/255.0, blue: 1/255, alpha: 1.000)
        case .particle4: return UIColor(red: 95/255.0, green: 201/255.0, blue: 146/255.0, alpha: 1.000)
        case .particleGlow: return UIColor(red: 83/255.0, green: 58/255.0, blue: 253/255.0, alpha: 0.251)

        // MARK: - Grey (6)
        case .grey300: return UIColor(red: 224/255.0, green: 224/255.0, blue: 224/255.0, alpha: 1.000)
        case .grey400: return UIColor(red: 189/255.0, green: 189/255.0, blue: 189/255.0, alpha: 1.000)
        case .grey600: return UIColor(red: 117/255.0, green: 117/255.0, blue: 117/255.0, alpha: 1.000)
        case .grey700: return UIColor(red: 97/255.0, green: 97/255.0, blue: 97/255.0, alpha: 1.000)
        case .grey800: return UIColor(red: 66/255.0, green: 66/255.0, blue: 66/255.0, alpha: 1.000)
        case .lightGray: return UIColor(red: 224/255.0, green: 224/255.0, blue: 224/255.0, alpha: 1.000)

        // MARK: - MaterialStandard (6)
        case .blue500: return UIColor(red: 33/255.0, green: 150/255.0, blue: 243/255.0, alpha: 1.000)
        case .blue700: return UIColor(red: 25/255.0, green: 118/255.0, blue: 210/255.0, alpha: 1.000)
        case .orangeStd: return UIColor(red: 1/255, green: 152/255.0, blue: 0/255, alpha: 1.000)
        case .orange500: return UIColor(red: 1/255, green: 152/255.0, blue: 0/255, alpha: 1.000)
        case .orange700: return UIColor(red: 245/255.0, green: 124/255.0, blue: 0/255, alpha: 1.000)
        case .orange300: return UIColor(red: 1/255, green: 183/255.0, blue: 77/255.0, alpha: 1.000)

        // MARK: - Hint (4)
        case .hintPurple: return UIColor(red: 136/255.0, green: 136/255.0, blue: 170/255.0, alpha: 1.000)
        case .hintPink: return UIColor(red: 206/255.0, green: 147/255.0, blue: 216/255.0, alpha: 1.000)
        case .googleBlue: return UIColor(red: 26/255.0, green: 115/255.0, blue: 232/255.0, alpha: 1.000)
        case .infoBlue: return UIColor(red: 74/255.0, green: 144/255.0, blue: 217/255.0, alpha: 1.000)
        }
    }
}
#endif
