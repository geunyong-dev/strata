import AppKit
import SwiftUI

/// SwiftUI Menu can retain its AppKit focus ring despite focusEffectDisabled().
/// Set the native control's ring explicitly without disabling keyboard access.
struct AppearanceMenu: NSViewRepresentable {
    @Binding var selection: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func makeControl() -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.bezelStyle = .inline
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("화면 색상")
        button.toolTip = "화면 색상"
        return button
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = Self.makeControl()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let title = NSMenuItem(title: "화면 색상", action: nil, keyEquivalent: "")
        title.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: "화면 색상")
        menu.addItem(title)
        for (name, value) in [("어둡게", "dark"), ("밝게", "light"), ("시스템 설정", "system")] {
            let item = NSMenuItem(title: name, action: #selector(Coordinator.choose(_:)), keyEquivalent: "")
            item.representedObject = value
            item.target = context.coordinator
            menu.addItem(item)
        }
        button.menu = menu
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.focusRingType = .none
        for item in button.itemArray {
            guard let value = item.representedObject as? String else { continue }
            item.state = value == selection ? .on : .off
        }
        button.setAccessibilityValue(button.itemArray.first { ($0.representedObject as? String) == selection }?.title)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: AppearanceMenu
        init(_ parent: AppearanceMenu) { self.parent = parent }

        @objc func choose(_ item: NSMenuItem) {
            guard let value = item.representedObject as? String,
                  ["dark", "light", "system"].contains(value) else { return }
            parent.selection = value
        }
    }
}
