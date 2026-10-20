import SwiftUI

struct CoreSamplePanel: View {
    let snapshot: ScanSnapshot?
    let progress: ScanProgress?
    let selectedPath: String?
    let hasAnimated: Bool
    let didAnimate: () -> Void
    let select: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var panelWidth = StrataLayout.coreWidth
    @State private var reveal: CGFloat = 0
    @State private var showOther = false
    @State private var showMeasurementInfo = false
    @State private var showSpaceDetails = false

    init(snapshot: ScanSnapshot?, progress: ScanProgress? = nil, selectedPath: String?, hasAnimated: Bool,
         didAnimate: @escaping () -> Void, select: @escaping (String) -> Void) {
        self.snapshot = snapshot
        self.progress = progress
        self.selectedPath = selectedPath
        self.hasAnimated = hasAnimated
        self.didAnimate = didAnimate
        self.select = select
        _reveal = State(initialValue: hasAnimated ? 1 : 0)
    }

    private var breakdown: CoreStorageBreakdown? {
        if let progress {
            return CoreStorageBreakdown(volume: progress.volume, areas: progress.areas, isScanning: true)
        }
        return snapshot.map { CoreStorageBreakdown(volume: $0.volume, areas: $0.volumeAreas, evidence: $0.spaceDiagnostics?.containerUsage) }
    }

