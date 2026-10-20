import SwiftUI

struct StrataHeader: View {
    @Binding var appearance: String
    let isBusy: Bool
    let scan: () -> Void
    var showsScan = true
    @ScaledMetric(relativeTo: .body) private var panelWidth = StrataLayout.coreWidth

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.3.layers.3d.down.right")
                    .font(.system(size: 21, weight: .light)).foregroundStyle(StrataTheme.successText)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STRATA").font(.system(size: 15, weight: .semibold, design: .rounded)).tracking(2)
                    Text("STORAGE EXPLORER").font(.system(size: 8, design: .monospaced)).tracking(0.8)
                        .foregroundStyle(StrataTheme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(width: max(StrataLayout.coreWidth, panelWidth), height: 64)
            .background(StrataTheme.sunken)
            .overlay(alignment: .trailing) { Rectangle().fill(StrataTheme.line).frame(width: 1) }

            HStack(spacing: 24) {
                Text("저장공간").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 16)
                AppearanceMenu(selection: $appearance)
                    .frame(width: 36, height: 32)
                if showsScan {
                Button(action: scan) {
                    Label("다시 스캔", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(StrataSurfaceButtonStyle())
                .disabled(isBusy)
                }
            }
            .padding(.horizontal, StrataLayout.contentInset)
            .frame(height: 64)
            .background(StrataTheme.base)
        }
        .foregroundStyle(StrataTheme.primary)
    }
}

/// Low-chrome controls with native Button keyboard and accessibility behavior.
struct StrataSurfaceButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        Surface(configuration: configuration, selected: selected)
    }

    private struct Surface: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .foregroundStyle(selected ? StrataTheme.accentText : StrataTheme.primary)
                .background(selected ? StrataTheme.accentSurface :
                                (configuration.isPressed || hovering ? StrataTheme.line.opacity(0.5) : StrataTheme.raised))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(
                    selected ? StrataTheme.accentBorder : StrataTheme.line, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }
    }
}

struct StrataPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? StrataTheme.actionForeground : StrataTheme.secondary)
            .background(isEnabled ? (configuration.isPressed ? StrataTheme.actionHover : StrataTheme.actionFill) : StrataTheme.sunken,
                        in: RoundedRectangle(cornerRadius: 6))
    }
}
