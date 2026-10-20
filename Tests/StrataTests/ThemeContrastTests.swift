import XCTest
import SwiftUI
import AppKit
@testable import Strata

final class ThemeContrastTests: XCTestCase {
    @MainActor
    func testSemanticTextContrastInBothAppearances() throws {
        let pairs: [(String, Color, Color)] = [
            ("accent", StrataTheme.accentText, StrataTheme.accentSurface),
            ("success", StrataTheme.successText, StrataTheme.successSurface),
            ("warning", StrataTheme.warningText, StrataTheme.warningSurface),
            ("error", StrataTheme.errorText, StrataTheme.errorSurface),
            ("info", StrataTheme.infoText, StrataTheme.infoSurface),
            ("button", StrataTheme.actionForeground, StrataTheme.actionFill),
            ("button-hover", StrataTheme.actionForeground, StrataTheme.actionHover)
        ]
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            for (role, foreground, background) in pairs {
                XCTAssertGreaterThanOrEqual(try contrast(foreground, background, appearance), 4.5, "\(name): \(role)")
            }
            for foreground in [StrataTheme.accentText, StrataTheme.successText, StrataTheme.warningText,
                               StrataTheme.errorText, StrataTheme.infoText, StrataTheme.secondary,
                               StrataTheme.tertiary, StrataTheme.irreversible] {
                for background in [StrataTheme.base, StrataTheme.raised, StrataTheme.sunken] {
                    XCTAssertGreaterThanOrEqual(try contrast(foreground, background, appearance), 4.5)
                }
            }
            for background in [StrataTheme.base, StrataTheme.raised, StrataTheme.accentSurface] {
                XCTAssertGreaterThanOrEqual(try contrast(StrataTheme.accentBorder, background, appearance), 3)
            }
        }
    }

    @MainActor
    private func contrast(_ a: Color, _ b: Color, _ appearance: NSAppearance) throws -> Double {
        func luminance(_ color: Color) throws -> Double {
            var resolved: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolved = NSColor(color).usingColorSpace(.sRGB)
            }
            let color = try XCTUnwrap(resolved)
            func linear(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return linear(color.redComponent) * 0.2126 + linear(color.greenComponent) * 0.7152 + linear(color.blueComponent) * 0.0722
        }
        let x = try luminance(a), y = try luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
