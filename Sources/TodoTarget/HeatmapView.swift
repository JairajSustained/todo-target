import SwiftUI
import AppKit
import TodoTargetCore

/// Yearly heatmap: one column per week, 7 rows. Colours match the menu bar icon.
struct HeatmapView: View {
    let heatmap: HeatmapModel

    // Sized so 53 columns fit the panel's content width (568 pt).
    static let cell: CGFloat = 9
    static let gap: CGFloat = 1.5
    private var pitch: CGFloat { Self.cell + Self.gap }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(heatmap.columns.indices, id: \.self) { c in
                    VStack(spacing: Self.gap) {
                        ForEach(0..<7, id: \.self) { r in
                            cellView(heatmap.columns[c][r])
                        }
                    }
                }
            }
            // Month names sit under the columns where a month starts.
            ZStack(alignment: .topLeading) {
                Color.clear.frame(height: 11)
                ForEach(heatmap.monthLabels.indices, id: \.self) { i in
                    Text(heatmap.monthLabels[i].name)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .offset(x: CGFloat(heatmap.monthLabels[i].column) * pitch)
                }
            }
            .frame(width: CGFloat(heatmap.columns.count) * pitch, alignment: .leading)
        }
    }

    @ViewBuilder
    private func cellView(_ cell: HeatmapCell?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2)
        if let cell {
            switch cell.kind {
            case .future:
                shape.fill(Color.clear).frame(width: Self.cell, height: Self.cell)
                    .overlay { if cell.isToday { shape.stroke(Color.primary, lineWidth: 1.5) } }
                    .help(cell.tooltip)
            case .beforeStart:
                shape.fill(Color.gray.opacity(0.25)).frame(width: Self.cell, height: Self.cell)
                    .help(cell.tooltip)
            case .day(let level):
                shape.fill(Color(nsColor: IconRenderer.color(level: level)))
                    .frame(width: Self.cell, height: Self.cell)
                    .overlay {
                        if cell.savedByCatchUp {
                            Circle().fill(Color.white).frame(width: 3.5, height: 3.5)
                        }
                    }
                    .overlay { if cell.isToday { shape.stroke(Color.primary, lineWidth: 1.5) } }
                    .help(cell.tooltip)
            }
        } else {
            Color.clear.frame(width: Self.cell, height: Self.cell)
        }
    }
}