    var body: some View {
        GeometryReader { available in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("코어 시료").font(.headline)
                        Text(progress != nil ? "스캔 중 · 잠정 측정값" : breakdown?.isMeasuredOnly == true ? "측정된 영역의 용량" : "저장공간의 단면")
                            .font(.caption).foregroundStyle(StrataTheme.secondary)
                    }
                    if let breakdown, breakdown.total > 0 {
                        chart(breakdown)
                            .frame(height: max(340, available.size.height - 245))
                            .onAppear {
                                if progress != nil { reveal = 1; didAnimate(); return }
                                guard !hasAnimated else { reveal = 1; return }
                                didAnimate()
                                withAnimation(reduceMotion ? nil : .easeOut(duration: 1.2)) { reveal = 1 }
                            }
                        notes(breakdown)
                    } else {
                        RoundedRectangle(cornerRadius: 3).fill(StrataTheme.line)
                            .frame(height: max(320, available.size.height - 180))
                            .overlay {
                                VStack(spacing: 8) {
                                    Image(systemName: "square.3.layers.3d.down.right")
                                    Text("스캔 대기").font(.caption)
                                }.foregroundStyle(StrataTheme.secondary)
                            }
                        Text("스캔 후 실제 용량 비율로 단면을 표시합니다.")
                            .font(.caption).foregroundStyle(StrataTheme.secondary)
                    }
                    if let trash = (progress?.areas ?? snapshot?.volumeAreas ?? []).first(where: \.isTrash),
                       trash.allocatedBytes == 0 {
                        Button { select(trash.path) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: trash.inaccessibleItemCount > 0 ? "lock.fill" : "trash")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("휴지통").fontWeight(.medium)
                                    Text(trash.capacityText)
                                }
                                Spacer(minLength: 0)
                            }
                            .font(.caption).foregroundStyle(StrataTheme.infoText)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(StrataTheme.infoSurface, in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).disabled(progress != nil)
                        .help(trash.measurementNote ?? "현재 사용자 휴지통")
                    }
                }
                .padding(16)
            }
        }
        .frame(width: max(StrataLayout.coreWidth, panelWidth))
        .background(StrataTheme.sunken)
        .overlay(alignment: .trailing) { Rectangle().fill(StrataTheme.line).frame(width: 1) }
        .sheet(isPresented: $showSpaceDetails) {
            if let snapshot { SpaceDiagnosticDetailsView(snapshot: snapshot) }
        }
    }

    private func chart(_ data: CoreStorageBreakdown) -> some View {
        GeometryReader { geometry in
            let height = geometry.size.height - 24
            let columnX = 39.0
            let columnWidth = 44.0
            let labelX = 97.0
            let labelWidth = max(80, geometry.size.width - labelX)
            let starts = data.bands.indices.map { index in
                data.bands.prefix(index).reduce(0.0) { $0 + $1.bytes } / data.total * height
            }
            let heights = data.bands.map { $0.bytes / data.total * height }
            let centers = CoreStorageBreakdown.labelCenters(
                ideal: data.bands.indices.map { starts[$0] + heights[$0] / 2 }, height: height)
            ZStack(alignment: .topLeading) {
                ruler(total: data.total, height: height)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(data.bands.enumerated()), id: \.element.id) { index, band in
                        bandShape(band)
                            .frame(width: columnWidth, height: heights[index])
                            .offset(y: starts[index])
                    }
                }
                .frame(width: columnWidth, height: height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(StrataTheme.strongLine, lineWidth: 1))
                .mask(alignment: .bottom) { Rectangle().frame(height: height * (progress != nil ? 1 : reveal)) }
                .offset(x: columnX)
                .accessibilityHidden(true)

                ForEach(Array(data.bands.enumerated()), id: \.element.id) { index, band in
                    Path { path in
                        path.move(to: CGPoint(x: columnX + columnWidth + 1, y: starts[index] + heights[index] / 2))
                        path.addLine(to: CGPoint(x: labelX - 4, y: centers[index]))
                    }
                    .stroke(isSelected(band) ? accent(band.texture) : StrataTheme.strongLine, lineWidth: 1)
                    .accessibilityHidden(true)
                    label(band, total: data.total)
                        .frame(width: labelWidth, height: 40, alignment: .leading)
                        .offset(x: labelX, y: centers[index] - 20)
                }
            }
            // Animate actual completed scans, never estimated cleanup savings.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: snapshot?.finishedAt)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: progress?.updatedAt)
        }
    }

    private func ruler(total: Double, height: Double) -> some View {
        let step = CoreStorageBreakdown.tickStep(total: total, height: height)
        let ticks = Array(stride(from: 0.0, to: total, by: step))
        let unit = total >= 1_000_000_000_000 ? 1_000_000_000_000.0 : total >= 1_000_000_000 ? 1_000_000_000.0 : 1_000_000.0
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(StrataTheme.strongLine).frame(width: 1, height: height).offset(x: 34)
            ForEach(ticks, id: \.self) { tick in
                let y = tick / total * height
                if height - y > 16 {
                    Text((tick / unit).formatted(.number.precision(.fractionLength(0...1))))
                        .font(.system(size: 9, design: .monospaced))
                        .frame(width: 28, alignment: .trailing).offset(y: max(0, y - 5))
                    Rectangle().fill(StrataTheme.strongLine).frame(width: 5, height: 1).offset(x: 30, y: y)
                }
            }
            Text((total / unit).formatted(.number.precision(.fractionLength(0...1))))
                .font(.system(size: 9, design: .monospaced))
                .frame(width: 32, alignment: .trailing).offset(y: height - 8)
            Text(unit == 1_000_000_000_000 ? "TB" : unit == 1_000_000_000 ? "GB" : "MB")
                .font(.system(size: 9, design: .monospaced)).offset(x: 15, y: height + 8)
        }
        .foregroundStyle(StrataTheme.secondary)
        .accessibilityHidden(true)
    }

    private func bandShape(_ band: CoreStorageBreakdown.Band) -> some View {
        Rectangle()
            .fill(band.kind == .free ? StrataTheme.base : accent(band.texture).opacity(colorScheme == .dark ? 0.72 : 0.65))
            .overlay {
                RockHatching(pattern: band.kind == .free ? 5 : band.texture)
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
                    .opacity(band.kind == .free ? 0.06 : colorScheme == .dark ? 0.21 : 0.12)
            }
            .overlay {
                if band.kind != .free {
                    LinearGradient(colors: [.black.opacity(0.17), .white.opacity(0.06), .clear, .black.opacity(0.18)],
                                   startPoint: .leading, endPoint: .trailing)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(StrataTheme.sunken).frame(height: 1) }
            .overlay { if isSelected(band) { Rectangle().strokeBorder(accent(band.texture), lineWidth: 1.8) } }
            .opacity(selectedPath == nil || isSelected(band) || band.areas.isEmpty ? 1 : 0.8)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selectedPath)
            .onTapGesture { activate(band) }
            .help("\(band.name) · \(band.formattedBytes)")
    }

    @ViewBuilder
    private func label(_ band: CoreStorageBreakdown.Band, total: Double) -> some View {
        if progress == nil, band.kind == .systemVolumes || band.kind == .unmeasured {
            Button { showSpaceDetails = true } label: {
                labelContent(band).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityDescription(band, total: total))
            .accessibilityHint("시스템 공간과 남은 측정 차이의 설명을 엽니다")
        } else if band.areas.isEmpty || progress != nil {
            labelContent(band)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription(band, total: total))
                .help(band.kind == .unmeasured ? "디스크 사용량과 폴더 측정 합계의 차이입니다. 삭제 가능 용량이 아닙니다." : "")
        } else {
            Button { activate(band) } label: {
                labelContent(band).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityDescription(band, total: total))
            .accessibilityHint(band.kind == .grouped ? "포함된 영역 목록을 엽니다" : "해당 영역의 사용량으로 이동합니다")
            .accessibilityAddTraits(isSelected(band) ? .isSelected : [])
            .help(band.areas.count == 1 ? "\(band.areas[0].path) · \(band.formattedBytes)" : "포함된 영역 보기")
            .popover(isPresented: band.kind == .grouped ? $showOther : .constant(false)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("기타 영역").font(.headline)
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(band.areas) { area in
                                Button { showOther = false; select(area.path) } label: {
                                    HStack {
                                        Text(area.name)
                                        Spacer()
                                        Text(area.allocatedBytes.storageFormatted).monospacedDigit()
                                    }.frame(maxWidth: .infinity).padding(6).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }.frame(maxHeight: 300)
                }.padding(16).frame(width: 300)
            }
        }
    }

    private func labelContent(_ band: CoreStorageBreakdown.Band) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(band.name).font(.system(size: 10, weight: isSelected(band) ? .semibold : .medium))
                .foregroundStyle(band.kind == .free ? StrataTheme.secondary :
                    [StrataTheme.successText, StrataTheme.accentText, StrataTheme.warningText, StrataTheme.infoText, StrataTheme.secondary][band.texture % 5])
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 3) {
                Text(band.formattedBytes).font(.system(size: 10, design: .monospaced))
                if band.kind == .grouped { Image(systemName: "chevron.right").font(.system(size: 8)) }
            }
            .foregroundStyle(StrataTheme.secondary)
        }
        .foregroundStyle(isSelected(band) ? (colorScheme == .dark ? accent(band.texture) : StrataTheme.primary) : StrataTheme.primary)
    }

    private func notes(_ data: CoreStorageBreakdown) -> some View {
        HStack {
            if let progress {
                Text("측정 중 · \(progress.measuredBytes.storageFormatted)")
            } else if let snapshot {
                Text("\(snapshot.finishedAt.formatted(date: .omitted, time: .shortened)) 측정")
            }
            Spacer()
            Button { showMeasurementInfo.toggle() } label: {
                Image(systemName: "info.circle").frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("용량 측정 기준")
            .popover(isPresented: $showMeasurementInfo) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("용량 측정 기준").font(.headline)
                    Text(data.isMeasuredOnly ? "디스크 사용량과 폴더 측정 합계의 기준이 달라 측정 영역만 표시합니다." : "두께는 전체 용량에서 차지하는 비율입니다. 확인된 별도 볼륨은 시스템 공간으로, 남은 차이는 아직 설명되지 않은 공간으로 구분합니다.")
                    Text("미분류 공간에는 접근 제한, 스냅샷, 파일 시스템의 측정 차이 등이 영향을 줄 수 있습니다. 권한을 허용해도 모두 분류된다고 보장할 수 없습니다.")
                    Text("층의 깊이나 질감은 파일 나이·삭제 안전도를 뜻하지 않습니다.")
                }.padding(20).frame(width: 300)
            }
        }
        .font(.caption2).foregroundStyle(StrataTheme.secondary)
    }

    private func accessibilityDescription(_ band: CoreStorageBreakdown.Band, total: Double) -> String {
        "\(band.name), \(band.formattedBytes), \(breakdown?.isMeasuredOnly == true ? "측정 합계" : "전체 용량")의 \((band.bytes / total).formatted(.percent.precision(.fractionLength(1))))"
    }

    private func isSelected(_ band: CoreStorageBreakdown.Band) -> Bool {
        band.areas.contains { $0.path == selectedPath }
    }

    private func activate(_ band: CoreStorageBreakdown.Band) {
        guard progress == nil else { return }
        if band.kind == .grouped { showOther = true }
        else if band.kind == .systemVolumes || band.kind == .unmeasured { showSpaceDetails = true }
        else if let area = band.areas.first { select(area.path) }
    }

    private func accent(_ index: Int) -> Color {
        [StrataTheme.lichen, StrataTheme.glacier, StrataTheme.amber, StrataTheme.slate, StrataTheme.basalt][index % 5]
    }
}

