import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color?
    
    init(title: String, value: String, icon: String, color: Color? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
    }
    
    var body: some View {
        if let color = color {
            // Colored version (used in ContentView)
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(10)
        } else {
            // Default version (used in DriveDetailView)
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

// MARK: - Shimmer / Skeleton loading

/// A view modifier that overlays a shimmering highlight to indicate loading.
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.35), location: 0.4),
                            .init(color: .clear, location: 0.8),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: phase * geo.size.width * 2)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

/// A rounded rectangle placeholder that pulses while content loads.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
            .shimmer()
    }
}

/// Skeleton row that mimics a leaderboard entry while loading.
struct LeaderboardSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: 28, height: 20)
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 36, height: 36)
                .shimmer()
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 120, height: 14)
                SkeletonBlock(width: 80, height: 12)
            }
            Spacer()
            SkeletonBlock(width: 60, height: 20)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Skeleton card that mimics a stat card while loading.
struct StatCardSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            SkeletonBlock(width: 24, height: 24, cornerRadius: 4)
            SkeletonBlock(width: 50, height: 12)
            SkeletonBlock(width: 70, height: 18)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
