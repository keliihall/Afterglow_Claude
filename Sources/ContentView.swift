import SwiftUI

/// Minimal translucent surface showing the real Claude plan usage: how much of
/// the rolling 5-hour and weekly windows remains. Drag anywhere to move.
struct ContentView: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var settings: AppSettings

    private let labelColor = Color.white.opacity(0.45)
    private let valueColor = Color.white.opacity(0.95)
    private let dimColor = Color.white.opacity(0.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            if model.rows.isEmpty {
                Text(model.status.isEmpty ? "暂无数据" : model.status)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.orange.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.rows) { row in usageRow(row) }
            }
            footer
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 176, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .opacity(settings.opacity)
    }

    private var background: some View {
        Group {
            if settings.frosted {
                VisualEffectView(material: .hudWindow).overlay(Color.black.opacity(0.38))
            } else {
                Color.black.opacity(0.62)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("Claude 余量")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(labelColor)
                .tracking(0.3)
            if !model.tier.isEmpty {
                Text(model.tier.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            Spacer(minLength: 0)
            Circle().fill(statusColor).frame(width: 6, height: 6)
        }
    }

    private func usageRow(_ row: UsageRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(dimColor)
                    .frame(minWidth: 18, alignment: .leading)
                Spacer(minLength: 0)
                Text("\(Int(row.remaining.rounded()))%")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(valueColor)
                    .monospacedDigit()
                Text("余")
                    .font(.system(size: 8.5, weight: .regular, design: .rounded))
                    .foregroundColor(labelColor)
                    .baselineOffset(0)
            }
            bar(remaining: row.remaining)
            if !Fmt.reset(row.resetsAt).isEmpty {
                Text(Fmt.reset(row.resetsAt))
                    .font(.system(size: 8.5, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.32))
            }
        }
        .help("\(row.label)：已用 \(Int(row.usedPercent.rounded()))%，剩余 \(Int(row.remaining.rounded()))%" +
              (row.resetsAt != nil ? "，\(Fmt.reset(row.resetsAt))" : ""))
    }

    private func bar(remaining: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(barColor(remaining))
                    .frame(width: max(3, geo.size.width * CGFloat(remaining / 100)))
            }
        }
        .frame(height: 4)
    }

    private func barColor(_ remaining: Double) -> Color {
        if remaining >= 40 { return Color(red: 0.34, green: 0.80, blue: 0.50) }
        if remaining >= 15 { return Color(red: 0.96, green: 0.72, blue: 0.25) }
        return Color(red: 0.96, green: 0.38, blue: 0.34)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Text(updatedText)
                .font(.system(size: 8.5, weight: .regular, design: .rounded))
                .foregroundColor(Color.white.opacity(0.3))
            if !model.status.isEmpty && !model.rows.isEmpty {
                Text("· \(model.status)")
                    .font(.system(size: 8.5, weight: .regular, design: .rounded))
                    .foregroundColor(.orange.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
    }

    private var statusColor: Color {
        if !model.ok { return .red.opacity(0.8) }
        guard let u = model.lastUpdated else { return .yellow.opacity(0.8) }
        return Date().timeIntervalSince(u) < 180 ? .green.opacity(0.85) : .yellow.opacity(0.8)
    }

    private var updatedText: String {
        guard let d = model.lastUpdated else { return "—" }
        return "更新 \(Fmt.clock(d))"
    }
}
