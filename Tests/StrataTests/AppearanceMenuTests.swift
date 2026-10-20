import AppKit
import SwiftUI
import XCTest
@testable import Strata

final class AppearanceMenuTests: XCTestCase {
    @MainActor
    func testNativeControlDoesNotDrawFocusRing() {
        let button = AppearanceMenu.makeControl()
        XCTAssertEqual(button.focusRingType, .none)
        XCTAssertTrue(button.isEnabled)
        XCTAssertTrue(button.acceptsFirstResponder)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 60),
                              styleMask: .borderless, backing: .buffered, defer: false)
        button.frame = NSRect(x: 10, y: 10, width: 36, height: 32)
        window.contentView?.addSubview(button)
        XCTAssertTrue(window.makeFirstResponder(button))
        XCTAssertTrue(window.firstResponder === button)
        XCTAssertEqual(button.focusRingType, .none)
        window.makeFirstResponder(nil)
        button.removeFromSuperview()
    }

    @MainActor
    func testMenuSelectionUpdatesBindingAndRejectsUnknownValues() {
        var value = "dark"
        let menu = AppearanceMenu(selection: Binding(get: { value }, set: { value = $0 }))
        let coordinator = menu.makeCoordinator()
        let item = NSMenuItem()
        for option in ["light", "system", "dark"] {
            item.representedObject = option
            coordinator.choose(item)
            XCTAssertEqual(value, option)
        }
        item.representedObject = "invalid"
        coordinator.choose(item)
        XCTAssertEqual(value, "dark")
    }
}
