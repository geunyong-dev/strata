import AppKit
import SwiftUI

/// A native three-state checkbox: clicking a mixed selection selects the group.
struct GroupSelectionCheckbox: NSViewRepresentable {
    let title: String
    let selectedCount: Int
    let totalCount: Int
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator,
                              action: #selector(Coordinator.toggleSelection))
        button.allowsMixedState = true
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.state = selectedCount == 0 ? .off : (selectedCount == totalCount ? .on : .mixed)
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: GroupSelectionCheckbox

        init(_ parent: GroupSelectionCheckbox) { self.parent = parent }

        @objc func toggleSelection(_ sender: NSButton) {
            guard parent.isEnabled else { return }
            let selectAll = parent.selectedCount < parent.totalCount
            sender.state = selectAll ? .on : .off
            parent.onChange(selectAll)
        }
    }
}
