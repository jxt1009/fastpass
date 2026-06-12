import SwiftUI

// MARK: - CarDetailStyleGuide

struct CarDetailStyleGuide: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                ForEach(DrivingStyle.guideStyles, id: \.self) { style in
                    HStack(alignment: .top, spacing: 12) {
                        DrivingStyleBadge(style: style)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(style.title)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(style.detailedExplanation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Driving Style Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - ConfettiOverlay

struct ConfettiOverlay: View {
    let show: Bool

    var body: some View {
        if show {
            ConfettiView()
                .frame(height: 600)
                .ignoresSafeArea(edges: .top)
        }
    }
}
