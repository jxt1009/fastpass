import SwiftUI

/// Two-column LazyVGrid wrapper for stat cells. Replaces 10+ ad-hoc
/// `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
/// spacing: N)` usages. The cell content is generic; pass whatever
/// view each site uses (InstrumentStatCell, StatMini, FTGauge compact,
/// PerformanceStatCard, etc.).
///
/// The grid is single-row when `cells.count <= 2` and 2-row otherwise
/// (2×2 for 4 cells, 2×3 for 6, etc.).
struct StatsGrid<Content: View>: View {
    let spacing: CGFloat
    let columns: [GridItem]
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 10,
         columns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())],
         @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.columns = columns
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            content()
        }
    }
}