private struct RockHatching: View {
    let pattern: Int
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for y in stride(from: 0.0, to: size.height, by: 10) {
                for x in stride(from: 0.0, to: size.width, by: 16) {
                    switch pattern {
                    case 0:
                        path.addEllipse(in: CGRect(x: x + 2, y: y + 2, width: 1.5, height: 1.5))
                        path.addEllipse(in: CGRect(x: x + 10, y: y + 7, width: 1, height: 1))
                    case 1:
                        path.move(to: CGPoint(x: x + 2, y: y + 5))
                        path.addLines([CGPoint(x: x + 5, y: y + 2), CGPoint(x: x + 8, y: y + 4), CGPoint(x: x + 6, y: y + 7)])
                        path.closeSubpath()
                    case 2:
                        path.move(to: CGPoint(x: x, y: y + 3)); path.addLine(to: CGPoint(x: x + 10, y: y + 3))
                        path.move(to: CGPoint(x: x + 11, y: y + 7)); path.addLine(to: CGPoint(x: x + 15, y: y + 7))
                    case 3:
                        path.move(to: CGPoint(x: x, y: y + 6))
                        path.addQuadCurve(to: CGPoint(x: x + 8, y: y + 6), control: CGPoint(x: x + 4, y: y))
                        path.addQuadCurve(to: CGPoint(x: x + 16, y: y + 6), control: CGPoint(x: x + 12, y: y + 12))
                    case 4:
                        path.move(to: CGPoint(x: x, y: y + 4))
                        path.addLines([CGPoint(x: x + 6, y: y), CGPoint(x: x + 13, y: y + 5), CGPoint(x: x + 16, y: y + 2)])
                    default:
                        path.move(to: CGPoint(x: x, y: y + 5)); path.addLine(to: CGPoint(x: x + 3, y: y + 5))
                    }
                }
            }
            context.stroke(path, with: .foreground, lineWidth: 0.8)
        }
        .accessibilityHidden(true)
    }
}
