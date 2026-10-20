import AppKit
import SwiftUI

enum StrataLayout {
    static let coreWidth = 220.0
    static let contentInset = 28.0
}

enum StrataTheme {
    private static func adaptive(_ name: String, light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }

    static let base = adaptive("strata.base", light: 0xEDEFEA, dark: 0x15191A)
    static let raised = adaptive("strata.raised", light: 0xF7F8F5, dark: 0x1D2224)
    static let sunken = adaptive("strata.sunken", light: 0xE3E6E0, dark: 0x0F1213)
    static let line = adaptive("strata.line", light: 0xD6DAD3, dark: 0x2B3133)
    static let strongLine = adaptive("strata.strongLine", light: 0xB8BEB6, dark: 0x3D4547)
    static let primary = adaptive("strata.primary", light: 0x1E2422, dark: 0xE6E9E6)
    static let secondary = adaptive("strata.secondary", light: 0x5D6764, dark: 0x9BA5A2)
    // Slightly stronger than decorative guide text to keep small labels legible.
    static let tertiary = adaptive("strata.tertiary", light: 0x576960, dark: 0x97ADA2)
    static let lichen = adaptive("strata.lichen", light: 0x7E9478, dark: 0x93AC8C)
    static let glacier = adaptive("strata.glacier", light: 0x6F9BB0, dark: 0x86B4C9)
    static let amber = adaptive("strata.amber", light: 0xB5823C, dark: 0xD9A356)
    static let slate = adaptive("strata.slate", light: 0x6B6E9E, dark: 0x8A8DBD)
    static let basalt = adaptive("strata.basalt", light: 0x58605F, dark: 0x7C8685)
    static let irreversible = adaptive("strata.irreversible", light: 0xA8442F, dark: 0xE18B72)

    // Semantic roles: opaque surfaces keep contrast predictable in both appearances.
    // Mineral colors above are for charts/decorations, not small text.
    static let accentText = adaptive("strata.accentText", light: 0x216477, dark: 0x87C8D2)
    static let accentSurface = adaptive("strata.accentSurface", light: 0xDBECEF, dark: 0x203940)
    static let accentBorder = adaptive("strata.accentBorder", light: 0x39798B, dark: 0x639DAA)
    static let actionFill = adaptive("strata.actionFill", light: 0x216477, dark: 0x87C8D2)
    static let actionForeground = adaptive("strata.actionForeground", light: 0xFFFFFF, dark: 0x102C34)
    static let actionHover = adaptive("strata.actionHover", light: 0x194F60, dark: 0xA0D9E0)
    static let successText = adaptive("strata.successText", light: 0x306342, dark: 0xA0CFAC)
    static let successSurface = adaptive("strata.successSurface", light: 0xE0ECDF, dark: 0x253B2D)
    static let warningText = adaptive("strata.warningText", light: 0x805615, dark: 0xE0B96F)
    static let warningSurface = adaptive("strata.warningSurface", light: 0xF3E8D1, dark: 0x403521)
    static let errorText = adaptive("strata.errorText", light: 0x9C414E, dark: 0xF0A0AB)
    static let errorSurface = adaptive("strata.errorSurface", light: 0xF5E2E6, dark: 0x442B32)
    static let infoText = adaptive("strata.infoText", light: 0x535580, dark: 0xB0AFE4)
    static let infoSurface = adaptive("strata.infoSurface", light: 0xE7E5F1, dark: 0x303047)
}

extension View {
    func strataCard() -> some View {
        background(StrataTheme.raised, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(StrataTheme.line, lineWidth: 1))
    }
}
