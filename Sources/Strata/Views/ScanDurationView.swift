import SwiftUI

enum ScanDuration {
    static func text(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        guard interval.isFinite, interval > 0 else { return "0초" }
        let seconds = Int(min(interval, Double(Int.max / 2)))
        if seconds >= 3600 { return "\(seconds / 3600)시간 \(seconds % 3600 / 60)분 \(seconds % 60)초" }
        if seconds >= 60 { return "\(seconds / 60)분 \(seconds % 60)초" }
        return "\(seconds)초"
    }
}

struct ScanDurationView: View {
    let startedAt: Date
    var finishedAt: Date? = nil

    var body: some View {
        if let finishedAt {
            badge("검사 소요 시간", end: finishedAt)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                badge("검사 경과 시간", end: context.date)
            }
        }
    }

    private func badge(_ title: String, end: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock").accessibilityHidden(true)
            Text(title)
            Text(ScanDuration.text(from: startedAt, to: end))
                .fontWeight(.semibold).monospacedDigit()
        }
        .font(.system(size: 15)).foregroundStyle(StrataTheme.accentText)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(StrataTheme.accentSurface, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
